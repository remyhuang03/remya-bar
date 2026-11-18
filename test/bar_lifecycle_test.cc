#include "../linux/runner/bar_icons.cc"
#include "../linux/runner/my_application.cc"
#include "../linux/runner/bar_popup.cc"
#include "../linux/runner/bar_popup_keyboard.cc"

static guint released_bars = 0;
static guint output_restart_requests = 0;
static constexpr int kInitialTooltipHeight = 80;

static void check_view_role(MyApplication* self, FlView* view, const char* role) {
  g_autoptr(FlValue) snapshot = self->views->snapshot();
  auto* views = fl_value_lookup_string(snapshot, "views");
  g_autofree gchar* id = g_strdup_printf("%" G_GINT64_FORMAT, fl_view_get_id(view));
  auto* value = fl_value_lookup_string(views, id);
  if (role == nullptr) g_assert_null(value);
  else g_assert_cmpstr(fl_value_get_string(value), ==, role);
}

static void show_test_tooltip(BarPopup* popup, const char* message) {
  create_popup(popup, false, false, true, false);
  g_autoptr(FlValue) args = fl_value_new_map();
  g_autoptr(FlValue) details = fl_value_new_map();
  fl_value_set_string_take(args, "kind", fl_value_new_string("tooltip"));
  g_autoptr(FlValue) theme = fl_value_new_map();
  fl_value_set_string_take(theme, "version", fl_value_new_int(1));
  fl_value_set_string(args, "theme", theme);
  fl_value_set_string_take(details, "scale", fl_value_new_float(1.0));
  fl_value_set_string_take(details, "message", fl_value_new_string(message));
  fl_value_set_string(args, "data", details);
  replace_content(popup, args, true);
  popup->visible = true;
  popup->width = 200;
  gtk_widget_set_size_request(GTK_WIDGET(popup->view), popup->width, kInitialTooltipHeight);
  gtk_window_resize(GTK_WINDOW(popup->window), popup->width, kInitialTooltipHeight);
  gtk_widget_show_all(popup->window);
}

static bool check_popup_views(MyApplication* app, FlView* owner) {
  auto* root = static_cast<BarPopup*>(g_object_get_data(G_OBJECT(owner), "remya-popup"));
  auto* engine_window = app->engine_host;
  g_assert_false(gtk_widget_get_mapped(engine_window));
  auto* implicit_view = FL_VIEW(gtk_bin_get_child(GTK_BIN(engine_window)));
  auto* engine = fl_view_get_engine(implicit_view);
  g_assert_true(fl_view_get_engine(owner) == engine);
  check_view_role(app, implicit_view, nullptr);
  check_view_role(app, owner, "bar");
  auto* tooltip = child_popup(root, root->tooltip_popup);
  static gint64 deadline = 0;
  if (deadline == 0) {
    show_test_tooltip(root, "First view");
    show_test_tooltip(tooltip, "Second view");
    g_assert_true(fl_view_get_engine(root->view) == engine);
    g_assert_true(fl_view_get_engine(tooltip->view) == engine);
    check_view_role(app, root->view, "popup");
    check_view_role(app, tooltip->view, "popup");
    g_assert_cmpint(fl_view_get_id(root->view), !=, fl_view_get_id(tooltip->view));
    deadline = g_get_monotonic_time() + 10 * G_TIME_SPAN_SECOND;
    return false;
  }

  // The first rendered tooltip content triggers Dart's measurement and a
  // native resize. Each view must have completed its own channel handshake.
  if (g_get_monotonic_time() < deadline &&
      (!root->ready || !tooltip->ready ||
       gtk_widget_get_allocated_height(GTK_WIDGET(root->view)) >= kInitialTooltipHeight ||
       gtk_widget_get_allocated_height(GTK_WIDGET(tooltip->view)) >= kInitialTooltipHeight)) {
    return false;
  }
  g_assert_true(root->ready);
  g_assert_true(tooltip->ready);
  g_assert_cmpint(gtk_widget_get_allocated_height(GTK_WIDGET(root->view)), <, kInitialTooltipHeight);
  g_assert_cmpint(gtk_widget_get_allocated_height(GTK_WIDGET(tooltip->view)), <, kInitialTooltipHeight);
  const auto first_id = fl_view_get_id(root->view);
  guint released_channels = 0;
  auto watch_channel = [&released_channels](BarPopup* popup) {
    g_object_weak_ref(G_OBJECT(popup->channel),
        [](gpointer data, GObject*) { ++*static_cast<guint*>(data); },
        &released_channels);
  };
  watch_channel(root);
  root->hide();
  g_assert_null(root->window);
  g_assert_null(root->view);
  g_assert_null(root->content);
  g_assert_true(tooltip->visible);
  g_assert_true(tooltip->ready);
  for (int iteration = 0; iteration < 5; ++iteration) {
    create_popup(root, false, false, true, false);
    watch_channel(root);
    root->hide();
  }
  g_assert_cmpuint(released_channels, ==, 6);
  show_test_tooltip(root, "Reopened view");
  g_assert_cmpint(fl_view_get_id(root->view), >, first_id);
  g_print("PASS: concurrent popup content, independent dismissal and fresh view ID\n");
  // Leave both popups open to exercise the synthetic monitor removal below.
  return true;
}

