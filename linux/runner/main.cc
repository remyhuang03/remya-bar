#include <errno.h>
#include <glib-unix.h>
#include <unistd.h>

#include "my_application.h"

static void prepare_for_sleep(GDBusConnection*, const gchar*, const gchar*,
                              const gchar*, const gchar*, GVariant* parameters,
                              gpointer data) {
  if (!g_variant_is_of_type(parameters, G_VARIANT_TYPE("(b)"))) return;
  gboolean sleeping;
  g_variant_get(parameters, "(b)", &sleeping);
  if (sleeping) return;

  // GTK and the Flutter engines share the EGL display. Reopen it on resume.
  g_message("System resumed; restarting Bar to recreate graphics contexts");
  if (g_fdwalk_set_cloexec(3) == 0) {
    execv("/proc/self/exe", static_cast<char**>(data));
  }
  g_warning("Could not restart Bar after resume: %s", g_strerror(errno));
}

int main(int argc, char** argv) {
  g_autoptr(MyApplication) app = my_application_new();
  g_autoptr(GError) error = nullptr;
  g_autoptr(GDBusConnection) bus = g_bus_get_sync(G_BUS_TYPE_SYSTEM, nullptr, &error);
  guint subscription = 0;
  if (bus != nullptr) {
    subscription = g_dbus_connection_signal_subscribe(
        bus, "org.freedesktop.login1", "org.freedesktop.login1.Manager",
        "PrepareForSleep", "/org/freedesktop/login1", nullptr,
        G_DBUS_SIGNAL_FLAGS_NONE, prepare_for_sleep, argv, nullptr);
  } else {
    g_warning("Could not watch for system resume: %s", error->message);
  }

  const int status = g_application_run(G_APPLICATION(app), argc, argv);
  if (subscription != 0) {
    g_dbus_connection_signal_unsubscribe(bus, subscription);
  }
  return status;
}
