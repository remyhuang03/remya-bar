#ifndef REMYA_BAR_POPUP_STATE_H_
#define REMYA_BAR_POPUP_STATE_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <gtk-layer-shell.h>
#include <cstdint>
#include <memory>
#include <vector>

#include "bar_views.h"
#include "virtual_keyboard.h"

namespace bar_popup_internal {

inline constexpr int kSidebarRightMargin = 6;
inline constexpr int kKeyboardShadow = 20;

const char* kind_of(FlValue* content);
bool is_card(const char* kind);
struct BarPopup;
extern BarPopup* open_keyboard;
void send_content(BarPopup* state);
void report_keyboard_visibility(FlView* owner);
bool int_at(FlValue* list, size_t index, int64_t minimum, int64_t maximum, int* output);
gchar* popup_channel_name(int64_t view_id);


struct BarPopup {
  FlView* owner;
  BarViews* views = nullptr;
  GtkWidget* window = nullptr;
  FlView* view = nullptr;
  int64_t view_id = -1;
  FlMethodChannel* channel = nullptr;
  FlMethodChannel* owner_channel = nullptr;
  GPtrArray* pending_actions = nullptr;
  FlValue* content = nullptr;
  BarPopup* sidebar_popup = nullptr;
  BarPopup* notifications_popup = nullptr;
  BarPopup* tray_popup = nullptr;
  BarPopup* tooltip_popup = nullptr;
  BarPopup* tray_overflow = nullptr;
  BarPopup* toast_popup = nullptr;
  BarPopup* osd_popup = nullptr;
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
  guint unmap_idle = 0;
  bool ready = false;
  bool visible = false;
  bool sidebar = false;
  bool notifications = false;
  bool tray = false;
  bool tooltip = false;
  bool toast = false;
  bool osd = false;
  bool is_panel() const { return sidebar || notifications; }
  bool retains_view() const { return is_panel() || toast; }
  // Gap from the bar edge; tooltips compute their own from the pill.
  int edge_margin() const { return osd || toast || is_panel() ? 8 : tray || tooltip ? 2 : 0; }
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
  void cancel_unmap() {
    g_clear_handle_id(&unmap_idle, g_source_remove);
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
    if (visible && notifications) {
      g_autoptr(FlValue) args = fl_value_new_map();
      fl_value_set_string_take(args, "action", fl_value_new_string("notifications.closed"));
      fl_method_channel_invoke_method(owner_channel, "action", args, nullptr, nullptr, nullptr);
    }
    visible = false;
    if (open_keyboard == this) {
      open_keyboard = nullptr;
      report_keyboard_visibility(owner);
    }
    keyboard.reset();
    if (window != nullptr && retains_view()) {
      clear_dismiss_windows();
      end_pending_actions();
      if (unmap_idle == 0 && gtk_widget_get_visible(window)) {
        // Keep the FlView alive for pending key callbacks and unmap after GTK draws.
        unmap_idle = g_idle_add_full(G_PRIORITY_HIGH_IDLE, [](gpointer data) -> gboolean {
          auto* popup = static_cast<BarPopup*>(data);
          popup->unmap_idle = 0;
          gtk_widget_hide(popup->window);
          if (popup->ready) {
            fl_method_channel_invoke_method(popup->channel, "closed", nullptr, nullptr,
                                            nullptr, nullptr);
          }
          return G_SOURCE_REMOVE;
        }, this, nullptr);
      }
    } else {
      destroy_window();
    }
    g_clear_pointer(&content, fl_value_unref);
  }
  void end_pending_actions() {
    if (pending_actions != nullptr) {
      for (guint index = 0; index < pending_actions->len; ++index) {
        auto* call = FL_METHOD_CALL(pending_actions->pdata[index]);
        fl_method_call_respond_error(call, "view-closed", "Popup closed", nullptr, nullptr);
      }
      g_ptr_array_set_size(pending_actions, 0);
      g_clear_pointer(&pending_actions, g_ptr_array_unref);
    }
  }
  void destroy_window() {
    cancel_hide();
    cancel_unmap();
    cancel_dismiss();
    clear_dismiss_windows();
    end_pending_actions();
    if (channel != nullptr) {
      g_autofree gchar* name = popup_channel_name(view_id);
      fl_binary_messenger_set_message_handler_on_channel(
          fl_engine_get_binary_messenger(fl_view_get_engine(owner)), name, nullptr, nullptr, nullptr);
      g_clear_object(&channel);
    }
    if (window != nullptr) {
      views->remove(view);
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
    delete notifications_popup;
    delete tray_popup;
    delete tooltip_popup;
    delete tray_overflow;
    delete toast_popup;
    delete osd_popup;
    delete keyboard_popup;
    destroy_window();
    g_clear_object(&owner_channel);
    g_clear_pointer(&content, fl_value_unref);
  }
};

gchar* keyboard_state_path();
GdkRectangle monitor_geometry(GdkMonitor* monitor);
void size_keyboard(BarPopup* state, const GdkRectangle& monitor);
void place_keyboard(BarPopup* state, const GdkRectangle& monitor, bool resize = false);
bool keyboard_action(BarPopup* state, FlMethodCall* call, FlValue* args, const char* action);

}  // namespace bar_popup_internal

#endif