static void check_settings_window(MyApplication* self) {
  open_settings(self, "layout");
  auto* first = FL_VIEW(gtk_bin_get_child(GTK_BIN(self->settings_window)));
  const auto first_id = fl_view_get_id(first);
  g_assert_true(fl_view_get_engine(first) == self->engine);
  check_view_role(self, first, "settings");
  g_assert_false(gtk_layer_is_layer_window(GTK_WINDOW(self->settings_window)));
  g_assert_cmpstr(gtk_window_get_title(GTK_WINDOW(self->settings_window)), ==, "Remy'a Bar Settings");
  open_settings(self, "notifications");
  g_assert_true(first == FL_VIEW(gtk_bin_get_child(GTK_BIN(self->settings_window))));
  // The ready engine receives the page immediately, clearing the pending request.
  g_assert_null(self->settings_page);
  gtk_widget_destroy(self->settings_window);
  g_assert_null(self->settings_window);
  g_assert_true(gtk_widget_get_realized(self->engine_host));
  open_settings(self, "ai-ring");
  auto* reopened = FL_VIEW(gtk_bin_get_child(GTK_BIN(self->settings_window)));
  g_assert_cmpint(fl_view_get_id(reopened), >, first_id);
  g_assert_true(fl_view_get_engine(reopened) == self->engine);
  gtk_widget_destroy(self->settings_window);
  g_assert_null(self->settings_window);
  g_assert_true(valid_settings_page("quiet-schedule"));
  g_assert_true(valid_settings_page("material-theme"));
  g_assert_true(valid_settings_page("account"));
  g_assert_false(valid_settings_page("../invalid"));
  g_assert_false(valid_settings_page("layout\n"));
  g_print("PASS: normal settings window, page reuse, close/reopen with warm engine\n");
}

