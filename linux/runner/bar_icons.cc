#include "bar_icons.h"

#include <gtk/gtk.h>
#include <string>

namespace {

void icon_method(FlMethodChannel*, FlMethodCall* call, gpointer) {
  if (g_strcmp0(fl_method_call_get_name(call), "lookupTray") != 0) {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  FlValue* args = fl_method_call_get_args(call);
  if (fl_value_get_type(args) != FL_VALUE_TYPE_LIST || fl_value_get_length(args) > 256) {
    fl_method_call_respond_error(call, "invalid-arguments", "Expected application identifiers", nullptr, nullptr);
    return;
  }
  g_autoptr(FlValue) result = fl_value_new_map();
  for (size_t index = 0; index < fl_value_get_length(args); ++index) {
    FlValue* item = fl_value_get_list_value(args, index);
    if (fl_value_get_type(item) != FL_VALUE_TYPE_LIST || fl_value_get_length(item) != 2) continue;
    FlValue* name_value = fl_value_get_list_value(item, 0);
    FlValue* path_value = fl_value_get_list_value(item, 1);
    if (fl_value_get_type(name_value) != FL_VALUE_TYPE_STRING ||
        fl_value_get_type(path_value) != FL_VALUE_TYPE_STRING) continue;
    const std::string name = fl_value_get_string(name_value);
    const std::string path = fl_value_get_string(path_value);
    if (name.empty() || name.size() > 4096 || path.size() > 4096 ||
        name.find_first_of("\r\n") != std::string::npos ||
        path.find_first_of("\r\n") != std::string::npos) continue;
    g_autoptr(GdkPixbuf) icon = nullptr;
    if (g_path_is_absolute(name.c_str())) {
      icon = gdk_pixbuf_new_from_file_at_scale(name.c_str(), 64, 64, TRUE, nullptr);
    } else if (name.find('/') == std::string::npos) {
      if (g_path_is_absolute(path.c_str())) {
        g_autoptr(GtkIconTheme) custom = gtk_icon_theme_new();
        gtk_icon_theme_prepend_search_path(custom, path.c_str());
        icon = gtk_icon_theme_load_icon(custom, name.c_str(), 64, GTK_ICON_LOOKUP_FORCE_SIZE, nullptr);
        // Some indicator exporters provide a flat directory.
        for (const auto* extension : {".png", ".svg", ""}) {
          if (icon != nullptr) break;
          const auto file = path + "/" + name + extension;
          if (g_file_test(file.c_str(), G_FILE_TEST_IS_REGULAR)) {
            icon = gdk_pixbuf_new_from_file_at_scale(file.c_str(), 64, 64, TRUE, nullptr);
          }
        }
      }
      if (icon == nullptr) {
        icon = gtk_icon_theme_load_icon(gtk_icon_theme_get_default(), name.c_str(),
                                      64, GTK_ICON_LOOKUP_FORCE_SIZE, nullptr);
      }
    }
    if (icon == nullptr) continue;
    g_autofree gchar* png = nullptr;
    gsize length = 0;
    if (gdk_pixbuf_save_to_buffer(icon, &png, &length, "png", nullptr, nullptr)) {
      const auto key = path + "\n" + name;
      fl_value_set_string_take(result, key.c_str(),
          fl_value_new_uint8_list(reinterpret_cast<const uint8_t*>(png), length));
    }
  }
  fl_method_call_respond_success(call, result, nullptr);
}

}  // namespace

void register_bar_icons(FlView* owner) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(owner)),
      "top.remya.bar/icons", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, icon_method, nullptr, nullptr);
}
