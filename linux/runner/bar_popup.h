#ifndef REMYA_BAR_POPUP_H_
#define REMYA_BAR_POPUP_H_

#include <flutter_linux/flutter_linux.h>

GtkWidget* create_bar_popup_engine();
void register_bar_popup(FlView* owner, FlEngine* popup_engine);
void hide_bar_popup(FlView* owner);
bool close_bar_sidebar(FlView* owner);
void bar_popup_monitor_removed(GdkMonitor* monitor);

#endif
