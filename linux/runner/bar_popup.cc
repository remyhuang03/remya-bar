#include "bar_popup.h"

#include <gtk-layer-shell.h>
#include <cerrno>
#include <cstdint>
#include <cstring>
#include <memory>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "virtual_keyboard.h"

namespace {

constexpr int kSidebarRightMargin = 6;
constexpr int kKeyboardShadow = 20;

const char* kind_of(FlValue* content);
bool is_card(const char* kind);
struct BarPopup;
BarPopup* open_keyboard = nullptr;
void send_content(BarPopup* state);
void report_keyboard_visibility(FlView* owner);
bool int_at(FlValue* list, size_t index, int64_t minimum, int64_t maximum, int* output);

struct BarPopup {
  FlView* owner;
  GtkWidget* window = nullptr;
  FlView* view = nullptr;
  FlMethodChannel* channel = nullptr;
  FlMethodChannel* owner_channel = nullptr;
  FlValue* content = nullptr;
  BarPopup* sidebar_popup = nullptr;
  BarPopup* tray_popup = nullptr;
  BarPopup* tooltip_popup = nullptr;
  BarPopup* tray_overflow = nullptr;
  BarPopup* toast_popup = nullptr;
  BarPopup* keyboard_popup = nullptr;
  std::unique_ptr<VirtualKeyboard> keyboard = nullptr;
  bool is_keyboard = false;
  bool docked = false;
  int keyboard_requested_width = 1;
  int keyboard_requested_height = 1;
  int keyboard_height = 1;
  int keyboard_left = 0;
  int keyboard_bottom = 24;
  int drag_left = 0;
  int drag_bottom = 0;
  guint hide_timer = 0;
  bool ready = false;
  bool visible = false;
  bool sidebar = false;
  bool tray = false;
  bool tooltip = false;
  bool toast = false;
  std::vector<GtkWidget*> dismiss_windows;
  bool dismissing = false;
  bool owner_hovered = false;
  bool popup_hovered = false;
  guint dismiss_timer = 0;
  int pill_left = 0;
  int pill_width = 1;
  int width = 1;
  int monitor_width = 1;
  int vertical_insets = 56;

  void clear_dismiss_windows() {
    for (auto* window : dismiss_windows) gtk_widget_destroy(window);
    dismiss_windows.clear();
  }

  void cancel_hide() {
    if (hide_timer != 0) g_source_remove(hide_timer);
    hide_timer = 0;
  }
  void cancel_dismiss() {
    if (dismiss_timer != 0) g_source_remove(dismiss_timer);
    dismiss_timer = 0;
    dismissing = false;
  }
  void enter() {
    cancel_hide();
    if (!dismissing) return;
    cancel_dismiss();
    fl_value_set_string_take(content, "opening", fl_value_new_bool(false));
    send_content(this);
  }
  void card_state(bool open) {
    g_autoptr(FlValue) args = fl_value_new_map();
    fl_value_set_string_take(args, "action", fl_value_new_string("card.state"));
    fl_value_set_string_take(args, "kind", fl_value_new_string(kind_of(content)));
    fl_value_set_string_take(args, "open", fl_value_new_bool(open));
    fl_method_channel_invoke_method(owner_channel, "action", args, nullptr, nullptr, nullptr);
  }
  void hide() {
    cancel_hide();
    cancel_dismiss();
    owner_hovered = popup_hovered = false;
    if (visible && is_card(kind_of(content))) card_state(false);
    if (visible && tray && g_strcmp0(kind_of(content), "tray-menu") == 0) {
      g_autoptr(FlValue) args = fl_value_new_map();
      fl_value_set_string_take(args, "action", fl_value_new_string("tray.closed"));
      FlValue* details = content != nullptr ? fl_value_lookup_string(content, "data") : nullptr;
      if (details != nullptr) {
        FlValue* token = fl_value_lookup_string(details, "token");
        if (token != nullptr) fl_value_set_string(args, "token", token);
      }
      fl_method_channel_invoke_method(owner_channel, "action", args, nullptr, nullptr, nullptr);
    }
    if (visible && sidebar) {
      g_autoptr(FlValue) args = fl_value_new_map();
      fl_value_set_string_take(args, "action", fl_value_new_string("sidebar.closed"));
      fl_method_channel_invoke_method(owner_channel, "action", args, nullptr, nullptr, nullptr);
    }
    visible = false;
    if (open_keyboard == this) {
      open_keyboard = nullptr;
      report_keyboard_visibility(owner);
      if (ready) fl_method_channel_invoke_method(channel, "keyboard.hidden", nullptr,
                                                 nullptr, nullptr, nullptr);
    }
    keyboard.reset();
    clear_dismiss_windows();
    if (window != nullptr) gtk_widget_hide(window);
  }
  void destroy_window() {
    cancel_hide();
    cancel_dismiss();
    clear_dismiss_windows();
    g_clear_object(&channel);
    if (window != nullptr) {
      gtk_widget_destroy(window);
      g_object_unref(window);
    }
    window = nullptr;
    view = nullptr;
    ready = false;
  }
  ~BarPopup() {
    if (open_keyboard == this) open_keyboard = nullptr;
    delete sidebar_popup;
    delete tray_popup;
    delete tooltip_popup;
    delete tray_overflow;
    delete toast_popup;
    delete keyboard_popup;
    destroy_window();
    g_clear_object(&owner_channel);
    g_clear_pointer(&content, fl_value_unref);
  }
};

void report_keyboard_visibility(FlView* owner) {
  auto* parent = GTK_WINDOW(gtk_widget_get_toplevel(GTK_WIDGET(owner)));
  auto* app = gtk_window_get_application(parent);
  if (app == nullptr) return;
  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "action", fl_value_new_string("keyboard.visibility"));
  fl_value_set_string_take(args, "open", fl_value_new_bool(open_keyboard != nullptr));
  for (auto* node = gtk_application_get_windows(app); node != nullptr; node = node->next) {
    auto* view = gtk_bin_get_child(GTK_BIN(node->data));
    if (view == nullptr) continue;
    auto* root = static_cast<BarPopup*>(g_object_get_data(G_OBJECT(view), "remya-popup"));
    if (root != nullptr)
      fl_method_channel_invoke_method(root->owner_channel, "action", args, nullptr, nullptr, nullptr);
  }
}

