#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk-layer-shell.h>

#include "bar_popup.h"
#include "bar_icons.h"
#include "bar_views.h"
#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr char kSettingsChannel[] = "top.remya.bar/settings";
}

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GHashTable* bar_windows;
  GtkWidget* engine_host;
  FlEngine* engine;
  BarViews* views;
  GtkWidget* settings_window;
  FlMethodChannel* settings_channel;
  gchar* settings_page;
  bool settings_ready;
  GtkNativeDialog* avatar_dialog;
  FlMethodCall* avatar_call;
  GDBusConnection* shortcut_bus;
  guint shortcut_subscription;
  guint output_restart;
  RestartBar restart_bar;
  gpointer restart_data;
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

static void set_bar_fullscreen(GtkWindow* window, bool fullscreen) {
  if (fullscreen == (g_object_get_data(G_OBJECT(window), "fullscreen") != nullptr)) return;
  g_object_set_data(G_OBJECT(window), "fullscreen", fullscreen ? GINT_TO_POINTER(1) : nullptr);
  if (fullscreen) {
    hide_bar_popup(FL_VIEW(gtk_bin_get_child(GTK_BIN(window))));
    gtk_layer_set_exclusive_zone(window, 0);
    gtk_widget_hide(GTK_WIDGET(window));
  } else {
    gtk_layer_auto_exclusive_zone_enable(window);
    gtk_widget_show(GTK_WIDGET(window));
  }
}

// Popups read the "bottom" flag to open towards the screen centre.
static void set_bar_bottom(GtkWindow* window, bool bottom) {
  if (bottom == (g_object_get_data(G_OBJECT(window), "bottom") != nullptr)) return;
  g_object_set_data(G_OBJECT(window), "bottom", bottom ? GINT_TO_POINTER(1) : nullptr);
  hide_bar_popup(FL_VIEW(gtk_bin_get_child(GTK_BIN(window))));
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_TOP, !bottom);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_BOTTOM, bottom);
}

static void schedule_output_restart(MyApplication* self);

static FlView* settings_view(MyApplication* self) {
  return self->settings_window == nullptr ? nullptr :
      FL_VIEW(gtk_bin_get_child(GTK_BIN(self->settings_window)));
}

static void finish_avatar_picker(MyApplication* self, gint response) {
  if (self->avatar_dialog == nullptr) return;
  g_autoptr(GtkNativeDialog) dialog = g_steal_pointer(&self->avatar_dialog);
  g_autoptr(FlMethodCall) call = g_steal_pointer(&self->avatar_call);
  g_autofree gchar* path = response == GTK_RESPONSE_ACCEPT
      ? gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(dialog)) : nullptr;
  g_signal_handlers_disconnect_by_data(dialog, self);
  gtk_native_dialog_destroy(dialog);
  // Dart uses UTF-8 paths; non-UTF-8 filenames cannot be passed to the editor.
  if (path != nullptr && !g_utf8_validate(path, -1, nullptr)) {
    fl_method_call_respond_error(call, "invalid-path", "Expected a UTF-8 file path", nullptr, nullptr);
  } else {
    g_autoptr(FlValue) selected = path == nullptr ? nullptr : fl_value_new_string(path);
    fl_method_call_respond_success(call, selected, nullptr);
  }
}

static void pick_avatar(MyApplication* self, FlMethodCall* call) {
  if (self->avatar_dialog != nullptr) {
    fl_method_call_respond_error(call, "dialog-open", "Avatar picker is already open", nullptr, nullptr);
    return;
  }
  auto* dialog = gtk_file_chooser_native_new("Open File", GTK_WINDOW(self->settings_window),
      GTK_FILE_CHOOSER_ACTION_OPEN, "_Open", "_Cancel");
  auto* filter = gtk_file_filter_new();
  gtk_file_filter_set_name(filter, "Images");
  const gchar* types[] = {"image/png", "image/jpeg", "image/webp"};
  for (const gchar* type : types) gtk_file_filter_add_mime_type(filter, type);
  gtk_file_chooser_add_filter(GTK_FILE_CHOOSER(dialog), filter);
  self->avatar_call = FL_METHOD_CALL(g_object_ref(call));
  self->avatar_dialog = GTK_NATIVE_DIALOG(dialog);
  gtk_native_dialog_set_modal(self->avatar_dialog, TRUE);
  g_signal_connect(self->avatar_dialog, "response", G_CALLBACK(+[](GtkNativeDialog*, gint response,
      MyApplication* self) { finish_avatar_picker(self, response); }), self);
  gtk_native_dialog_show(self->avatar_dialog);
}

