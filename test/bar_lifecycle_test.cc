#include "../linux/runner/my_application.cc"

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

int main(int argc, char** argv) {
  g_autoptr(MyApplication) app = my_application_new();
  g_timeout_add(500, check_monitor_lifecycle, app);
  int status = g_application_run(G_APPLICATION(app), argc, argv);
  g_assert_cmpuint(g_hash_table_size(app->bar_windows), ==, 0);
  return status;
}