gchar* keyboard_state_path() {
  const char* base = g_getenv("XDG_STATE_HOME");
  if (base != nullptr && g_path_is_absolute(base))
    return g_build_filename(base, "remya", "bar", "keyboard.ini", nullptr);
  return g_build_filename(g_get_home_dir(), ".local", "state", "remya", "bar",
                          "keyboard.ini", nullptr);
}

GdkRectangle monitor_geometry(GdkMonitor* monitor) {
  GdkRectangle geometry = {};
  if (monitor != nullptr) gdk_monitor_get_geometry(monitor, &geometry);
  return geometry;
}

void size_keyboard(BarPopup* state, const GdkRectangle& monitor) {
  const int width = state->keyboard_requested_width;
  const int height = state->keyboard_requested_height;
  state->width = MAX(1, MIN(width, MIN(monitor.width - 16,
      MAX(1, monitor.height - 56) * width / height)));
  state->keyboard_height = MAX(1, height * state->width / width);
}

void place_keyboard(BarPopup* state, const GdkRectangle& monitor, bool resize = false) {
  const int center = (monitor.width - state->width) / 2;
  state->keyboard_left = CLAMP(state->keyboard_left, -center,
                               monitor.width - state->width - center);
  state->keyboard_bottom = CLAMP(state->keyboard_bottom, 0,
                                 MAX(0, monitor.height - state->keyboard_height));
  auto* window = GTK_WINDOW(state->window);
  gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_LEFT,
                       state->docked ? 0 : center + state->keyboard_left - kKeyboardShadow);
  gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_BOTTOM,
                       state->docked ? 0 : state->keyboard_bottom - kKeyboardShadow);
  if (!resize) return;
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_LEFT, !state->docked);
  gtk_layer_set_exclusive_zone(window, state->docked ? state->keyboard_height : -1);
  const int width = state->width + 2 * kKeyboardShadow;
  const int height = state->keyboard_height + (state->docked ? 1 : 2) * kKeyboardShadow;
  gtk_widget_set_size_request(GTK_WIDGET(state->view), width, height);
  gtk_window_resize(window, width, height);
  const cairo_rectangle_int_t panel = {
      kKeyboardShadow, kKeyboardShadow, state->width, state->keyboard_height};
  auto* input = cairo_region_create_rectangle(&panel);
  gtk_widget_input_shape_combine_region(state->window, input);
  cairo_region_destroy(input);
}

bool keyboard_drag(BarPopup* state, FlValue* value, bool drop) {
  constexpr int limit = 1 << 24;
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_LIST) return false;
  const size_t length = fl_value_get_length(value);
  int dx, dy;
  if ((length != 2 && !(drop && length == 4)) ||
      !int_at(value, 0, -limit, limit, &dx) || !int_at(value, 1, -limit, limit, &dy)) {
    return false;
  }
  auto* window = GTK_WINDOW(state->window);
  auto* monitor = gtk_layer_get_monitor(window);
  const auto geometry = monitor_geometry(monitor);
  const int left = state->drag_left + dx;
  const int bottom = state->drag_bottom - dy;
  if (drop) {
    const int center = geometry.x + geometry.width / 2 + left;
    const int top = geometry.y + geometry.height - state->keyboard_height - bottom;
    int x = center;
    int y = top + 11;
    if (length == 4 &&
        (!int_at(value, 2, -limit, limit, &x) || !int_at(value, 3, -limit, limit, &y))) {
      return false;
    }
    auto* target = gdk_display_get_monitor_at_point(gtk_widget_get_display(state->window), x, y);
    const auto bounds = monitor_geometry(target);
    if (target != monitor && x >= bounds.x && x < bounds.x + bounds.width &&
        y >= bounds.y && y < bounds.y + bounds.height) {
      // Remapping a layer surface ends its pointer grab, so switch outputs on drop.
      gtk_layer_set_monitor(window, target);
      size_keyboard(state, bounds);
      state->keyboard_left = center - bounds.x - bounds.width / 2;
      state->keyboard_bottom = bounds.y + bounds.height - state->keyboard_height - top;
      place_keyboard(state, bounds, true);
      return true;
    }
  }
  state->keyboard_left = left;
  state->keyboard_bottom = bottom;
  place_keyboard(state, geometry);
  return true;
}

void save_keyboard_position(BarPopup* state) {
  g_autofree gchar* path = keyboard_state_path();
  g_autofree gchar* directory = g_path_get_dirname(path);
  g_autofree gchar* contents = g_strdup_printf("[floating]\nleft=%d\nbottom=%d\n",
                                               state->keyboard_left, state->keyboard_bottom);
  g_autoptr(GError) error = nullptr;
  if (g_mkdir_with_parents(directory, 0700) != 0 ||
      !g_file_set_contents_full(path, contents, -1, G_FILE_SET_CONTENTS_CONSISTENT, 0600, &error)) {
    g_warning("Could not save virtual keyboard position: %s",
              error != nullptr ? error->message : g_strerror(errno));
  }
}

