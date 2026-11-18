#include "bar_views.h"

namespace {
constexpr char kChannel[] = "top.remya.bar/views";
}  // namespace

BarViews::BarViews(FlView* implicit)
    : messenger_(fl_engine_get_binary_messenger(fl_view_get_engine(implicit))),
      benchmark_(g_strcmp0(g_getenv("REMYA_BAR_BENCHMARK"), "1") == 0) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  channel_ = fl_method_channel_new(messenger_, kChannel, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel_,
      [](FlMethodChannel*, FlMethodCall* call, gpointer data) {
        if (g_strcmp0(fl_method_call_get_name(call), "list") == 0) {
          auto* self = static_cast<BarViews*>(data);
          self->listening_ = true;
          g_autoptr(FlValue) snapshot = self->snapshot();
          fl_method_call_respond_success(call, snapshot, nullptr);
        } else {
          fl_method_call_respond_not_implemented(call, nullptr);
        }
      }, this, nullptr);
  trace("engine_created", fl_view_get_id(implicit), "implicit");
}

BarViews::~BarViews() {
  fl_binary_messenger_set_message_handler_on_channel(messenger_, kChannel,
      nullptr, nullptr, nullptr);
  g_object_unref(channel_);
}

void BarViews::add(FlView* view, const char* role) {
  roles_.emplace(fl_view_get_id(view), role);
  trace("view_created", fl_view_get_id(view), role);
  if (benchmark_) {
    g_signal_connect(view, "first-frame", G_CALLBACK(+[](FlView* view, gpointer data) {
      auto* self = static_cast<BarViews*>(data);
      const auto id = fl_view_get_id(view);
      auto role = self->roles_.find(id);
      if (role != self->roles_.end()) self->trace("native_first_frame", id, role->second);
    }), this);
    g_signal_connect(view, "map", G_CALLBACK(+[](FlView* view, gpointer data) {
      auto* self = static_cast<BarViews*>(data);
      const auto id = fl_view_get_id(view);
      auto role = self->roles_.find(id);
      if (role != self->roles_.end()) self->trace("view_mapped", id, role->second);
    }), this);
  }
  changed();
}

void BarViews::remove(FlView* view) {
  const auto id = fl_view_get_id(view);
  auto entry = roles_.find(id);
  if (entry == roles_.end()) return;
  const auto* role = entry->second;
  g_signal_handlers_disconnect_by_data(view, this);
  roles_.erase(entry);
  trace("view_removed", id, role);
  changed();
}

FlValue* BarViews::snapshot() const {
  auto* views = fl_value_new_map();
  for (const auto& entry : roles_) {
    g_autofree gchar* key = g_strdup_printf("%" G_GINT64_FORMAT, entry.first);
    fl_value_set_string_take(views, key, fl_value_new_string(entry.second));
  }
  auto* snapshot = fl_value_new_map();
  fl_value_set_string_take(snapshot, "revision", fl_value_new_int(revision_));
  fl_value_set_string_take(snapshot, "views", views);
  return snapshot;
}

void BarViews::changed() {
  ++revision_;
  // The initial list already includes changes before Dart installs its handler.
  if (!listening_) return;
  g_autoptr(FlValue) current = snapshot();
  fl_method_channel_invoke_method(channel_, "changed", current, nullptr, nullptr, nullptr);
}

void BarViews::trace(const char* event, int64_t id, const char* role) const {
  if (!benchmark_) return;
  g_message("remya-bar-benchmark event=%s monotonic_us=%" G_GINT64_FORMAT
            " engine_count=1 explicit_view_count=%zu view_id=%" G_GINT64_FORMAT " role=%s",
            event, g_get_monotonic_time(), roles_.size(), id, role);
}

gchar* bar_channel_name(FlView* view, const char* endpoint) {
  return g_strdup_printf("top.remya.bar/bar/%" G_GINT64_FORMAT "/%s",
      fl_view_get_id(view), endpoint);
}