static void send_settings_page(MyApplication* self) {
  auto* view = settings_view(self);
  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "viewId", fl_value_new_int(fl_view_get_id(view)));
  fl_value_set_string_take(args, "page", fl_value_new_string(self->settings_page));
  g_clear_pointer(&self->settings_page, g_free);
  fl_method_channel_invoke_method(self->settings_channel, "open", args,
                                 nullptr, nullptr, nullptr);
}

static bool valid_settings_page(const char* page) {
  return page != nullptr && (page[0] == '\0' ||
      g_regex_match_simple("^[a-z0-9]+(-[a-z0-9]+)*$", page,
                           G_REGEX_DOLLAR_ENDONLY, G_REGEX_MATCH_DEFAULT));
}

static void show_settings(MyApplication* self) {
  if (!self->settings_ready || self->settings_page == nullptr) return;
  if (self->settings_window == nullptr) {
    auto* window = gtk_application_window_new(GTK_APPLICATION(self));
    self->settings_window = window;
    gtk_window_set_title(GTK_WINDOW(window), "Remy'a Bar Settings");
    // The Flutter title bar is the only one; it moves and closes through the settings channel.
    gtk_window_set_decorated(GTK_WINDOW(window), FALSE);
    gtk_window_set_default_size(GTK_WINDOW(window), 1100, 720);
    auto* view = fl_view_new_for_engine(self->engine);
    gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
    g_signal_connect(window, "destroy", G_CALLBACK(+[](GtkWidget*, MyApplication* self) {
      auto* view = settings_view(self);
      self->views->remove(view);
      self->settings_window = nullptr;
      finish_avatar_picker(self, GTK_RESPONSE_CANCEL);
      g_autoptr(FlValue) id = fl_value_new_int(fl_view_get_id(view));
      fl_method_channel_invoke_method(self->settings_channel, "closed", id,
                                     nullptr, nullptr, nullptr);
    }), self);
    send_settings_page(self);
    self->views->add(view, "settings");
    // Keep the toplevel hidden until Flutter has rendered the themed view.
    g_signal_connect(view, "first-frame", G_CALLBACK(+[](FlView* view, gpointer) {
      gtk_window_present(GTK_WINDOW(gtk_widget_get_toplevel(GTK_WIDGET(view))));
    }), nullptr);
    gtk_widget_show(GTK_WIDGET(view));
    gtk_widget_realize(GTK_WIDGET(view));
  } else {
    send_settings_page(self);
    if (gtk_widget_get_visible(self->settings_window)) {
      gtk_window_present(GTK_WINDOW(self->settings_window));
    }
  }
}

static void open_settings(MyApplication* self, const char* page) {
  g_free(self->settings_page);
  self->settings_page = g_strdup(page);
  show_settings(self);
}

static FlMethodChannel* settings_channel(MyApplication* self, FlEngine* engine) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  auto* channel = fl_method_channel_new(fl_engine_get_binary_messenger(engine),
      kSettingsChannel, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel,
      [](FlMethodChannel*, FlMethodCall* call, gpointer data) {
        auto* self = MY_APPLICATION(data);
        const char* method = fl_method_call_get_name(call);
        if (g_strcmp0(method, "ready") == 0) {
          self->settings_ready = true;
          fl_method_call_respond_success(call, nullptr, nullptr);
          show_settings(self);
        } else if (g_strcmp0(method, "open") == 0) {
          FlValue* args = fl_method_call_get_args(call);
          const char* page = fl_value_get_type(args) == FL_VALUE_TYPE_STRING
              ? fl_value_get_string(args) : nullptr;
          if (!valid_settings_page(page)) {
            fl_method_call_respond_error(call, "invalid-page", "Invalid settings page", nullptr, nullptr);
            return;
          }
          open_settings(self, page);
          fl_method_call_respond_success(call, nullptr, nullptr);
        } else if (g_strcmp0(method, "close") == 0 || g_strcmp0(method, "startMove") == 0 ||
                   g_strcmp0(method, "pickAvatar") == 0) {
          FlView* view = settings_view(self);
          FlValue* id = fl_method_call_get_args(call);
          if (view == nullptr || fl_value_get_type(id) != FL_VALUE_TYPE_INT ||
              fl_value_get_int(id) != fl_view_get_id(view)) {
            fl_method_call_respond_error(call, "view-closed", "Settings view closed", nullptr, nullptr);
            return;
          }
          if (g_strcmp0(method, "pickAvatar") == 0) {
            pick_avatar(self, call);
            return;
          }
          if (g_strcmp0(method, "close") == 0) {
            gtk_window_close(GTK_WINDOW(self->settings_window));
          } else {
            // Called while the primary button is held; Wayland uses the press serial.
            auto* seat = gdk_display_get_default_seat(gtk_widget_get_display(self->settings_window));
            gint x, y;
            gdk_device_get_position(gdk_seat_get_pointer(seat), nullptr, &x, &y);
            gtk_window_begin_move_drag(GTK_WINDOW(self->settings_window), GDK_BUTTON_PRIMARY,
                                       x, y, gtk_get_current_event_time());
          }
          fl_method_call_respond_success(call, nullptr, nullptr);
        } else {
          fl_method_call_respond_not_implemented(call, nullptr);
        }
      }, self, nullptr);
  return channel;
}

