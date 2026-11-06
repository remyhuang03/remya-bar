#include "bar_popup.h"
#include <gtk-layer-shell.h>

#include <cstdint>

#include "flutter/generated_plugin_registrant.h"

namespace {

struct BarPopup {
  FlView* owner;
  GtkWidget* window = nullptr;
  FlView* view = nullptr;
  FlMethodChannel* channel = nullptr;
  FlValue* content = nullptr;
  FlMethodChannel* owner_channel = nullptr;
  guint hide_timer = 0;
  bool ready = false;
  bool visible = false;

  void cancel_hide() {
    if (hide_timer != 0) g_source_remove(hide_timer);
    hide_timer = 0;
  }

  void hide() {
    cancel_hide();
    visible = false;
    if (window != nullptr) gtk_widget_hide(window);
  }

  ~BarPopup() {
    cancel_hide();
    if (window != nullptr) {
      gtk_widget_destroy(window);
      g_object_unref(window);
    }
    g_clear_object(&channel);
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
  } else if (g_strcmp0(kind_of(state->content), "media") == 0 &&
             (g_strcmp0(method, "enter") == 0 || g_strcmp0(method, "leave") == 0)) {
    if (g_strcmp0(method, "enter") == 0) state->cancel_hide();
    else schedule_hide(state);
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else if (g_strcmp0(method, "action") == 0 && state->visible &&
             g_strcmp0(kind_of(state->content), "media") == 0) {
    FlValue* args = fl_method_call_get_args(call);
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

void create_popup(BarPopup* state) {
  state->window = gtk_window_new(GTK_WINDOW_POPUP);
  g_object_ref_sink(state->window);
  auto* window = GTK_WINDOW(state->window);
  gtk_window_set_transient_for(window,
      GTK_WINDOW(gtk_widget_get_toplevel(GTK_WIDGET(state->owner))));
  gtk_window_set_destroy_with_parent(window, TRUE);
  gtk_window_set_decorated(window, FALSE);
  gtk_window_set_accept_focus(window, FALSE);
  gtk_window_set_focus_on_map(window, FALSE);
  gtk_window_set_type_hint(window, GDK_WINDOW_TYPE_HINT_TOOLTIP);
  gtk_widget_set_app_paintable(state->window, TRUE);
  GdkVisual* visual = gdk_screen_get_rgba_visual(gtk_window_get_screen(window));
  if (visual != nullptr) gtk_widget_set_visual(state->window, visual);

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

void owner_method(FlMethodChannel* channel, FlMethodCall* call, gpointer data) {
  auto* state = static_cast<BarPopup*>(data);
  const char* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  const char* kind = kind_of(args);
  const bool matches = kind[0] == '\0' || g_strcmp0(kind, kind_of(state->content)) == 0;
  if (g_strcmp0(method, "hide") == 0 || g_strcmp0(method, "enter") == 0 ||
      g_strcmp0(method, "leave") == 0 || g_strcmp0(method, "update") == 0) {
    if (matches) {
      if (g_strcmp0(method, "hide") == 0) state->hide();
      else if (g_strcmp0(method, "enter") == 0) state->cancel_hide();
      else if (g_strcmp0(method, "leave") == 0) schedule_hide(state);
      else if (state->visible) {
        g_clear_pointer(&state->content, fl_value_unref);
        state->content = fl_value_ref(args);
        send_content(state);
      }
    }
    fl_method_call_respond_success(call, nullptr, nullptr);
    return;
  }
  if (g_strcmp0(method, "show") != 0) {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  FlValue* anchor = fl_value_get_type(args) == FL_VALUE_TYPE_MAP
                        ? fl_value_lookup_string(args, "anchor") : nullptr;
  FlValue* size = fl_value_get_type(args) == FL_VALUE_TYPE_MAP
                        ? fl_value_lookup_string(args, "size") : nullptr;
  int width, height;
  GdkRectangle rect;
  if (anchor == nullptr || size == nullptr ||
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
  if (state->window == nullptr) create_popup(state);
  g_clear_pointer(&state->content, fl_value_unref);
  state->content = fl_value_ref(args);
  state->cancel_hide();
  state->visible = true;
  auto* owner = GTK_WINDOW(gtk_widget_get_toplevel(GTK_WIDGET(state->owner)));
  if (auto* monitor = gtk_layer_get_monitor(owner); monitor != nullptr) {
    GdkRectangle bounds;
    gdk_monitor_get_geometry(monitor, &bounds);
    width = MIN(width, MAX(1, bounds.width - 16));
    height = MIN(height, MAX(1, bounds.height - 56));
  }
  gtk_widget_set_size_request(GTK_WIDGET(state->view), width, height);
  gtk_window_resize(GTK_WINDOW(state->window), width, height);
  gtk_widget_realize(state->window);
  GdkRectangle allocation = {0, 0, width, height};
  gtk_widget_size_allocate(state->window, &allocation);
  GdkWindow* popup = gtk_widget_get_window(state->window);
  gdk_window_move_to_rect(popup, &rect, GDK_GRAVITY_SOUTH, GDK_GRAVITY_NORTH,
      static_cast<GdkAnchorHints>(GDK_ANCHOR_SLIDE_X | GDK_ANCHOR_FLIP_Y | GDK_ANCHOR_SLIDE_Y), 0, 6);
  gtk_widget_show_all(state->window);
  send_content(state);
  fl_method_call_respond_success(call, nullptr, nullptr);
}

}  // namespace

void register_bar_popup(FlView* owner) {
  auto* state = new BarPopup{owner};
  g_object_set_data_full(G_OBJECT(owner), "remya-popup", state,
                         [](gpointer data) { delete static_cast<BarPopup*>(data); });
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(owner)),
      "top.remya.bar/popup", FL_METHOD_CODEC(codec));
  state->owner_channel = FL_METHOD_CHANNEL(g_object_ref(channel));
  fl_method_channel_set_method_call_handler(channel, owner_method, state, nullptr);
}