const char* kind_of(FlValue* content) {
  if (content == nullptr || fl_value_get_type(content) != FL_VALUE_TYPE_MAP) return "";
  FlValue* kind = fl_value_lookup_string(content, "kind");
  return kind != nullptr && fl_value_get_type(kind) == FL_VALUE_TYPE_STRING
      ? fl_value_get_string(kind) : "";
}

bool is_card(const char* kind) {
  return g_strcmp0(kind, "media") == 0 || g_strcmp0(kind, "battery") == 0 ||
      g_strcmp0(kind, "datetime") == 0 || g_strcmp0(kind, "resources") == 0 ||
      g_strcmp0(kind, "notifications") == 0;
}

FlValue* copy_map(FlValue* source) {
  auto* copy = fl_value_new_map();
  if (source != nullptr && fl_value_get_type(source) == FL_VALUE_TYPE_MAP) {
    for (size_t i = 0; i < fl_value_get_length(source); ++i)
      fl_value_set(copy, fl_value_get_map_key(source, i), fl_value_get_map_value(source, i));
  }
  return copy;
}

void replace_content(BarPopup* state, FlValue* args, bool opening) {
  g_autoptr(FlValue) content = copy_map(args);
  fl_value_set_string_take(content, "opening", fl_value_new_bool(opening));
  if (state->sidebar) {
    g_autoptr(FlValue) details = copy_map(fl_value_lookup_string(content, "data"));
    fl_value_set_string_take(details, "keyboardOpen", fl_value_new_bool(open_keyboard != nullptr));
    fl_value_set_string(content, "data", details);
  }
  if (is_card(kind_of(content))) {
    FlValue* anchor = fl_value_lookup_string(content, "anchor");
    int x, width;
    if (anchor != nullptr && fl_value_get_type(anchor) == FL_VALUE_TYPE_LIST &&
        fl_value_get_length(anchor) == 4 &&
        int_at(anchor, 0, 0, G_MAXINT / 2, &x) &&
        int_at(anchor, 2, 1, G_MAXINT / 2, &width)) {
      const int left = CLAMP(x + (width - state->width) / 2,
          0, MAX(0, state->monitor_width - state->width));
      state->pill_left = x - left;
      state->pill_width = width;
      if (state->window != nullptr)
        gtk_layer_set_margin(GTK_WINDOW(state->window), GTK_LAYER_SHELL_EDGE_LEFT, left);
    }
    g_autoptr(FlValue) details = copy_map(fl_value_lookup_string(content, "data"));
    g_autoptr(FlValue) pill = fl_value_new_list();
    fl_value_append_take(pill, fl_value_new_int(state->pill_left));
    fl_value_append_take(pill, fl_value_new_int(state->pill_width));
    fl_value_set_string(details, "pill", pill);
    fl_value_set_string(content, "data", details);
  }
  g_clear_pointer(&state->content, fl_value_unref);
  state->content = fl_value_ref(content);
}

void send_content(BarPopup* state) {
  if (state->ready && state->visible && state->content != nullptr) {
    fl_method_channel_invoke_method(state->channel, "content", state->content,
                                    nullptr, nullptr, nullptr);
  }
}

void schedule_hide(BarPopup* state) {
  // Notification popups close only when their notifications do.
  if (state->sidebar || state->tray || state->toast || state->is_keyboard ||
      state->dismissing) return;
  state->cancel_hide();
  state->hide_timer = g_timeout_add(180, [](gpointer data) -> gboolean {
    auto* state = static_cast<BarPopup*>(data);
    state->hide_timer = 0;
    if (!state->visible) return G_SOURCE_REMOVE;
    if (!is_card(kind_of(state->content))) {
      state->hide();
      return G_SOURCE_REMOVE;
    }
    state->dismissing = true;
    fl_method_channel_invoke_method(state->channel, "dismiss", nullptr, nullptr, nullptr, nullptr);
    state->dismiss_timer = g_timeout_add(400, [](gpointer data) -> gboolean {
      auto* state = static_cast<BarPopup*>(data);
      state->dismiss_timer = 0;
      state->hide();
      return G_SOURCE_REMOVE;
    }, state);
    return G_SOURCE_REMOVE;
  }, state);
}