// Debug theme resolution in bar and settings views needs the repository root.
static FlMethodChannel* paths_channel(FlEngine* engine) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  auto* channel = fl_method_channel_new(fl_engine_get_binary_messenger(engine),
      "top.remya.paths", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel,
      [](FlMethodChannel*, FlMethodCall* call, gpointer) {
        if (g_strcmp0(fl_method_call_get_name(call), "repositoryDirectory") == 0) {
          g_autoptr(FlValue) root = fl_value_new_string(REMYA_REPOSITORY_DIR);
          fl_method_call_respond_success(call, root, nullptr);
        } else {
          fl_method_call_respond_not_implemented(call, nullptr);
        }
      },
      nullptr, nullptr);
  return channel;
}

static void create_bar_window(MyApplication* self, GdkMonitor* monitor) {
  if (g_hash_table_contains(self->bar_windows, monitor)) return;

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(self)));
  g_hash_table_insert(self->bar_windows, g_object_ref(monitor),
                      g_object_ref(window));
  g_object_set_data(G_OBJECT(window), "bar-monitor", monitor);
  gtk_window_set_title(window, "Remy'a Bar");
  gtk_window_set_decorated(window, FALSE);
  gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);
  GdkVisual* visual = gdk_screen_get_rgba_visual(gtk_window_get_screen(window));
  if (visual != nullptr) gtk_widget_set_visual(GTK_WIDGET(window), visual);
  gtk_widget_set_size_request(GTK_WIDGET(window), -1, 40);

  gtk_layer_init_for_window(window);
  gtk_layer_set_namespace(window, APPLICATION_ID);
  gtk_layer_set_monitor(window, monitor);
  gtk_layer_set_layer(window, GTK_LAYER_SHELL_LAYER_TOP);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_TOP, TRUE);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_LEFT, TRUE);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_RIGHT, TRUE);
  gtk_layer_set_keyboard_mode(window, GTK_LAYER_SHELL_KEYBOARD_MODE_NONE);
  gtk_layer_auto_exclusive_zone_enable(window);

  FlView* view = fl_view_new_for_engine(self->engine);
  const GdkRGBA transparent = {0, 0, 0, 0};
  fl_view_set_background_color(view, &transparent);
  register_bar_popup(view, self->views);
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  g_autoptr(FlStandardMethodCodec) window_codec = fl_standard_method_codec_new();
  g_autofree gchar* channel_name = bar_channel_name(view, "window");
  g_autoptr(FlMethodChannel) window_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(self->engine), channel_name,
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
        } else if (g_strcmp0(method, "setFullscreen") == 0 ||
                   g_strcmp0(method, "setBottom") == 0) {
          FlValue* value = fl_method_call_get_args(call);
          if (fl_value_get_type(value) != FL_VALUE_TYPE_BOOL) {
            fl_method_call_respond_error(call, "invalid-arguments", "Expected boolean", nullptr, nullptr);
            return;
          }
          auto* view = GTK_WIDGET(g_object_get_data(G_OBJECT(channel), "owner"));
          auto* window = GTK_WINDOW(gtk_widget_get_toplevel(view));
          if (g_strcmp0(method, "setBottom") == 0) set_bar_bottom(window, fl_value_get_bool(value));
          else set_bar_fullscreen(window, fl_value_get_bool(value));
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
  g_signal_connect_object(monitor, "notify::scale-factor",
      G_CALLBACK(+[](GdkMonitor*, GParamSpec*, GtkWindow* window) {
        auto* app = gtk_window_get_application(window);
        if (app != nullptr) schedule_output_restart(MY_APPLICATION(app));
      }), window, G_CONNECT_DEFAULT);
  g_signal_connect(window, "destroy", G_CALLBACK(+[](GtkWindow* window, MyApplication* self) {
    auto* view = FL_VIEW(gtk_bin_get_child(GTK_BIN(window)));
    self->views->remove(view);
    g_autofree gchar* name = bar_channel_name(view, "window");
    fl_binary_messenger_set_message_handler_on_channel(fl_engine_get_binary_messenger(self->engine),
        name, nullptr, nullptr, nullptr);
    g_object_set_data(G_OBJECT(view), "window-channel", nullptr);
    unregister_bar_popup(view);
    auto* monitor = GDK_MONITOR(g_object_get_data(G_OBJECT(window), "bar-monitor"));
    g_signal_handlers_disconnect_by_data(monitor, window);
    g_hash_table_remove(self->bar_windows, monitor);
  }), self);
  self->views->add(view, "bar");
  gtk_widget_show_all(GTK_WIDGET(window));
}

