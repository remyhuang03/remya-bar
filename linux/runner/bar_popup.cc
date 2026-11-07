#include "bar_popup.h"

#include <gtk-layer-shell.h>
#include <cstdint>
#include <cstring>
#include <vector>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr int kSidebarRightMargin = 6;

const char* kind_of(FlValue* content);

struct BarPopup {
  FlView* owner;
  GtkWidget* window = nullptr;
  FlView* view = nullptr;
  FlMethodChannel* channel = nullptr;
  FlMethodChannel* owner_channel = nullptr;
  FlValue* content = nullptr;
  BarPopup* sidebar_popup = nullptr;
  BarPopup* resources_popup = nullptr;
  BarPopup* tray_popup = nullptr;
  BarPopup* tooltip_popup = nullptr;
  BarPopup* tray_overflow = nullptr;
  guint hide_timer = 0;
  bool ready = false;
  bool visible = false;
  bool sidebar = false;
  bool tray = false;
  bool resources = false;
  bool tooltip = false;
  std::vector<GtkWidget*> dismiss_windows;
  GdkRectangle anchor{};
  int width = 1;
  int vertical_insets = 56;

  void clear_dismiss_windows() {
    for (auto* window : dismiss_windows) gtk_widget_destroy(window);
    dismiss_windows.clear();
  }

  void cancel_hide() {
    if (hide_timer != 0) g_source_remove(hide_timer);
    hide_timer = 0;
  }
  void hide() {
    cancel_hide();
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
    clear_dismiss_windows();
    if (window != nullptr) gtk_widget_hide(window);
  }
  void destroy_window() {
    cancel_hide();
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
    delete sidebar_popup;
    delete resources_popup;
    delete tray_popup;
    delete tooltip_popup;
    delete tray_overflow;
    destroy_window();
    g_clear_object(&owner_channel);
    g_clear_pointer(&content, fl_value_unref);
  }
};

const char* kind_of(FlValue* content) {
  if (content == nullptr || fl_value_get_type(content) != FL_VALUE_TYPE_MAP) return "";
  FlValue* kind = fl_value_lookup_string(content, "kind");
  return kind != nullptr && fl_value_get_type(kind) == FL_VALUE_TYPE_STRING
      ? fl_value_get_string(kind) : "";
}

void send_content(BarPopup* state) {
  if (state->ready && state->visible && state->content != nullptr) {
    fl_method_channel_invoke_method(state->channel, "content", state->content,
                                    nullptr, nullptr, nullptr);
  }
}