bool keyboard_action(BarPopup* state, FlMethodCall* call, FlValue* args, const char* action) {
  if (!state->is_keyboard || !state->visible || !state->keyboard) return false;
  auto* value = fl_value_lookup_string(args, "value");
  if (g_strcmp0(action, "keyboard.configure") == 0) {
    g_autoptr(FlValue) layout = state->keyboard->configure(value);
    if (layout != nullptr) fl_method_call_respond_success(call, layout, nullptr);
    else fl_method_call_respond_error(call, "keymap", "Could not load the keyboard layout", nullptr, nullptr);
    return true;
  }
  if (g_strcmp0(action, "keyboard.press") == 0) {
    int code, modifiers, locks;
    if (value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_LIST &&
        fl_value_get_length(value) == 3 && int_at(value, 0, 1, 127, &code) &&
        int_at(value, 1, 0, 31, &modifiers) && int_at(value, 2, 0, 3, &locks) &&
        state->keyboard->press(code, modifiers, locks & 1, locks & 2)) {
      fl_method_call_respond_success(call, nullptr, nullptr);
    } else {
      fl_method_call_respond_error(call, "key", "Could not send the key", nullptr, nullptr);
    }
    return true;
  }
  if (g_strcmp0(action, "keyboard.dock") == 0 && value != nullptr &&
      fl_value_get_type(value) == FL_VALUE_TYPE_BOOL) {
    state->docked = fl_value_get_bool(value);
    place_keyboard(state, monitor_geometry(gtk_layer_get_monitor(GTK_WINDOW(state->window))), true);
  } else if (!state->docked && g_strcmp0(action, "keyboard.drag-start") == 0) {
    state->drag_left = state->keyboard_left;
    state->drag_bottom = state->keyboard_bottom;
  } else if (!state->docked && (g_strcmp0(action, "keyboard.drag") == 0 ||
                               g_strcmp0(action, "keyboard.drag-end") == 0)) {
    const bool drop = g_strcmp0(action, "keyboard.drag-end") == 0;
    const bool canceled = drop && (value == nullptr || fl_value_get_type(value) == FL_VALUE_TYPE_NULL);
    if (!canceled && !keyboard_drag(state, value, drop)) {
      fl_method_call_respond_error(call, "invalid-position", "Invalid keyboard position", nullptr, nullptr);
      return true;
    }
    if (drop) save_keyboard_position(state);
  } else if (!state->docked && g_strcmp0(action, "keyboard.reset-position") == 0) {
    state->keyboard_left = 0;
    state->keyboard_bottom = 24;
    place_keyboard(state, monitor_geometry(gtk_layer_get_monitor(GTK_WINDOW(state->window))));
    save_keyboard_position(state);
  } else {
    return false;
  }
  fl_method_call_respond_success(call, nullptr, nullptr);
  return true;
}

void popup_method(FlMethodChannel* channel, FlMethodCall* call, gpointer data) {
  auto* state = static_cast<BarPopup*>(data);
  const char* method = fl_method_call_get_name(call);
  if (g_strcmp0(method, "ready") == 0) {
    state->ready = true;
    fl_method_call_respond_success(call, nullptr, nullptr);
    send_content(state);
  } else if (g_strcmp0(method, "resize") == 0) {
    FlValue* args = fl_method_call_get_args(call);
    FlValue* value = args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
        ? fl_value_lookup_string(args, "height") : nullptr;
    if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_INT ||
        fl_value_get_int(value) < 1 || fl_value_get_int(value) > G_MAXINT / 2) {
      fl_method_call_respond_error(call, "invalid-arguments", "Invalid content height", nullptr, nullptr);
      return;
    }
    if (state->visible) {
      auto* owner = GTK_WINDOW(gtk_widget_get_toplevel(GTK_WIDGET(state->owner)));
      GdkRectangle monitor;
      gdk_monitor_get_geometry(gtk_layer_get_monitor(owner), &monitor);
      const int height = MIN(fl_value_get_int(value), MAX(1, monitor.height - state->vertical_insets));
      gtk_widget_set_size_request(GTK_WIDGET(state->view), state->width, height);
      gtk_window_resize(GTK_WINDOW(state->window), state->width, height);

    }
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else if (g_strcmp0(method, "enter") == 0 || g_strcmp0(method, "leave") == 0) {
    // Bar and popup engines report pointer moves in any order; hide only
    // once the pointer has left both.
    state->popup_hovered = g_strcmp0(method, "enter") == 0;
    if (state->popup_hovered || state->owner_hovered) state->enter();
    else schedule_hide(state);
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else if (g_strcmp0(method, "hidden") == 0) {
    if (state->dismissing) state->hide();
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else if (g_strcmp0(method, "action") == 0) {
    FlValue* args = fl_method_call_get_args(call);
    FlValue* action = fl_value_get_type(args) == FL_VALUE_TYPE_MAP
        ? fl_value_lookup_string(args, "action") : nullptr;
    if (action == nullptr || fl_value_get_type(action) != FL_VALUE_TYPE_STRING) {
      fl_method_call_respond_error(call, "invalid-arguments", "Expected popup action", nullptr, nullptr);
      return;
    }
    if (g_strcmp0(fl_value_get_string(action), "close") == 0) {
      state->hide();
      fl_method_call_respond_success(call, nullptr, nullptr);
      return;
    }
    if (keyboard_action(state, call, args, fl_value_get_string(action))) return;
    if (state->is_keyboard && !state->visible) {
      fl_method_call_respond_error(call, "keyboard-hidden", "Keyboard is hidden", nullptr, nullptr);
      return;
    }
    if (g_strcmp0(fl_value_get_string(action), "quit") == 0) {
      fl_method_call_respond_success(call, nullptr, nullptr);
      auto* owner = GTK_WINDOW(gtk_widget_get_toplevel(GTK_WIDGET(state->owner)));
      g_application_quit(G_APPLICATION(gtk_window_get_application(owner)));
      return;
    }
    fl_method_channel_invoke_method(state->owner_channel, "action", args, nullptr,
        [](GObject* channel, GAsyncResult* result, gpointer data) {
          g_autoptr(FlMethodCall) call = FL_METHOD_CALL(data);
          g_autoptr(GError) error = nullptr;
          g_autoptr(FlMethodResponse) response = fl_method_channel_invoke_method_finish(
              FL_METHOD_CHANNEL(channel), result, &error);
          if (response != nullptr) fl_method_call_respond(call, response, nullptr);
          else fl_method_call_respond_error(call, "action-failed", error->message, nullptr, nullptr);
        }, g_object_ref(call));
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
  }
}

void create_popup(BarPopup* state, bool sidebar, bool tray, bool tooltip, bool toast,
                  bool keyboard = false) {
  const bool card = !sidebar && !tray && !tooltip && !toast && !keyboard;
  const bool interactive = !tooltip && !toast && !keyboard;
  state->sidebar = sidebar;
  state->tray = tray;
  state->tooltip = tooltip;
  state->toast = toast;
  state->is_keyboard = keyboard;
  state->window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  g_object_ref_sink(state->window);
  auto* window = GTK_WINDOW(state->window);
  auto* owner = GTK_WINDOW(gtk_widget_get_toplevel(GTK_WIDGET(state->owner)));
  gtk_window_set_transient_for(window, owner);
  gtk_window_set_destroy_with_parent(window, TRUE);
  gtk_window_set_decorated(window, FALSE);
  gtk_window_set_accept_focus(window, interactive);
  gtk_window_set_focus_on_map(window, FALSE);
  gtk_layer_init_for_window(window);
  gtk_layer_set_namespace(window, sidebar ? "top.remya.bar/sidebar"
      : keyboard ? "top.remya.bar/keyboard"
      : toast ? "top.remya.bar/notifications"
      : tray ? "top.remya.bar/tray-menu"
      : card ? "top.remya.bar/card" : "top.remya.bar/tooltip");
  gtk_layer_set_monitor(window, gtk_layer_get_monitor(owner));
  gtk_layer_set_layer(window, GTK_LAYER_SHELL_LAYER_OVERLAY);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_TOP, !keyboard);
  gtk_layer_set_exclusive_zone(window, 0);
  if (keyboard) {
    gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_BOTTOM, TRUE);
    gtk_layer_set_keyboard_mode(window, GTK_LAYER_SHELL_KEYBOARD_MODE_NONE);
  } else if (toast) {
    gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_LEFT, TRUE);
    gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_LEFT, 8);
    gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_TOP, 8);
    gtk_layer_set_keyboard_mode(window, GTK_LAYER_SHELL_KEYBOARD_MODE_NONE);
  } else if (sidebar) {
    gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_RIGHT, TRUE);
    gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_RIGHT, kSidebarRightMargin);
    gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_TOP, 8);
    gtk_layer_set_keyboard_mode(window, GTK_LAYER_SHELL_KEYBOARD_MODE_ON_DEMAND);
  } else {
    gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_LEFT, TRUE);
    gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_TOP, card ? 0 : 2);
    gtk_layer_set_keyboard_mode(window, tray ? GTK_LAYER_SHELL_KEYBOARD_MODE_EXCLUSIVE
        : card ? GTK_LAYER_SHELL_KEYBOARD_MODE_ON_DEMAND
                    : GTK_LAYER_SHELL_KEYBOARD_MODE_NONE);
  }

  if (card) {
    g_signal_connect(window, "key-press-event",
        G_CALLBACK(+[](GtkWidget*, GdkEventKey* event, gpointer data) -> gboolean {
          if (event->keyval != GDK_KEY_Escape) return FALSE;
          static_cast<BarPopup*>(data)->hide();
          return TRUE;
        }), state);
  }
  gtk_widget_set_app_paintable(state->window, TRUE);
  GdkVisual* visual = gdk_screen_get_rgba_visual(gtk_window_get_screen(window));
  if (visual != nullptr) gtk_widget_set_visual(GTK_WIDGET(window), visual);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  gchar popup_argument[] = "--remya-popup";
  gchar* arguments[] = {popup_argument, nullptr};
  fl_dart_project_set_dart_entrypoint_arguments(project, arguments);
  state->view = fl_view_new(project);
  const GdkRGBA transparent = {0, 0, 0, 0};
  fl_view_set_background_color(state->view, &transparent);
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(state->view));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  state->channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(state->view)),
      "top.remya.bar/popup", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(state->channel, popup_method, state, nullptr);
  fl_register_plugins(FL_PLUGIN_REGISTRY(state->view));
}

