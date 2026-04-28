#include "include/flutter_cluster_window/flutter_cluster_window_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "flutter_cluster_window_plugin.h"

void FlutterClusterWindowPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  flutter_cluster_window::FlutterClusterWindowPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