static void schedule_output_restart(MyApplication* self) {
  g_clear_handle_id(&self->output_restart, g_source_remove);
  // Wait for Wayland's topology and scale announcements to settle first.
  self->output_restart = g_timeout_add(250, +[](gpointer data) -> gboolean {
    auto* self = MY_APPLICATION(data);
    self->output_restart = 0;
    if (gdk_display_get_n_monitors(gdk_display_get_default()) > 0) {
      self->restart_bar("Display topology or scale changed", self->restart_data);
      g_application_activate(G_APPLICATION(self));
    }
    return G_SOURCE_REMOVE;
  }, self);
}

static void monitor_added(GdkDisplay*, GdkMonitor* monitor, MyApplication* self) {
  if (self->engine != nullptr && !g_hash_table_contains(self->bar_windows, monitor)) {
    schedule_output_restart(self);
  }
}

static void monitor_removed(GdkDisplay*, GdkMonitor* monitor,
                            MyApplication* self) {
  auto* window = GTK_WIDGET(g_hash_table_lookup(self->bar_windows, monitor));
  bar_popup_monitor_removed(monitor);
  if (window != nullptr) {
    gtk_widget_destroy(window);
    schedule_output_restart(self);
  }
}

static void create_app_engine(MyApplication* self) {
  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);
  self->engine_host = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  g_object_ref_sink(self->engine_host);
  gtk_window_set_default_size(GTK_WINDOW(self->engine_host), 1, 1);
  auto* implicit = fl_view_new(project);
  gtk_container_add(GTK_CONTAINER(self->engine_host), GTK_WIDGET(implicit));
  self->engine = FL_ENGINE(g_object_ref(fl_view_get_engine(implicit)));
  self->views = new BarViews(implicit);
  self->settings_channel = settings_channel(self, self->engine);
  g_object_set_data_full(G_OBJECT(implicit), "paths-channel", paths_channel(self->engine), g_object_unref);
  register_bar_icons(implicit);
  fl_register_plugins(FL_PLUGIN_REGISTRY(implicit));

  // Realization starts Flutter without mapping the implicit host on any output.
  gtk_widget_realize(self->engine_host);
  gtk_widget_realize(GTK_WIDGET(implicit));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  if (self->engine_host == nullptr) create_app_engine(self);
  GdkDisplay* display = gdk_display_get_default();
  for (int index = 0; index < gdk_display_get_n_monitors(display); index++) {
    create_bar_window(self, gdk_display_get_monitor(display, index));
  }
}

