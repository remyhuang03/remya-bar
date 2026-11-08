#include "virtual_keyboard.h"

#include <gdk/gdkwayland.h>
#include <glib/gstdio.h>
#include <linux/input-event-codes.h>
#include <sys/mman.h>
#include <unistd.h>
#include <xkbcommon/xkbcommon.h>
#include <xkbcommon/xkbcommon-keysyms.h>

#include <array>
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <memory>

#include "virtual-keyboard-client.h"

namespace {

const char* string_field(FlValue* map, const char* name) {
  auto* value = fl_value_lookup_string(map, name);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_STRING
      ? fl_value_get_string(value) : nullptr;
}

xkb_mod_mask_t mask(xkb_keymap* map, const char* name) {
  const auto index = xkb_keymap_mod_get_index(map, name);
  return index < 32 ? 1u << index : 0;
}

bool install_keymap(zwp_virtual_keyboard_v1* keyboard, xkb_keymap* map) {
  std::unique_ptr<char, decltype(&free)> text(
      xkb_keymap_get_as_string(map, XKB_KEYMAP_FORMAT_TEXT_V1), free);
  if (!text) return false;
  const size_t size = strlen(text.get()) + 1;
  const int fd = memfd_create("remya-keymap", MFD_CLOEXEC);
  if (fd < 0) return false;
  const bool sized = ftruncate(fd, size) == 0;
  void* data = sized ? mmap(nullptr, size, PROT_WRITE, MAP_SHARED, fd, 0) : MAP_FAILED;
  if (data != MAP_FAILED) {
    memcpy(data, text.get(), size);
    munmap(data, size);
    zwp_virtual_keyboard_v1_keymap(keyboard, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, fd, size);
  }
  close(fd);
  return data != MAP_FAILED;
}

const char* key_label(xkb_state* state, int key, char (&label)[16]) {
  const auto symbol = xkb_state_key_get_one_sym(state, key + 8);
  if (xkb_keysym_to_utf8(symbol, label, sizeof(label)) > 0 &&
      static_cast<unsigned char>(label[0]) >= 32 && label[0] != 127) {
    return label;
  }
  switch (symbol) {
    case XKB_KEY_dead_acute: return "´";
    case XKB_KEY_dead_grave: return "`";
    case XKB_KEY_dead_circumflex: return "^";
    case XKB_KEY_dead_tilde: return "~";
    case XKB_KEY_dead_diaeresis: return "¨";
    case XKB_KEY_dead_cedilla: return "¸";
    default: return "";
  }
}

}  // namespace

VirtualKeyboard::VirtualKeyboard(GdkDisplay* gdk_display) {
  if (!GDK_IS_WAYLAND_DISPLAY(gdk_display)) return;
  auto* seat = gdk_display_get_default_seat(gdk_display);
  if (seat == nullptr) return;
  auto* wl_seat = gdk_wayland_seat_get_wl_seat(seat);
  if (wl_seat == nullptr) return;
  display_ = gdk_wayland_display_get_wl_display(gdk_display);
  auto* queue = wl_display_create_queue(display_);
  if (queue == nullptr) return;
  auto* registry = wl_display_get_registry(display_);
  wl_proxy_set_queue(reinterpret_cast<wl_proxy*>(registry), queue);
  zwp_virtual_keyboard_manager_v1* manager = nullptr;
  static const wl_registry_listener listener = {
      [](void* data, wl_registry* registry, uint32_t name, const char* interface, uint32_t) {
        if (strcmp(interface, zwp_virtual_keyboard_manager_v1_interface.name) != 0) return;
        auto** manager = static_cast<zwp_virtual_keyboard_manager_v1**>(data);
        *manager = static_cast<zwp_virtual_keyboard_manager_v1*>(
            wl_registry_bind(registry, name, &zwp_virtual_keyboard_manager_v1_interface, 1));
      },
      [](void*, wl_registry*, uint32_t) {},
  };
  wl_registry_add_listener(registry, &listener, &manager);
  wl_display_roundtrip_queue(display_, queue);
  if (manager != nullptr) {
    keyboard_ = zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(
        manager, wl_seat);
    wl_proxy_set_queue(reinterpret_cast<wl_proxy*>(keyboard_), nullptr);
    zwp_virtual_keyboard_manager_v1_destroy(manager);
  }
  wl_registry_destroy(registry);
  wl_event_queue_destroy(queue);
}

VirtualKeyboard::~VirtualKeyboard() {
  if (keymap_ != nullptr) xkb_keymap_unref(keymap_);
  if (keyboard_ != nullptr) {
    zwp_virtual_keyboard_v1_destroy(keyboard_);
    wl_display_flush(display_);
  }
}

