cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES C CXX)

pkg_check_modules(VIRTUAL_KEYBOARD REQUIRED IMPORTED_TARGET wayland-client xkbcommon)
find_program(WAYLAND_SCANNER wayland-scanner REQUIRED)
set(KEYBOARD_XML "${CMAKE_CURRENT_SOURCE_DIR}/../protocols/virtual-keyboard-unstable-v1.xml")
set(KEYBOARD_HEADER "${CMAKE_CURRENT_BINARY_DIR}/virtual-keyboard-client.h")
set(KEYBOARD_CODE "${CMAKE_CURRENT_BINARY_DIR}/virtual-keyboard-protocol.c")
add_custom_command(OUTPUT "${KEYBOARD_HEADER}" "${KEYBOARD_CODE}"
  COMMAND "${WAYLAND_SCANNER}" client-header "${KEYBOARD_XML}" "${KEYBOARD_HEADER}"
  COMMAND "${WAYLAND_SCANNER}" private-code "${KEYBOARD_XML}" "${KEYBOARD_CODE}"
  DEPENDS "${KEYBOARD_XML}"
  VERBATIM
)
add_library(bar_virtual_keyboard STATIC
  virtual_keyboard.cc "${KEYBOARD_HEADER}" "${KEYBOARD_CODE}"
)
target_include_directories(bar_virtual_keyboard PRIVATE "${CMAKE_CURRENT_BINARY_DIR}")
target_link_libraries(bar_virtual_keyboard PRIVATE
  flutter PkgConfig::GTK PkgConfig::VIRTUAL_KEYBOARD
)
apply_standard_settings(bar_virtual_keyboard)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "bar_popup.cc"
  "bar_icons.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")
get_filename_component(REMYA_REPOSITORY_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
add_definitions(-DREMYA_REPOSITORY_DIR="${REMYA_REPOSITORY_DIR}")

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK_LAYER_SHELL)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GIO_UNIX)
target_link_libraries(${BINARY_NAME} PRIVATE bar_virtual_keyboard)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Build explicitly after the app bundle; the executable needs its Flutter assets.
add_executable(bar_lifecycle_test EXCLUDE_FROM_ALL
  "../../test/bar_lifecycle_test.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)
apply_standard_settings(bar_lifecycle_test)
target_include_directories(bar_lifecycle_test PRIVATE "${CMAKE_SOURCE_DIR}")
target_link_libraries(bar_lifecycle_test PRIVATE
  flutter PkgConfig::GTK PkgConfig::GTK_LAYER_SHELL PkgConfig::GIO_UNIX bar_virtual_keyboard
)
set_target_properties(bar_lifecycle_test PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bundle"
)
