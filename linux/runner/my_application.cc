#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk-layer-shell.h>

#include "bar_popup.h"
#include "bar_icons.h"
#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GHashTable* bar_windows;
  GDBusConnection* shortcut_bus;
  guint shortcut_subscription;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static FlValue* output_geometry(GdkMonitor* monitor) {
  GdkRectangle geometry;
  gdk_monitor_get_geometry(monitor, &geometry);
  FlValue* result = fl_value_new_map();
  fl_value_set_string_take(result, "x", fl_value_new_int(geometry.x));
  fl_value_set_string_take(result, "y", fl_value_new_int(geometry.y));
  fl_value_set_string_take(result, "width", fl_value_new_int(geometry.width));
  fl_value_set_string_take(result, "height", fl_value_new_int(geometry.height));
  return result;
}

static bool perf_enabled() {
  return g_strcmp0(g_getenv("REMYA_BAR_PERF"), "1") == 0;
}

static void set_bar_fullscreen(GtkWindow* window, bool fullscreen) {
  if (fullscreen == (g_object_get_data(G_OBJECT(window), "fullscreen") != nullptr)) return;
  g_object_set_data(G_OBJECT(window), "fullscreen", fullscreen ? GINT_TO_POINTER(1) : nullptr);
  if (fullscreen) {
    hide_bar_popup(FL_VIEW(gtk_bin_get_child(GTK_BIN(window))));
    gtk_layer_set_exclusive_zone(window, 0);
    gtk_widget_hide(GTK_WIDGET(window));
  } else {
    if (!perf_enabled()) gtk_layer_auto_exclusive_zone_enable(window);
    gtk_widget_show(GTK_WIDGET(window));
  }
}

static void create_bar_window(MyApplication* self, GdkMonitor* monitor) {
  if (g_hash_table_contains(self->bar_windows, monitor)) return;
  if (perf_enabled()) {
    const char* output = g_getenv("REMYA_BAR_PERF_OUTPUT_X");
    GdkRectangle geometry;
    gdk_monitor_get_geometry(monitor, &geometry);
    if (output != nullptr && geometry.x != g_ascii_strtoll(output, nullptr, 10)) return;
  }

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(self)));
  g_hash_table_insert(self->bar_windows, g_object_ref(monitor),
                      g_object_ref(window));
  gtk_window_set_title(window, "Remy'a Bar");
  gtk_window_set_decorated(window, FALSE);
  gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);
  GdkVisual* visual = gdk_screen_get_rgba_visual(gtk_window_get_screen(window));
  if (visual != nullptr) gtk_widget_set_visual(GTK_WIDGET(window), visual);
  gtk_widget_set_size_request(GTK_WIDGET(window), -1, 40);

  gtk_layer_init_for_window(window);
  gtk_layer_set_namespace(window, perf_enabled() ? "remya-bar-profiling" : APPLICATION_ID);
  gtk_layer_set_monitor(window, monitor);
  gtk_layer_set_layer(window, GTK_LAYER_SHELL_LAYER_TOP);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_TOP, TRUE);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_LEFT, TRUE);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_RIGHT, TRUE);
  gtk_layer_set_keyboard_mode(window, GTK_LAYER_SHELL_KEYBOARD_MODE_NONE);
  if (perf_enabled()) gtk_layer_set_exclusive_zone(window, 0);
  else gtk_layer_auto_exclusive_zone_enable(window);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  if (perf_enabled() && g_getenv("REMYA_BAR_PERF_SKIA") != nullptr)
    fl_dart_project_set_enable_impeller(project, FALSE);

  FlView* view = fl_view_new(project);
  const GdkRGBA transparent = {0, 0, 0, 0};
  fl_view_set_background_color(view, &transparent);
  register_bar_popup(view);
  register_bar_icons(view);
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  g_autoptr(FlStandardMethodCodec) window_codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) window_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)), "top.remya.bar/window",
      FL_METHOD_CODEC(window_codec));
  g_object_set_data_full(G_OBJECT(view), "window-channel", g_object_ref(window_channel), g_object_unref);
  fl_method_channel_set_method_call_handler(
      window_channel,
      [](FlMethodChannel* channel, FlMethodCall* call, gpointer data) {
        auto* monitor = GDK_MONITOR(data);
        const char* method = fl_method_call_get_name(call);
        if (g_strcmp0(method, "output") == 0) {
          g_autoptr(FlValue) geometry = output_geometry(monitor);
          fl_method_call_respond_success(call, geometry, nullptr);
        } else if (g_strcmp0(method, "setFullscreen") == 0) {
          FlValue* value = fl_method_call_get_args(call);
          if (fl_value_get_type(value) != FL_VALUE_TYPE_BOOL) {
            fl_method_call_respond_error(call, "invalid-arguments", "Expected fullscreen boolean", nullptr, nullptr);
            return;
          }
          auto* view = GTK_WIDGET(g_object_get_data(G_OBJECT(channel), "owner"));
          auto* window = GTK_WINDOW(gtk_widget_get_toplevel(view));
          set_bar_fullscreen(window, fl_value_get_bool(value));
          fl_method_call_respond_success(call, nullptr, nullptr);
        } else {
          fl_method_call_respond_not_implemented(call, nullptr);
        }
      },
      g_object_ref(monitor), g_object_unref);
  g_object_set_data(G_OBJECT(window_channel), "owner", view);
  g_signal_connect_object(monitor, "notify::geometry",
      G_CALLBACK(+[](GdkMonitor* monitor, GParamSpec*, FlMethodChannel* channel) {
        g_autoptr(FlValue) geometry = output_geometry(monitor);
        fl_method_channel_invoke_method(channel, "outputChanged", geometry, nullptr, nullptr, nullptr);
      }), window_channel, G_CONNECT_DEFAULT);
  g_autoptr(FlStandardMethodCodec) paths_codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) paths_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)), "top.remya.paths",
      FL_METHOD_CODEC(paths_codec));
  fl_method_channel_set_method_call_handler(
      paths_channel,
      [](FlMethodChannel* channel, FlMethodCall* call, gpointer data) {
        if (g_strcmp0(fl_method_call_get_name(call), "repositoryDirectory") == 0) {
          g_autoptr(FlValue) root = fl_value_new_string(REMYA_REPOSITORY_DIR);
          fl_method_call_respond_success(call, root, nullptr);
        } else {
          fl_method_call_respond_not_implemented(call, nullptr);
        }
      },
      nullptr, nullptr);

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  gtk_widget_show_all(GTK_WIDGET(window));
}

