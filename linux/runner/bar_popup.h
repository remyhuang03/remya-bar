#ifndef REMYA_BAR_POPUP_H_
#define REMYA_BAR_POPUP_H_

#include <flutter_linux/flutter_linux.h>

class BarViews;

void register_bar_popup(FlView* owner, BarViews* views);
void unregister_bar_popup(FlView* owner);
void hide_bar_popup(FlView* owner);
void bar_popup_monitor_removed(GdkMonitor* monitor);

#endif