bool int_at(FlValue* list, size_t index, int64_t minimum, int64_t maximum, int* output) {
  FlValue* value = fl_value_get_list_value(list, index);
  if (fl_value_get_type(value) != FL_VALUE_TYPE_INT) return false;
  int64_t number = fl_value_get_int(value);
  if (number < minimum || number > maximum) return false;
  *output = static_cast<int>(number);
  return true;
}

void watch_outside(BarPopup* state) {
  if (!state->dismiss_windows.empty()) return;
  auto* display = gtk_widget_get_display(GTK_WIDGET(state->owner));
  for (int i = 0; i < gdk_display_get_n_monitors(display); ++i) {
    auto* dismiss = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_layer_init_for_window(GTK_WINDOW(dismiss));
    gtk_layer_set_namespace(GTK_WINDOW(dismiss), "top.remya.bar/dismiss");
    gtk_layer_set_monitor(GTK_WINDOW(dismiss), gdk_display_get_monitor(display, i));
    gtk_layer_set_layer(GTK_WINDOW(dismiss), GTK_LAYER_SHELL_LAYER_TOP);
    for (auto edge : {GTK_LAYER_SHELL_EDGE_TOP, GTK_LAYER_SHELL_EDGE_BOTTOM,
                      GTK_LAYER_SHELL_EDGE_LEFT, GTK_LAYER_SHELL_EDGE_RIGHT})
      gtk_layer_set_anchor(GTK_WINDOW(dismiss), edge, TRUE);
    gtk_layer_set_margin(GTK_WINDOW(dismiss), GTK_LAYER_SHELL_EDGE_TOP, 0);
    gtk_layer_set_exclusive_zone(GTK_WINDOW(dismiss), 0);
    gtk_layer_set_keyboard_mode(GTK_WINDOW(dismiss), GTK_LAYER_SHELL_KEYBOARD_MODE_NONE);
    gtk_window_set_accept_focus(GTK_WINDOW(dismiss), FALSE);
    gtk_widget_set_app_paintable(dismiss, TRUE);
    auto* visual = gdk_screen_get_rgba_visual(gtk_window_get_screen(GTK_WINDOW(dismiss)));
    if (visual != nullptr) gtk_widget_set_visual(dismiss, visual);
    g_signal_connect(dismiss, "draw", G_CALLBACK(+[](GtkWidget*, cairo_t* cr, gpointer) -> gboolean {
      cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
      cairo_set_source_rgba(cr, 0, 0, 0, 0);
      cairo_paint(cr);
      return TRUE;
    }), nullptr);
    gtk_widget_add_events(dismiss, GDK_BUTTON_PRESS_MASK);
    g_signal_connect(dismiss, "button-press-event", G_CALLBACK(+[](GtkWidget*, GdkEventButton*, gpointer data) -> gboolean {
      auto* state = static_cast<BarPopup*>(data);
      if (!state->sidebar) {
        g_autoptr(FlValue) args = fl_value_new_map();
        fl_value_set_string_take(args, "action", fl_value_new_string("tray.outside"));
        fl_method_channel_invoke_method(state->owner_channel, "action", args, nullptr, nullptr, nullptr);
      }
      state->hide();
      return TRUE;
    }), state);
    state->dismiss_windows.push_back(dismiss);
    gtk_widget_show(dismiss);
  }
}

