#include "../linux/runner/bar_icons.cc"
#include "../linux/runner/my_application.cc"
#include "../linux/runner/bar_popup.cc"

static guint released_engines = 0;

static gboolean check_monitor_lifecycle(gpointer data) {
  auto* self = MY_APPLICATION(data);
  GdkDisplay* display = gdk_display_get_default();
  const int count = gdk_display_get_n_monitors(display);
  g_assert_cmpint(count, >, 0);
  static bool removed = false;

  if (!removed) {
    g_assert_cmpuint(g_hash_table_size(self->bar_windows), ==, count);
    // Emit client-side GDK events without changing the desktop's outputs.
    for (int index = 0; index < count; index++) {
      GdkMonitor* monitor = gdk_display_get_monitor(display, index);
      g_signal_emit_by_name(display, "monitor-added", monitor);
    }
    g_assert_cmpuint(g_hash_table_size(self->bar_windows), ==, count);
    for (int index = 0; index < count; index++) {
      GdkMonitor* monitor = gdk_display_get_monitor(display, index);
      auto* window = GTK_BIN(g_hash_table_lookup(self->bar_windows, monitor));
      auto* view = FL_VIEW(gtk_bin_get_child(window));
      g_object_weak_ref(
          G_OBJECT(fl_view_get_engine(view)),
          [](gpointer data, GObject* object) { ++*static_cast<guint*>(data); },
          &released_engines);
      g_signal_emit_by_name(display, "monitor-removed", monitor);
      g_signal_emit_by_name(display, "monitor-removed", monitor);
    }
    g_assert_cmpuint(g_hash_table_size(self->bar_windows), ==, 0);
    removed = true;
    return G_SOURCE_CONTINUE;
  }

  // Reaching this next timer tick also verifies survival with no bar windows.
  g_assert_cmpuint(released_engines, ==, count);
  for (int index = 0; index < count; index++) {
    g_signal_emit_by_name(display, "monitor-added",
                          gdk_display_get_monitor(display, index));
  }
  g_application_activate(G_APPLICATION(self));
  g_assert_cmpuint(g_hash_table_size(self->bar_windows), ==, count);
  g_assert_cmpuint(
      g_list_length(gtk_application_get_windows(GTK_APPLICATION(self))), ==,
      count);
  g_print(
      "PASS: duplicate add/remove, all outputs removed, reconnect, and "
      "reactivation\n");
  g_application_quit(G_APPLICATION(self));
  return G_SOURCE_REMOVE;
}

// These protocol/state checks do not initialize GTK or map a desktop surface.
static void check_popup_content() {
  for (const char* kind : {"media", "battery", "datetime", "resources"}) {
    g_assert_true(is_card(kind));
    BarPopup popup{nullptr};
    popup.pill_left = 81;
    popup.pill_width = 140;
    g_autoptr(FlValue) args = fl_value_new_map();
    g_autoptr(FlValue) details = fl_value_new_map();
    fl_value_set_string_take(args, "kind", fl_value_new_string(kind));
    fl_value_set_string_take(args, "opening", fl_value_new_bool(true));
    fl_value_set_string_take(details, "sample", fl_value_new_int(1));
    fl_value_set_string(args, "data", details);
    replace_content(&popup, args, true);
    auto* pill = fl_value_lookup_string(fl_value_lookup_string(popup.content, "data"), "pill");
    g_assert_cmpint(fl_value_get_int(fl_value_get_list_value(pill, 0)), ==, 81);
    g_assert_cmpint(fl_value_get_int(fl_value_get_list_value(pill, 1)), ==, 140);
    g_assert_null(fl_value_lookup_string(details, "pill"));
    g_assert_true(fl_value_get_bool(fl_value_lookup_string(args, "opening")));
    fl_value_set_string_take(details, "sample", fl_value_new_int(2));
    replace_content(&popup, args, false);
    g_assert_false(fl_value_get_bool(fl_value_lookup_string(popup.content, "opening")));
    g_assert_cmpint(fl_value_get_int(fl_value_lookup_string(
        fl_value_lookup_string(popup.content, "data"), "sample")), ==, 2);
    popup.monitor_width = 1000;
    popup.width = 500;
    for (const auto& placement : std::vector<std::pair<int, int>>{{0, 0}, {450, 180}, {860, 360}}) {
      g_autoptr(FlValue) anchor = fl_value_new_list();
      for (int value : {placement.first, 0, 140, 40})
        fl_value_append_take(anchor, fl_value_new_int(value));
      fl_value_set_string(args, "anchor", anchor);
      replace_content(&popup, args, false);
      g_assert_cmpint(popup.pill_left, ==, placement.second);
      g_assert_cmpint(popup.pill_width, ==, 140);
    }
    popup.dismissing = true;
    popup.hide_timer = g_timeout_add(10000, [](gpointer) -> gboolean {
      g_assert_not_reached();
      return G_SOURCE_REMOVE;
    }, nullptr);
    popup.dismiss_timer = g_timeout_add(10000, [](gpointer) -> gboolean {
      g_assert_not_reached();
      return G_SOURCE_REMOVE;
    }, nullptr);
    const guint fallback = popup.dismiss_timer;
    popup.enter();
    g_assert_false(popup.dismissing);
    g_assert_cmpuint(popup.hide_timer, ==, 0);
    g_assert_cmpuint(popup.dismiss_timer, ==, 0);
    g_assert_null(g_main_context_find_source_by_id(nullptr, fallback));
    g_assert_false(fl_value_get_bool(fl_value_lookup_string(popup.content, "opening")));
  }
  for (const char* kind : {"tooltip", "tray-menu", "workspace-overview", "sidebar"})
    g_assert_false(is_card(kind));
  g_print("PASS: card content copies, pill geometry, updates, and dismiss cancellation\n");
}

int main(int argc, char** argv) {
  check_popup_content();
  if (argc == 2 && g_strcmp0(argv[1], "--popup-only") == 0) return 0;
  const auto desktop_id = normalized("Code.desktop");
  const auto app_id = normalized("com.Example.App");
  g_assert_cmpstr(desktop_id.c_str(), ==, "code");
  g_assert_cmpstr(app_id.c_str(), ==, "com.example.app");
  g_autoptr(MyApplication) app = my_application_new();
  g_timeout_add(500, check_monitor_lifecycle, app);
  int status = g_application_run(G_APPLICATION(app), argc, argv);
  g_assert_cmpuint(g_hash_table_size(app->bar_windows), ==, 0);
  return status;
}