void schedule_hide(BarPopup* state) {
  if (state->sidebar || state->tray) return;
  state->cancel_hide();
  state->hide_timer = g_timeout_add(180, [](gpointer data) -> gboolean {
    auto* state = static_cast<BarPopup*>(data);
    state->hide_timer = 0;
    state->hide();
    return G_SOURCE_REMOVE;
  }, state);
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
      if (!state->sidebar && !state->tray && !state->resources && !state->tooltip) {
        GdkRectangle allocation = {0, 0, state->width, height};
        gtk_widget_size_allocate(state->window, &allocation);
        gdk_window_move_to_rect(gtk_widget_get_window(state->window), &state->anchor,
            GDK_GRAVITY_SOUTH, GDK_GRAVITY_NORTH,
            static_cast<GdkAnchorHints>(GDK_ANCHOR_SLIDE_X | GDK_ANCHOR_FLIP_Y | GDK_ANCHOR_SLIDE_Y), 0, 6);
      }
    }
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else if (g_strcmp0(method, "enter") == 0 || g_strcmp0(method, "leave") == 0) {
    if (g_strcmp0(method, "enter") == 0) state->cancel_hide();
    else schedule_hide(state);
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

void create_popup(BarPopup* state, bool sidebar, bool tray, bool resources, bool tooltip) {
  const bool interactive = sidebar || tray || resources;
  const bool layer = interactive || tooltip;
  state->sidebar = sidebar;
  state->tray = tray;
  state->resources = resources;
  state->tooltip = tooltip;
  state->window = gtk_window_new(layer ? GTK_WINDOW_TOPLEVEL : GTK_WINDOW_POPUP);
  g_object_ref_sink(state->window);
  auto* window = GTK_WINDOW(state->window);
  auto* owner = GTK_WINDOW(gtk_widget_get_toplevel(GTK_WIDGET(state->owner)));
  gtk_window_set_transient_for(window, owner);
  gtk_window_set_destroy_with_parent(window, TRUE);
  gtk_window_set_decorated(window, FALSE);
  gtk_window_set_accept_focus(window, interactive);
  gtk_window_set_focus_on_map(window, FALSE);
  if (layer) {
    gtk_layer_init_for_window(window);
    gtk_layer_set_namespace(window, sidebar ? "top.remya.bar/sidebar"
        : tray ? "top.remya.bar/tray-menu"
        : resources ? "top.remya.bar/resources" : "top.remya.bar/tooltip");
    gtk_layer_set_monitor(window, gtk_layer_get_monitor(owner));
    gtk_layer_set_layer(window, GTK_LAYER_SHELL_LAYER_OVERLAY);
    gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_TOP, TRUE);
    gtk_layer_set_exclusive_zone(window, 0);
    if (sidebar) {
      gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_RIGHT, TRUE);
      gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_RIGHT, kSidebarRightMargin);
      gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_TOP, 8);
      gtk_layer_set_keyboard_mode(window, GTK_LAYER_SHELL_KEYBOARD_MODE_ON_DEMAND);
    } else {
      gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_LEFT, TRUE);
      gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_TOP, 2);
      gtk_layer_set_keyboard_mode(window, tray ? GTK_LAYER_SHELL_KEYBOARD_MODE_EXCLUSIVE
          : resources ? GTK_LAYER_SHELL_KEYBOARD_MODE_ON_DEMAND
                      : GTK_LAYER_SHELL_KEYBOARD_MODE_NONE);
    }
  } else {
    gtk_window_set_type_hint(window, GDK_WINDOW_TYPE_HINT_TOOLTIP);
  }
  if (resources) {
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
  const bool resources = g_strcmp0(kind, "resources") == 0;
  const bool tooltip = g_strcmp0(kind, "tooltip") == 0;
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
  if (sidebar || tray || resources || tooltip) {
    auto*& child = sidebar ? root->sidebar_popup : tray ? root->tray_popup
        : resources ? root->resources_popup : root->tooltip_popup;
    if (child == nullptr && !show) {
      fl_method_call_respond_success(call, nullptr, nullptr);
      return;
    }
    state = child_popup(root, child);
  }
  if (show && !sidebar && root->sidebar_popup != nullptr && root->sidebar_popup->visible) {
    if (tray) {
      fl_method_call_respond_error(call, "popup-busy", "Sidebar is open", nullptr, nullptr);
    } else {
      fl_method_call_respond_success(call, nullptr, nullptr);
    }
    return;
  }
  if (show && !sidebar && !tray &&
      ((root->tray_popup != nullptr && root->tray_popup->visible) ||
       (!resources && root->resources_popup != nullptr && root->resources_popup->visible))) {
    fl_method_call_respond_success(call, nullptr, nullptr);
    return;
  }
  if (g_strcmp0(method, "hide") == 0 || g_strcmp0(method, "leave") == 0 ||
      g_strcmp0(method, "enter") == 0) {
    if (g_strcmp0(method, "hide") == 0 && kind[0] == '\0') {
      if (root->sidebar_popup != nullptr) root->sidebar_popup->hide();
      if (root->tray_popup != nullptr) root->tray_popup->hide();
      if (root->resources_popup != nullptr) root->resources_popup->hide();
      if (root->tooltip_popup != nullptr) root->tooltip_popup->hide();
      if (root->tray_overflow != nullptr) root->tray_overflow->hide();
    }
    if (kind[0] == '\0' || g_strcmp0(kind, kind_of(state->content)) == 0) {
      if (g_strcmp0(method, "hide") == 0) state->hide();
      else if (g_strcmp0(method, "leave") == 0) schedule_hide(state);
      else state->cancel_hide();
    }
    fl_method_call_respond_success(call, nullptr, nullptr);
    return;
  }
  if (g_strcmp0(method, "update") == 0) {
    if (state->visible && g_strcmp0(kind, kind_of(state->content)) == 0) {
      g_clear_pointer(&state->content, fl_value_unref);
      state->content = fl_value_ref(args);
      send_content(state);
    }
    fl_method_call_respond_success(call, nullptr, nullptr);
    return;
  }
  if (g_strcmp0(method, "show") != 0) {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  if (!gtk_widget_get_visible(gtk_widget_get_toplevel(GTK_WIDGET(state->owner)))) {
    if (tray || sidebar) fl_method_call_respond_error(call, "popup-hidden", "Bar is hidden", nullptr, nullptr);
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
  if (resources && state->visible) {
    state->cancel_hide();
    fl_method_call_respond_success(call, nullptr, nullptr);
    return;
  }
  if (tray && state->visible && g_strcmp0(kind, kind_of(state->content)) != 0) state->hide();
  state->cancel_hide();
  if (sidebar || tray) watch_outside(state);
  if (state->window == nullptr) create_popup(state, sidebar, tray, resources, tooltip);
  if (sidebar || tray || resources || tooltip) root->hide();
  if ((sidebar || tray) && root->resources_popup != nullptr) root->resources_popup->hide();
  if (resources && root->tray_overflow != nullptr && !root->tray_overflow->dismiss_windows.empty()) {
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
  g_clear_pointer(&state->content, fl_value_unref);
  state->content = fl_value_ref(args);
  state->visible = true;
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
  if (tooltip || resources) {
    gtk_layer_set_margin(GTK_WINDOW(state->window), GTK_LAYER_SHELL_EDGE_LEFT,
        CLAMP(rect.x + (rect.width - width) / 2, 0, MAX(0, monitor.width - width)));
    gtk_layer_set_margin(GTK_WINDOW(state->window), GTK_LAYER_SHELL_EDGE_TOP,
        resources ? 2 : MAX(0, rect.y + rect.height + 6 - gtk_widget_get_allocated_height(GTK_WIDGET(state->owner))));
  }
  if (tray) {
    // The pill ends 4px above the bar's exclusive edge.
    gtk_layer_set_margin(GTK_WINDOW(state->window), GTK_LAYER_SHELL_EDGE_LEFT,
        CLAMP(rect.x + (overview ? (rect.width - width) / 2 : 0),
              0, MAX(0, monitor.width - width)));
  }
  state->width = width;
  if (!sidebar && !tray && !resources && !tooltip) {
    // Align hover cards to the 32px pill's bottom edge in the 40px bar.
    rect.y = MAX(0, gtk_widget_get_allocated_height(GTK_WIDGET(state->owner)) - 5);
    rect.height = 1;
  }
  state->anchor = rect;
  gtk_widget_set_size_request(GTK_WIDGET(state->view), width, height);
  gtk_window_resize(GTK_WINDOW(state->window), width, height);
  if (!sidebar && !tray && !resources && !tooltip) {
    gtk_widget_realize(state->window);
    GdkRectangle allocation = {0, 0, width, height};
    gtk_widget_size_allocate(state->window, &allocation);
    GdkWindow* popup = gtk_widget_get_window(state->window);
    gdk_window_move_to_rect(popup, &rect, GDK_GRAVITY_SOUTH, GDK_GRAVITY_NORTH,
        static_cast<GdkAnchorHints>(GDK_ANCHOR_SLIDE_X | GDK_ANCHOR_FLIP_Y | GDK_ANCHOR_SLIDE_Y), 0, 6);
  }
  gtk_widget_show_all(state->window);
  if (tray) gtk_widget_grab_focus(GTK_WIDGET(state->view));
  send_content(state);
  fl_method_call_respond_success(call, nullptr, nullptr);
}

}  // namespace

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
    if (state->resources_popup != nullptr) state->resources_popup->hide();
    if (state->tooltip_popup != nullptr) state->tooltip_popup->hide();
    if (state->tray_overflow != nullptr && !state->tray_overflow->dismiss_windows.empty()) {
      g_autoptr(FlValue) args = fl_value_new_map();
      fl_value_set_string_take(args, "action", fl_value_new_string("tray.outside"));
      fl_method_channel_invoke_method(state->owner_channel, "action", args, nullptr, nullptr, nullptr);
      state->tray_overflow->hide();
    }
  }
}
