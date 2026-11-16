#include "bar_popup_state.h"

#include <cerrno>

namespace bar_popup_internal {

namespace {

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

}  // namespace

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

void place_keyboard(BarPopup* state, const GdkRectangle& monitor, bool resize) {
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

}  // namespace bar_popup_internal
