#ifndef FLUTTER_CLUSTER_WINDOW_PLUGIN_H_
#define FLUTTER_CLUSTER_WINDOW_PLUGIN_H_

#include <flutter/event_channel.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/encodable_value.h>

#include <memory>
#include <map>
#include <string>
#include <mutex>
#include <windows.h>

namespace flutter_cluster_window {

/// Minimal entry tracking an OS window handle and its surface identity.
/// This is the only state the native layer holds; all surfaceId mapping
/// and lifecycle logic lives in Dart.
struct WindowEntry {
    HWND hwnd;
    std::string surface_id;
    bool is_alive;
};

/// Flutter plugin that bridges Dart commands to Win32 window operations.
///
/// Registers MethodChannel and EventChannel handlers. Method names use the
/// Do* prefix to avoid collisions with Win32 macros (CreateWindow,
/// ShowWindow, MoveWindow, DestroyWindow are preprocessor macros).
class FlutterClusterWindowPlugin : public flutter::Plugin {
public:
    static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

    FlutterClusterWindowPlugin(flutter::PluginRegistrarWindows* registrar);
    virtual ~FlutterClusterWindowPlugin();

    FlutterClusterWindowPlugin(const FlutterClusterWindowPlugin&) = delete;
    FlutterClusterWindowPlugin& operator=(const FlutterClusterWindowPlugin&) = delete;

private:
    /// Routes incoming method calls to the appropriate Do* handler.
    void HandleMethodCall(
        const flutter::MethodCall<flutter::EncodableValue>& method_call,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

    // ── Stateless command executors ──────────────────────────────────────

    void DoCreateWindow(const flutter::EncodableMap& args,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
    void DoMoveWindow(const flutter::EncodableMap& args,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
    void DoShowWindow(const flutter::EncodableMap& args,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
    void DoHideWindow(const flutter::EncodableMap& args,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
    void DoFocusWindow(const flutter::EncodableMap& args,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
    void DoDestroyWindow(const flutter::EncodableMap& args,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
    void DoExecuteBatch(const flutter::EncodableMap& args,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
    void DoQueryAllPositions(
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

    /// Sends an event to the Dart EventChannel.
    void EmitEvent(const flutter::EncodableMap& event);

    /// Subclass procedure for capturing WM_MOVE, WM_SIZE, and WM_ACTIVATE.
    static LRESULT CALLBACK SubclassProc(HWND hwnd, UINT message, WPARAM wparam,
        LPARAM lparam, UINT_PTR subclass_id, DWORD_PTR ref_data);

    // ── Handle registry ─────────────────────────────────────────────────

    std::map<HWND, WindowEntry> handle_registry_;
    std::map<std::string, HWND> surface_to_hwnd_;
    std::mutex registry_mutex_;

    int sequence_counter_ = 0;

    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;
    flutter::PluginRegistrarWindows* registrar_;

    // ── Window class registration ───────────────────────────────────────

    static bool window_class_registered_;
    static const wchar_t* kWindowClassName;
    static void RegisterWindowClass();

    // ── Drag tracking ───────────────────────────────────────────────────

    bool is_dragging_ = false;
    std::string dragging_surface_id_;

    /// Locates the primary Flutter runner window (not a desktop_multi_window child).
    static HWND FindPrimaryRunnerWindow();
};

}  // namespace flutter_cluster_window

#endif  // FLUTTER_CLUSTER_WINDOW_PLUGIN_H_