static gboolean check_monitor_lifecycle(gpointer data) {
  auto* self = MY_APPLICATION(data);
  GdkDisplay* display = gdk_display_get_default();
  const int count = gdk_display_get_n_monitors(display);
  g_assert_cmpint(count, >, 0);
  static gint64 release_deadline = 0;
  static int64_t previous_view_id = 0;
  static bool checked_recovery = false;

  if (release_deadline == 0) {
    g_assert_cmpuint(g_hash_table_size(self->bar_windows), ==, count);
    auto* monitor = gdk_display_get_monitor(display, 0);
    auto* window = GTK_BIN(g_hash_table_lookup(self->bar_windows, monitor));
    if (!check_popup_views(self, FL_VIEW(gtk_bin_get_child(window)))) {
      return G_SOURCE_CONTINUE;
    }
    check_settings_window(self);
    // Emit client-side GDK events without changing the desktop's outputs.
    for (int index = 0; index < count; index++) {
      GdkMonitor* monitor = gdk_display_get_monitor(display, index);
      g_signal_emit_by_name(display, "monitor-added", monitor);
    }
    g_assert_cmpuint(g_hash_table_size(self->bar_windows), ==, count);
    g_assert_cmpuint(self->output_restart, ==, 0);
    for (int index = 0; index < count; index++) {
      GdkMonitor* monitor = gdk_display_get_monitor(display, index);
      auto* window = GTK_BIN(g_hash_table_lookup(self->bar_windows, monitor));
      auto* view = FL_VIEW(gtk_bin_get_child(window));
      g_assert_true(fl_view_get_engine(view) == self->engine);
      check_view_role(self, view, "bar");
      previous_view_id = MAX(previous_view_id, fl_view_get_id(view));
      g_object_weak_ref(
          G_OBJECT(view),
          [](gpointer data, GObject* object) { ++*static_cast<guint*>(data); },
          &released_bars);
      g_signal_emit_by_name(display, "monitor-removed", monitor);
      g_signal_emit_by_name(display, "monitor-removed", monitor);
    }
    g_assert_cmpuint(g_hash_table_size(self->bar_windows), ==, 0);
    g_autoptr(FlValue) snapshot = self->views->snapshot();
    g_assert_cmpuint(fl_value_get_length(fl_value_lookup_string(snapshot, "views")), ==, 0);
    g_assert_cmpuint(self->output_restart, !=, 0);
    for (int index = 0; index < count; index++) {
      g_signal_emit_by_name(display, "monitor-added", gdk_display_get_monitor(display, index));
    }
    g_assert_cmpuint(g_hash_table_size(self->bar_windows), ==, 0);
    g_assert_cmpuint(output_restart_requests, ==, 0);
    release_deadline = g_get_monotonic_time() + 10 * G_TIME_SPAN_SECOND;
    return G_SOURCE_CONTINUE;
  }

  if (released_bars < static_cast<guint>(count) || output_restart_requests == 0) {
    g_assert_cmpint(g_get_monotonic_time(), <, release_deadline);
    return G_SOURCE_CONTINUE;
  }
  g_assert_true(gtk_widget_get_realized(self->engine_host));
  g_assert_false(gtk_widget_get_mapped(self->engine_host));
  if (!checked_recovery) {
    checked_recovery = true;
    g_assert_cmpuint(g_hash_table_size(self->bar_windows), ==, count);
    for (int index = 0; index < count; index++) {
      GdkMonitor* monitor = gdk_display_get_monitor(display, index);
      auto* window = GTK_BIN(g_hash_table_lookup(self->bar_windows, monitor));
      auto* view = FL_VIEW(gtk_bin_get_child(window));
      g_assert_true(fl_view_get_engine(view) == self->engine);
      g_assert_cmpint(fl_view_get_id(view), >, previous_view_id);
      check_view_role(self, view, "bar");
    }
    g_application_activate(G_APPLICATION(self));
    g_assert_cmpuint(g_hash_table_size(self->bar_windows), ==, count);
    g_assert_cmpuint(g_list_length(gtk_application_get_windows(GTK_APPLICATION(self))), ==, count);
    g_assert_cmpuint(output_restart_requests, ==, 1);
    GdkMonitor* monitor = gdk_display_get_monitor(display, 0);
    g_object_notify(G_OBJECT(monitor), "scale-factor");
    g_object_notify(G_OBJECT(monitor), "scale-factor");
    g_print("PASS: hotplug requests one graphics restart and recreates views if exec returns\n");
    return G_SOURCE_CONTINUE;
  }
  g_assert_cmpuint(output_restart_requests, ==, 2);
  g_print("PASS: scale recovery remains debounced\n");
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
  g_autoptr(MyApplication) app = nullptr;
  app = my_application_new(
      [](const char* reason, gpointer) {
        g_assert_cmpstr(reason, ==, "Display topology or scale changed");
        ++output_restart_requests;
      }, nullptr);
  g_timeout_add(500, check_monitor_lifecycle, app);
  int status = g_application_run(G_APPLICATION(app), argc, argv);
  g_assert_cmpuint(g_hash_table_size(app->bar_windows), ==, 0);
  return status;
}
