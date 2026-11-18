#ifndef REMYA_BAR_VIEWS_H_
#define REMYA_BAR_VIEWS_H_

#include <flutter_linux/flutter_linux.h>
#include <unordered_map>

class BarViews {
 public:
  explicit BarViews(FlView* implicit);
  ~BarViews();
  void add(FlView* view, const char* role);
  void remove(FlView* view);
  FlValue* snapshot() const;

 private:
  void changed();
  void trace(const char* event, int64_t id, const char* role) const;

  FlBinaryMessenger* messenger_;
  FlMethodChannel* channel_;
  std::unordered_map<int64_t, const char*> roles_;
  int64_t revision_ = 0;
  bool listening_ = false;
  bool benchmark_;
};

gchar* bar_channel_name(FlView* view, const char* endpoint);

#endif