static void monitor_added(GdkDisplay* display, GdkMonitor* monitor,
                          MyApplication* self) {
  create_bar_window(self, monitor);
}

static void monitor_removed(GdkDisplay* display, GdkMonitor* monitor,
                            MyApplication* self) {
  bar_popup_monitor_removed(monitor);
  auto* window = GTK_WIDGET(g_hash_table_lookup(self->bar_windows, monitor));
  if (window == nullptr) return;
  gtk_widget_destroy(window);
  g_hash_table_remove(self->bar_windows, monitor);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GdkDisplay* display = gdk_display_get_default();
  for (int index = 0; index < gdk_display_get_n_monitors(display); index++) {
    create_bar_window(self, gdk_display_get_monitor(display, index));
  }
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  if (!gtk_layer_is_supported()) {
    g_printerr(
        "Remy'a Bar requires a Wayland compositor with layer-shell support.\n");
    *exit_status = 1;
    return TRUE;
  }

  // Keep display event handling alive while all outputs are disconnected.
  g_application_hold(application);
  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
  GdkDisplay* display = gdk_display_get_default();
  MyApplication* self = MY_APPLICATION(application);
  self->shortcut_bus = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, nullptr);
  if (self->shortcut_bus != nullptr) {
    self->shortcut_subscription = g_dbus_connection_signal_subscribe(
        self->shortcut_bus, nullptr, "top.remya.bar.Shortcuts", "ToggleSidebar",
        "/top/remya/bar", nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
        +[](GDBusConnection*, const gchar*, const gchar*, const gchar*, const gchar*,
            GVariant* parameters, gpointer data) {
          const gchar* signature;
          if (!g_variant_is_of_type(parameters, G_VARIANT_TYPE("(s)"))) return;
          g_variant_get(parameters, "(&s)", &signature);
          if (g_strcmp0(signature, g_getenv("HYPRLAND_INSTANCE_SIGNATURE")) != 0) return;
          auto* self = MY_APPLICATION(data);
          GHashTableIter iterator;
          gpointer value;
          g_hash_table_iter_init(&iterator, self->bar_windows);
          bool closed = false;
          while (g_hash_table_iter_next(&iterator, nullptr, &value)) {
            closed |= close_bar_sidebar(FL_VIEW(gtk_bin_get_child(GTK_BIN(value))));
          }
          if (closed) return;
          g_hash_table_iter_init(&iterator, self->bar_windows);
          while (g_hash_table_iter_next(&iterator, nullptr, &value)) {
            auto* view = gtk_bin_get_child(GTK_BIN(value));
            auto* channel = FL_METHOD_CHANNEL(g_object_get_data(G_OBJECT(view), "window-channel"));
            fl_method_channel_invoke_method(channel, "toggleSidebar", nullptr, nullptr, nullptr, nullptr);
          }
        }, self, nullptr);
  }
  g_signal_connect_object(display, "monitor-added", G_CALLBACK(monitor_added),
                          application, G_CONNECT_DEFAULT);
  g_signal_connect_object(display, "monitor-removed",
                          G_CALLBACK(monitor_removed), application,
                          G_CONNECT_DEFAULT);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  if (self->shortcut_bus != nullptr) {
    g_dbus_connection_signal_unsubscribe(self->shortcut_bus, self->shortcut_subscription);
    g_clear_object(&self->shortcut_bus);
  }
  g_hash_table_foreach(
      self->bar_windows,
      [](gpointer key, gpointer value, gpointer data) {
        gtk_widget_destroy(GTK_WIDGET(value));
      },
      nullptr);
  g_hash_table_remove_all(self->bar_windows);
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_pointer(&self->bar_windows, g_hash_table_unref);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->bar_windows = g_hash_table_new_full(g_direct_hash, g_direct_equal,
                                            g_object_unref, g_object_unref);
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
