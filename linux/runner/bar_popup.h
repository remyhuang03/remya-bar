#ifndef REMYA_BAR_POPUP_H_
#define REMYA_BAR_POPUP_H_

#include <flutter_linux/flutter_linux.h>

void register_bar_popup(FlView* owner);
void hide_bar_popup(FlView* owner);
bool close_bar_sidebar(FlView* owner);
void bar_popup_monitor_removed(GdkMonitor* monitor);

#endif
