#include "bar_icons.h"

#include <gio/gdesktopappinfo.h>
#include <gtk/gtk.h>
#include <map>
#include <string>

namespace {

std::string normalized(const char* value) {
  if (value == nullptr) return {};
  g_autofree char* folded = g_utf8_casefold(value, -1);
  std::string result(folded);
  const std::string suffix = ".desktop";
  if (result.size() > suffix.size() &&
      result.compare(result.size() - suffix.size(), suffix.size(), suffix) == 0) {
    result.resize(result.size() - suffix.size());
  }
  return result;
}

std::string icon_file(GtkIconInfo* info) {
  if (info == nullptr) return {};
  const char* filename = gtk_icon_info_get_filename(info);
  std::string result = filename != nullptr ? filename : "";
  g_object_unref(info);
  return result;
}

std::string lookup_icon(const std::string& app_id) {
  const std::string wanted = normalized(app_id.c_str());
  GtkIconTheme* theme = gtk_icon_theme_get_default();
  GList* applications = g_app_info_get_all();
  std::string result;
  for (GList* entry = applications; entry != nullptr; entry = entry->next) {
    auto* app = G_APP_INFO(entry->data);
    const char* wm_class = G_IS_DESKTOP_APP_INFO(app)
        ? g_desktop_app_info_get_startup_wm_class(G_DESKTOP_APP_INFO(app)) : nullptr;
    g_autofree char* executable = g_path_get_basename(g_app_info_get_executable(app) != nullptr
        ? g_app_info_get_executable(app) : "");
    if (normalized(g_app_info_get_id(app)) != wanted &&
        normalized(wm_class) != wanted && normalized(executable) != wanted) continue;
    GIcon* icon = g_app_info_get_icon(app);
    if (icon != nullptr) result = icon_file(gtk_icon_theme_lookup_by_gicon(
        theme, icon, 32, GTK_ICON_LOOKUP_NO_SVG));
    if (!result.empty()) break;
  }
  g_list_free_full(applications, g_object_unref);
  if (!result.empty()) return result;
  for (const auto& candidate : {app_id, wanted,
       wanted.substr(wanted.find_last_of('.') == std::string::npos
           ? 0 : wanted.find_last_of('.') + 1)}) {
    result = icon_file(gtk_icon_theme_lookup_icon(theme, candidate.c_str(), 32, GTK_ICON_LOOKUP_NO_SVG));
    if (!result.empty()) return result;
  }
  return {};
}

void icon_method(FlMethodChannel*, FlMethodCall* call, gpointer) {
  const bool tray = g_strcmp0(fl_method_call_get_name(call), "lookupTray") == 0;
  if (!tray && g_strcmp0(fl_method_call_get_name(call), "lookup") != 0) {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  FlValue* args = fl_method_call_get_args(call);
  if (fl_value_get_type(args) != FL_VALUE_TYPE_LIST || fl_value_get_length(args) > 256) {
    fl_method_call_respond_error(call, "invalid-arguments", "Expected application identifiers", nullptr, nullptr);
    return;
  }
  static std::map<std::string, std::string> paths;
  g_autoptr(FlValue) result = fl_value_new_map();
  for (size_t index = 0; index < fl_value_get_length(args); ++index) {
    FlValue* item = fl_value_get_list_value(args, index);
    if (tray) {
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
      continue;
    }
    if (fl_value_get_type(item) != FL_VALUE_TYPE_STRING) continue;
    const std::string app_id = fl_value_get_string(item);
    if (app_id.empty() || app_id.size() > 256 || app_id.find_first_of("/\\\n\r") != std::string::npos) continue;
    auto path = paths.find(app_id);
    if (path == paths.end()) path = paths.emplace(app_id, lookup_icon(app_id)).first;
    if (!path->second.empty()) {
      fl_value_set_string_take(result, app_id.c_str(), fl_value_new_string(path->second.c_str()));
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