BarPopup* child_popup(BarPopup* root, BarPopup*& child) {
  if (child == nullptr) {
    child = new BarPopup{root->owner};
    child->owner_channel = FL_METHOD_CHANNEL(g_object_ref(root->owner_channel));
  }
  return child;
}

void owner_method(FlMethodChannel* channel, FlMethodCall* call, gpointer data) {
  auto* state = static_cast<BarPopup*>(data);
  const char* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  const char* kind = kind_of(args);
  auto* root = state;
  const bool show = g_strcmp0(method, "show") == 0;
  const bool sidebar = g_strcmp0(kind, "sidebar") == 0;
  const bool overview = g_strcmp0(kind, "workspace-overview") == 0;
  const bool tray = overview || g_strcmp0(kind, "tray-menu") == 0;
  const bool card = is_card(kind);
  const bool tooltip = g_strcmp0(kind, "tooltip") == 0;
  const bool toast = g_strcmp0(kind, "notification-toasts") == 0;
  const bool keyboard = g_strcmp0(kind, "keyboard") == 0;
  if (g_strcmp0(method, "keyboardVisible") == 0) {
    g_autoptr(FlValue) visible = fl_value_new_bool(open_keyboard != nullptr);
    fl_method_call_respond_success(call, visible, nullptr);
    return;
  }
  if (keyboard && g_strcmp0(method, "hide") == 0) {
    if (open_keyboard != nullptr) open_keyboard->hide();
    fl_method_call_respond_success(call, nullptr, nullptr);
    return;
  }
  if (g_strcmp0(method, "watchTrayOutside") == 0) {
    auto* overflow = child_popup(root, root->tray_overflow);
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_BOOL &&
        fl_value_get_bool(args) &&
        gtk_widget_get_visible(gtk_widget_get_toplevel(GTK_WIDGET(root->owner)))) {
      watch_outside(overflow);
    } else {
      overflow->hide();
    }
    fl_method_call_respond_success(call, nullptr, nullptr);
    return;
  }
  if (sidebar || tray || tooltip || toast || keyboard) {
    auto*& child = sidebar ? root->sidebar_popup : tray ? root->tray_popup
        : toast ? root->toast_popup : keyboard ? root->keyboard_popup : root->tooltip_popup;
    if (child == nullptr && !show) {
      fl_method_call_respond_success(call, nullptr, nullptr);
      return;
    }
    state = child_popup(root, child);
  }
  if (show && !sidebar && !toast && !keyboard && root->sidebar_popup != nullptr && root->sidebar_popup->visible) {
    if (tray) {
      fl_method_call_respond_error(call, "popup-busy", "Sidebar is open", nullptr, nullptr);
    } else {
      fl_method_call_respond_success(call, nullptr, nullptr);
    }
    return;
  }
  if (show && !sidebar && !tray && !toast && !keyboard &&
      (root->tray_popup != nullptr && root->tray_popup->visible)) {
    fl_method_call_respond_success(call, nullptr, nullptr);
    return;
  }
  if (g_strcmp0(method, "hide") == 0 || g_strcmp0(method, "leave") == 0 ||
      g_strcmp0(method, "enter") == 0) {
    if (g_strcmp0(method, "hide") == 0 && kind[0] == '\0') {
      if (root->sidebar_popup != nullptr) root->sidebar_popup->hide();
      if (root->tray_popup != nullptr) root->tray_popup->hide();
      if (root->tooltip_popup != nullptr) root->tooltip_popup->hide();
      if (root->tray_overflow != nullptr) root->tray_overflow->hide();
    }
    if (kind[0] == '\0' || g_strcmp0(kind, kind_of(state->content)) == 0) {
      if (g_strcmp0(method, "hide") == 0) state->hide();
      else {
        state->owner_hovered = g_strcmp0(method, "enter") == 0;
        if (state->owner_hovered || state->popup_hovered) state->enter();
        else schedule_hide(state);
      }
    }
    fl_method_call_respond_success(call, nullptr, nullptr);
    return;
  }
  if (g_strcmp0(method, "update") == 0) {
    if (state->visible && g_strcmp0(kind, kind_of(state->content)) == 0) {
      if (keyboard) {
        fl_value_set_string(args, "data", fl_value_lookup_string(state->content, "data"));
      }
      replace_content(state, args, keyboard && !state->ready);
      if (!state->dismissing) send_content(state);
    }
    fl_method_call_respond_success(call, nullptr, nullptr);
    return;
  }
  if (g_strcmp0(method, "show") != 0) {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  if (!toast && !gtk_widget_get_visible(gtk_widget_get_toplevel(GTK_WIDGET(state->owner)))) {
    if (tray || sidebar || keyboard) fl_method_call_respond_error(call, "popup-hidden", "Bar is hidden", nullptr, nullptr);
    else fl_method_call_respond_success(call, nullptr, nullptr);
    return;
  }
  FlValue* anchor = fl_value_get_type(args) == FL_VALUE_TYPE_MAP
                        ? fl_value_lookup_string(args, "anchor") : nullptr;
  FlValue* size = fl_value_get_type(args) == FL_VALUE_TYPE_MAP
                        ? fl_value_lookup_string(args, "size") : nullptr;
  int width, height;
  GdkRectangle rect;
  if (anchor == nullptr || size == nullptr || kind[0] == '\0' ||
      fl_value_get_type(anchor) != FL_VALUE_TYPE_LIST || fl_value_get_length(anchor) != 4 ||
      fl_value_get_type(size) != FL_VALUE_TYPE_LIST || fl_value_get_length(size) != 2 ||
      !int_at(anchor, 0, 0, G_MAXINT / 2, &rect.x) ||
      !int_at(anchor, 1, 0, G_MAXINT / 2, &rect.y) ||
      !int_at(anchor, 2, 1, G_MAXINT / 2, &rect.width) ||
      !int_at(anchor, 3, 1, G_MAXINT / 2, &rect.height) ||
      !int_at(size, 0, 1, 2048, &width) || !int_at(size, 1, 1, 2048, &height)) {
    fl_method_call_respond_error(call, "invalid-arguments", "Invalid popup bounds", nullptr, nullptr);
    return;
  }
  if (keyboard) {
    auto input = std::make_unique<VirtualKeyboard>(gtk_widget_get_display(GTK_WIDGET(state->owner)));
    if (!input->available()) {
      fl_method_call_respond_error(call, "keyboard-unavailable",
                                  "Wayland virtual keyboard is unavailable", nullptr, nullptr);
      return;
    }
    auto* details = fl_value_lookup_string(args, "data");
    auto* device = details != nullptr && fl_value_get_type(details) == FL_VALUE_TYPE_MAP
        ? fl_value_lookup_string(details, "device") : nullptr;
    g_autoptr(FlValue) layout = input->configure(device);
    if (layout == nullptr) {
      fl_method_call_respond_error(call, "keymap", "Could not load the keyboard layout", nullptr, nullptr);
      return;
    }
    fl_value_set_string(details, "layout", layout);
    if (open_keyboard != nullptr) open_keyboard->hide();
    if (root->sidebar_popup != nullptr) root->sidebar_popup->hide();
    if (state->window == nullptr) create_popup(state, false, false, false, false, true);
    state->keyboard = std::move(input);
    auto* owner = GTK_WINDOW(gtk_widget_get_toplevel(GTK_WIDGET(root->owner)));
    auto* monitor = gtk_layer_get_monitor(owner);
    gtk_layer_set_monitor(GTK_WINDOW(state->window), monitor);
    const auto geometry = monitor_geometry(monitor);
    state->keyboard_requested_width = width;
    state->keyboard_requested_height = height;
    size_keyboard(state, geometry);
    state->docked = false;
    g_autoptr(GKeyFile) position = g_key_file_new();
    g_autofree gchar* path = keyboard_state_path();
    state->keyboard_left = 0;
    state->keyboard_bottom = 24;
    if (g_key_file_load_from_file(position, path, G_KEY_FILE_NONE, nullptr)) {
      g_autoptr(GError) error = nullptr;
      const int left = g_key_file_get_integer(position, "floating", "left", &error);
      if (!error) {
        const int bottom = g_key_file_get_integer(position, "floating", "bottom", &error);
        if (!error) {
          state->keyboard_left = left;
          state->keyboard_bottom = bottom;
        }
      }
    }
    place_keyboard(state, geometry, true);
    replace_content(state, args, true);
    state->visible = true;
    open_keyboard = state;
    report_keyboard_visibility(state->owner);
    gtk_widget_show_all(state->window);
    gdk_display_flush(gtk_widget_get_display(state->window));
    send_content(state);
    fl_method_call_respond_success(call, nullptr, nullptr);
    return;
  }
  if (card && state->visible && g_strcmp0(kind, kind_of(state->content)) == 0) {
    state->cancel_hide();
    state->cancel_dismiss();
    replace_content(state, args, false);
    send_content(state);
    fl_method_call_respond_success(call, nullptr, nullptr);
    return;
  }
  if (card && state->visible) state->hide();
  if (tray && state->visible && g_strcmp0(kind, kind_of(state->content)) != 0) state->hide();
  state->cancel_hide();
  if (sidebar || tray) watch_outside(state);
  if (toast) {
    // The stack is independent of hover cards, menus and the sidebar.
    if (state->window == nullptr) create_popup(state, false, false, false, true);
    auto* owner = GTK_WINDOW(gtk_widget_get_toplevel(GTK_WIDGET(state->owner)));
    GdkRectangle monitor;
    gdk_monitor_get_geometry(gtk_layer_get_monitor(owner), &monitor);
    state->width = MIN(width, MAX(1, monitor.width - 16));
    state->monitor_width = monitor.width;
    if (!state->visible) {
      height = MIN(height, MAX(1, monitor.height - state->vertical_insets));
      gtk_widget_set_size_request(GTK_WIDGET(state->view), state->width, height);
      gtk_window_resize(GTK_WINDOW(state->window), state->width, height);
    }
    replace_content(state, args, !state->visible);
    state->visible = true;
    gtk_widget_show_all(state->window);
    send_content(state);
    fl_method_call_respond_success(call, nullptr, nullptr);
    return;
  }
  if (state->window == nullptr) create_popup(state, sidebar, tray, tooltip, false);
  if (sidebar || tray || tooltip) root->hide();
  if (card && root->tray_overflow != nullptr && !root->tray_overflow->dismiss_windows.empty()) {
    g_autoptr(FlValue) args = fl_value_new_map();
    fl_value_set_string_take(args, "action", fl_value_new_string("tray.outside"));
    fl_method_channel_invoke_method(root->owner_channel, "action", args, nullptr, nullptr, nullptr);
    root->tray_overflow->hide();
  }
  if (!tooltip && root->tooltip_popup != nullptr) root->tooltip_popup->hide();
  if (sidebar) {
    if (root->tray_popup != nullptr) root->tray_popup->hide();
    if (root->tray_overflow != nullptr) root->tray_overflow->hide();
  }

  auto* owner = GTK_WINDOW(gtk_widget_get_toplevel(GTK_WIDGET(state->owner)));
  GdkRectangle monitor;
  gdk_monitor_get_geometry(gtk_layer_get_monitor(owner), &monitor);
  if (sidebar) {
    FlValue* details = fl_value_lookup_string(args, "data");
    FlValue* reserved = details != nullptr && fl_value_get_type(details) == FL_VALUE_TYPE_MAP
        ? fl_value_lookup_string(details, "reservedHeight") : nullptr;
    state->vertical_insets = reserved != nullptr && fl_value_get_type(reserved) == FL_VALUE_TYPE_INT
        ? CLAMP(fl_value_get_int(reserved), 40, monitor.height) + 16 : 56;
  }
  width = MIN(width, MAX(1, monitor.width - (sidebar ? 2 * kSidebarRightMargin : 16)));
  height = MIN(height, MAX(1, monitor.height - state->vertical_insets));
  if (tooltip) {
    const int left = CLAMP(rect.x + (rect.width - width) / 2, 0, MAX(0, monitor.width - width));
    gtk_layer_set_margin(GTK_WINDOW(state->window), GTK_LAYER_SHELL_EDGE_LEFT, left);
    gtk_layer_set_margin(GTK_WINDOW(state->window), GTK_LAYER_SHELL_EDGE_TOP,
        MAX(0, rect.y + rect.height + 6 - gtk_widget_get_allocated_height(GTK_WIDGET(state->owner))));
  }
  if (tray) {
    // The pill ends 4px above the bar's exclusive edge.
    gtk_layer_set_margin(GTK_WINDOW(state->window), GTK_LAYER_SHELL_EDGE_LEFT,
        CLAMP(rect.x + (overview ? (rect.width - width) / 2 : 0),
              0, MAX(0, monitor.width - width)));
  }
  state->width = width;
  state->monitor_width = monitor.width;
  gtk_widget_set_size_request(GTK_WIDGET(state->view), width, height);
  gtk_window_resize(GTK_WINDOW(state->window), width, height);
  replace_content(state, args, true);
  state->visible = true;
  state->owner_hovered = true;  // Shown from a hover or tap on the anchor.
  gtk_widget_show_all(state->window);
  if (card) state->card_state(true);
  if (tray) gtk_widget_grab_focus(GTK_WIDGET(state->view));
  send_content(state);
  fl_method_call_respond_success(call, nullptr, nullptr);
}

}  // namespace