// GApplication forwards command lines from secondary processes to this instance.
static int my_application_command_line(GApplication* application,
                                       GApplicationCommandLine* command_line) {
  auto* self = MY_APPLICATION(application);
  int argc = 0;
  g_auto(GStrv) arguments = g_application_command_line_get_arguments(command_line, &argc);
  const bool settings = argc > 1 && g_strcmp0(arguments[1], "--settings") == 0;
  const char* page = settings && argc == 3 ? arguments[2] : "";
  if (settings && (argc > 3 || !valid_settings_page(page))) {
    g_application_command_line_printerr(command_line, "Usage: remya_bar --settings [page]\n");
    return 1;
  }
  if (!gtk_layer_is_supported()) {
    g_application_command_line_printerr(command_line,
        "Remy'a Bar requires a Wayland compositor with layer-shell support.\n");
    return 1;
  }
  if (self->dart_entrypoint_arguments == nullptr) {
    self->dart_entrypoint_arguments = g_strdupv(arguments + (settings ? argc : 1));
    // Keep display event handling alive while all outputs are disconnected.
    g_application_hold(application);
  }
  g_application_activate(application);
  if (settings) open_settings(self, page);
  return 0;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
  GdkDisplay* display = gdk_display_get_default();
  MyApplication* self = MY_APPLICATION(application);
  self->shortcut_bus = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, nullptr);
  if (self->shortcut_bus != nullptr) {
    self->shortcut_subscription = g_dbus_connection_signal_subscribe(
        self->shortcut_bus, nullptr, "top.remya.bar.Shortcuts", nullptr,
        "/top/remya/bar", nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
        +[](GDBusConnection*, const gchar*, const gchar*, const gchar*,
            const gchar* signal_name, GVariant* parameters, gpointer data) {
          if (g_variant_is_of_type(parameters, G_VARIANT_TYPE("(s)"))) {
            const gchar* signature;
            g_variant_get(parameters, "(&s)", &signature);
            if (signature[0] != '\0' &&
                g_strcmp0(signature, g_getenv("HYPRLAND_INSTANCE_SIGNATURE")) != 0) {
              return;
            }
          } else if (!g_variant_is_of_type(parameters, G_VARIANT_TYPE("()"))) {
            return;
          }
          auto* self = MY_APPLICATION(data);
          GHashTableIter iterator;
          gpointer value;
          if (g_strcmp0(signal_name, "ToggleSidebar") == 0) {
            if (!g_variant_is_of_type(parameters, G_VARIANT_TYPE("(s)"))) return;
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
            return;
          }
          if (g_strcmp0(signal_name, "VolumeUp") == 0 ||
              g_strcmp0(signal_name, "VolumeDown") == 0 ||
              g_strcmp0(signal_name, "VolumeMute") == 0 ||
              g_strcmp0(signal_name, "BrightnessUp") == 0 ||
              g_strcmp0(signal_name, "BrightnessDown") == 0) {
            g_hash_table_iter_init(&iterator, self->bar_windows);
            while (g_hash_table_iter_next(&iterator, nullptr, &value)) {
              auto* view = gtk_bin_get_child(GTK_BIN(value));
              auto* channel = FL_METHOD_CHANNEL(g_object_get_data(G_OBJECT(view), "window-channel"));
              g_autoptr(FlValue) action = fl_value_new_string(signal_name);
              fl_method_channel_invoke_method(channel, "osdShortcut", action, nullptr, nullptr, nullptr);
            }
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
  g_clear_handle_id(&self->output_restart, g_source_remove);
  g_signal_handlers_disconnect_by_data(gdk_display_get_default(), self);
  if (self->shortcut_bus != nullptr) {
    g_dbus_connection_signal_unsubscribe(self->shortcut_bus, self->shortcut_subscription);
    g_clear_object(&self->shortcut_bus);
  }
  if (self->settings_window != nullptr) gtk_widget_destroy(self->settings_window);
  g_autoptr(GList) windows = g_hash_table_get_values(self->bar_windows);
  for (auto* node = windows; node != nullptr; node = node->next)
    gtk_widget_destroy(GTK_WIDGET(node->data));
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_pointer(&self->bar_windows, g_hash_table_unref);
  g_clear_pointer(&self->settings_page, g_free);
  if (self->engine_host != nullptr) {
    fl_binary_messenger_set_message_handler_on_channel(fl_engine_get_binary_messenger(self->engine),
        kSettingsChannel, nullptr, nullptr, nullptr);
    g_clear_object(&self->settings_channel);
    delete self->views;
    self->views = nullptr;
    gtk_widget_destroy(self->engine_host);
    g_clear_object(&self->engine_host);
    g_clear_object(&self->engine);
  }
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->command_line = my_application_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->bar_windows = g_hash_table_new_full(g_direct_hash, g_direct_equal,
                                            g_object_unref, g_object_unref);
}

MyApplication* my_application_new(RestartBar restart_bar, gpointer restart_data) {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  auto* self = MY_APPLICATION(g_object_new(my_application_get_type(),
                                           "application-id", APPLICATION_ID, "flags",
                                           G_APPLICATION_HANDLES_COMMAND_LINE, nullptr));
  self->restart_bar = restart_bar;
  self->restart_data = restart_data;
  return self;
}
