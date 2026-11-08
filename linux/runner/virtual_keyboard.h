#ifndef REMYA_VIRTUAL_KEYBOARD_H_
#define REMYA_VIRTUAL_KEYBOARD_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

struct wl_display;
struct zwp_virtual_keyboard_v1;
struct xkb_keymap;

class VirtualKeyboard {
 public:
  explicit VirtualKeyboard(GdkDisplay* display);
  ~VirtualKeyboard();
  bool available() const { return keyboard_ != nullptr; }
  FlValue* configure(FlValue* device);
  bool press(int code, int modifiers, bool caps, bool num);

 private:
  wl_display* display_ = nullptr;
  zwp_virtual_keyboard_v1* keyboard_ = nullptr;
  xkb_keymap* keymap_ = nullptr;
  unsigned group_ = 0;
  unsigned right_alt_ = 0;
};

#endif