FlValue* VirtualKeyboard::configure(FlValue* device) {
  if (!available() || device == nullptr || fl_value_get_type(device) != FL_VALUE_TYPE_MAP) {
    return nullptr;
  }
  const xkb_rule_names names = {
      string_field(device, "rules"), string_field(device, "model"),
      string_field(device, "layout"), string_field(device, "variant"),
      string_field(device, "options"),
  };
  std::unique_ptr<xkb_context, decltype(&xkb_context_unref)> context(
      xkb_context_new(XKB_CONTEXT_NO_FLAGS), xkb_context_unref);
  if (!context) return nullptr;
  const char* path = string_field(device, "file");
  std::unique_ptr<FILE, decltype(&fclose)> file(
      path != nullptr && g_path_is_absolute(path) ? g_fopen(path, "r") : nullptr, fclose);
  std::unique_ptr<xkb_keymap, decltype(&xkb_keymap_unref)> map(
      path == nullptr
          ? xkb_keymap_new_from_names(context.get(), &names, XKB_KEYMAP_COMPILE_NO_FLAGS)
          : file ? xkb_keymap_new_from_file(context.get(), file.get(),
                       XKB_KEYMAP_FORMAT_TEXT_V1, XKB_KEYMAP_COMPILE_NO_FLAGS) : nullptr,
      xkb_keymap_unref);
  if (!map) return nullptr;
  auto* group = fl_value_lookup_string(device, "group");
  const auto index = group != nullptr && fl_value_get_type(group) == FL_VALUE_TYPE_INT
      ? fl_value_get_int(group) : 0;
  if (index < 0 || index >= xkb_keymap_num_layouts(map.get())) return nullptr;
  std::unique_ptr<xkb_state, decltype(&xkb_state_unref)> state(
      xkb_state_new(map.get()), xkb_state_unref);
  if (!state || !install_keymap(keyboard_, map.get())) return nullptr;
  if (keymap_ != nullptr) xkb_keymap_unref(keymap_);
  keymap_ = map.release();
  group_ = index;
  xkb_state_update_key(state.get(), KEY_RIGHTALT + 8, XKB_KEY_DOWN);
  right_alt_ = xkb_state_serialize_mods(state.get(), XKB_STATE_MODS_DEPRESSED);
  wl_display_flush(display_);

  auto* result = fl_value_new_map();
  auto* layouts = fl_value_new_list();
  for (unsigned i = 0; i < xkb_keymap_num_layouts(keymap_); ++i) {
    fl_value_append_take(layouts, fl_value_new_string(xkb_keymap_layout_get_name(keymap_, i)));
  }
  fl_value_set_string_take(result, "layouts", layouts);
  auto* layers = fl_value_new_list();
  for (int layer = 0; layer < 4; ++layer) {
    const auto shift = layer & 1 ? mask(keymap_, XKB_MOD_NAME_SHIFT) : 0;
    const auto caps = layer & 2 ? mask(keymap_, XKB_MOD_NAME_CAPS) : 0;
    xkb_state_update_mask(state.get(), shift, 0, caps, 0, 0, group_);
    auto* keys = fl_value_new_list();
    for (int key = 0; key <= KEY_COMPOSE; ++key) {
      char label[16];
      fl_value_append_take(keys, fl_value_new_string(key_label(state.get(), key, label)));
    }
    fl_value_append_take(layers, keys);
  }
  fl_value_set_string_take(result, "labels", layers);
  return result;
}

bool VirtualKeyboard::press(int code, int modifiers, bool caps, bool num) {
  if (keymap_ == nullptr || code < 1 || code > KEY_COMPOSE || modifiers < 0 || modifiers > 31) {
    return false;
  }
  const std::array<const char*, 4> names = {
      XKB_MOD_NAME_SHIFT, XKB_MOD_NAME_CTRL, XKB_MOD_NAME_ALT, XKB_MOD_NAME_LOGO,
  };
  xkb_mod_mask_t depressed = modifiers & 16 ? right_alt_ : 0;
  for (size_t i = 0; i < names.size(); ++i) {
    if (modifiers & (1 << i)) depressed |= mask(keymap_, names[i]);
  }
  const xkb_mod_mask_t locked = (caps ? mask(keymap_, XKB_MOD_NAME_CAPS) : 0) |
      (num ? mask(keymap_, XKB_MOD_NAME_NUM) : 0);
  const uint32_t time = g_get_monotonic_time() / 1000;
  zwp_virtual_keyboard_v1_modifiers(keyboard_, depressed, 0, locked, group_);
  zwp_virtual_keyboard_v1_key(keyboard_, time, code, WL_KEYBOARD_KEY_STATE_PRESSED);
  zwp_virtual_keyboard_v1_key(keyboard_, time, code, WL_KEYBOARD_KEY_STATE_RELEASED);
  zwp_virtual_keyboard_v1_modifiers(keyboard_, 0, 0, locked, group_);
  return wl_display_flush(display_) >= 0 || errno == EAGAIN;
}