void bar_popup_monitor_removed(GdkMonitor* monitor) {
  if (open_keyboard == nullptr) return;
  auto* owner = GTK_WINDOW(gtk_widget_get_toplevel(GTK_WIDGET(open_keyboard->owner)));
  if (gtk_layer_get_monitor(GTK_WINDOW(open_keyboard->window)) == monitor ||
      gtk_layer_get_monitor(owner) == monitor) {
    open_keyboard->hide();
  }
}

void register_bar_popup(FlView* owner) {
  auto* state = new BarPopup{owner};
  g_object_set_data_full(G_OBJECT(owner), "remya-popup", state,
                         [](gpointer data) { delete static_cast<BarPopup*>(data); });
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  state->owner_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(owner)),
      "top.remya.bar/popup", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(state->owner_channel, owner_method, state, nullptr);
}

bool close_bar_sidebar(FlView* owner) {
  auto* root = static_cast<BarPopup*>(g_object_get_data(G_OBJECT(owner), "remya-popup"));
  if (root == nullptr || root->sidebar_popup == nullptr || !root->sidebar_popup->visible) {
    return false;
  }
  root->sidebar_popup->hide();
  return true;
}

void hide_bar_popup(FlView* owner) {
  auto* state = static_cast<BarPopup*>(g_object_get_data(G_OBJECT(owner), "remya-popup"));
  if (state != nullptr) {
    state->hide();
    if (state->sidebar_popup != nullptr) state->sidebar_popup->hide();
    if (state->tray_popup != nullptr) state->tray_popup->hide();
    if (state->tooltip_popup != nullptr) state->tooltip_popup->hide();
    if (state->tray_overflow != nullptr && !state->tray_overflow->dismiss_windows.empty()) {
      g_autoptr(FlValue) args = fl_value_new_map();
      fl_value_set_string_take(args, "action", fl_value_new_string("tray.outside"));
      fl_method_channel_invoke_method(state->owner_channel, "action", args, nullptr, nullptr, nullptr);
      state->tray_overflow->hide();
    }
  }
}
