#include "flutter_cluster_window_plugin.h"

#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <dwmapi.h>
#pragma comment(lib, "dwmapi.lib")
#include <commctrl.h>
#pragma comment(lib, "comctl32.lib")

#include <memory>
#include <string>
#include <map>
#include <vector>
#include <mutex>

namespace flutter_cluster_window {

bool FlutterClusterWindowPlugin::window_class_registered_ = false;
const wchar_t* FlutterClusterWindowPlugin::kWindowClassName = L"FlutterClusterSurface";

// Helper: Get string from EncodableMap.
static std::string GetString(const flutter::EncodableMap& map, const std::string& key) {
    auto it = map.find(flutter::EncodableValue(key));
    if (it != map.end() && std::holds_alternative<std::string>(it->second)) {
        return std::get<std::string>(it->second);
    }
    return "";
}

// Helper: Get int from EncodableMap.
static int64_t GetInt(const flutter::EncodableMap& map, const std::string& key) {
    auto it = map.find(flutter::EncodableValue(key));
    if (it != map.end()) {
        if (std::holds_alternative<int32_t>(it->second)) return std::get<int32_t>(it->second);
        if (std::holds_alternative<int64_t>(it->second)) return std::get<int64_t>(it->second);
    }
    return 0;
}

// Helper: Get Rect from EncodableMap "frame" key.
static RECT GetFrame(const flutter::EncodableMap& map) {
    RECT r = { 0, 0, 0, 0 };
    auto it = map.find(flutter::EncodableValue("frame"));
    if (it != map.end() && std::holds_alternative<flutter::EncodableMap>(it->second)) {
        auto& frame = std::get<flutter::EncodableMap>(it->second);
        int x = static_cast<int>(GetInt(frame, "x"));
        int y = static_cast<int>(GetInt(frame, "y"));
        int w = static_cast<int>(GetInt(frame, "w"));
        int h = static_cast<int>(GetInt(frame, "h"));
        r.left = x;
        r.top = y;
        r.right = x + w;
        r.bottom = y + h;
    }
    return r;
}

// Helper: HWND from handle int.
static HWND HwndFromHandle(const flutter::EncodableMap& map) {
    return reinterpret_cast<HWND>(static_cast<intptr_t>(GetInt(map, "handle")));
}

void FlutterClusterWindowPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {

    auto plugin = std::make_unique<FlutterClusterWindowPlugin>(registrar);

    // Method channel.
    auto method_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        registrar->messenger(), "flutter_cluster_window",
        &flutter::StandardMethodCodec::GetInstance());

    method_channel->SetMethodCallHandler(
        [plugin_ptr = plugin.get()](const auto& call, auto result) {
            plugin_ptr->HandleMethodCall(call, std::move(result));
        });

    // Event channel.
    auto event_channel = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
        registrar->messenger(), "flutter_cluster_window/events",
        &flutter::StandardMethodCodec::GetInstance());

    event_channel->SetStreamHandler(
        std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
            [plugin_ptr = plugin.get()](
                const flutter::EncodableValue* arguments,
                std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
                -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
                plugin_ptr->event_sink_ = std::move(events);
                return nullptr;
            },
            [plugin_ptr = plugin.get()](const flutter::EncodableValue* arguments)
                -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
                plugin_ptr->event_sink_ = nullptr;
                return nullptr;
            }));

    registrar->AddPlugin(std::move(plugin));
}

FlutterClusterWindowPlugin::FlutterClusterWindowPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {}

FlutterClusterWindowPlugin::~FlutterClusterWindowPlugin() {
    // Clean up all tracked windows.
    std::lock_guard<std::mutex> lock(registry_mutex_);
    for (auto& [hwnd, entry] : handle_registry_) {
        if (entry.is_alive && IsWindow(hwnd)) {
            RemoveWindowSubclass(hwnd, SubclassProc, 0);
            DestroyWindow(hwnd);
        }
    }
    handle_registry_.clear();
    surface_to_hwnd_.clear();
}

void FlutterClusterWindowPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

    const auto& method = method_call.method_name();
    const auto* args = method_call.arguments();

    if (method == "initialize") {
        RegisterWindowClass();
        result->Success(flutter::EncodableValue(true));
    } else if (method == "executeCommand") {
        if (args && std::holds_alternative<flutter::EncodableMap>(*args)) {
            auto& map = std::get<flutter::EncodableMap>(*args);
            auto type = GetString(map, "type");

            if (type == "createWindow") {
                DoCreateWindow(map, std::move(result));
            } else if (type == "moveWindow") {
                DoMoveWindow(map, std::move(result));
            } else if (type == "showWindow") {
                DoShowWindow(map, std::move(result));
            } else if (type == "hideWindow") {
                DoHideWindow(map, std::move(result));
            } else if (type == "focusWindow") {
                DoFocusWindow(map, std::move(result));
            } else if (type == "destroyWindow") {
                DoDestroyWindow(map, std::move(result));
            } else {
                result->NotImplemented();
            }
        } else {
            result->Error("INVALID_ARGS", "Expected EncodableMap");
        }
    } else if (method == "executeBatch") {
        if (args && std::holds_alternative<flutter::EncodableMap>(*args)) {
            DoExecuteBatch(std::get<flutter::EncodableMap>(*args), std::move(result));
        } else {
            result->Error("INVALID_ARGS", "Expected EncodableMap");
        }
    } else if (method == "queryAllPositions") {
        DoQueryAllPositions(std::move(result));
    } else if (method == "dispose") {
        {
            std::lock_guard<std::mutex> lock(registry_mutex_);
            for (auto& [hwnd, entry] : handle_registry_) {
                if (entry.is_alive && IsWindow(hwnd)) {
                    RemoveWindowSubclass(hwnd, SubclassProc, 0);
                    DestroyWindow(hwnd);
                }
            }
            handle_registry_.clear();
            surface_to_hwnd_.clear();
        }
        result->Success();
    } else if (method == "getWindowHwnd") {
        // Return the HWND of the Flutter window this engine is attached to.
        HWND hwnd = registrar_->GetView()->GetNativeWindow();
        // Walk up to top-level window.
        HWND top = GetAncestor(hwnd, GA_ROOT);
        result->Success(flutter::EncodableValue(
            static_cast<int64_t>(reinterpret_cast<intptr_t>(top ? top : hwnd))));
    } else if (method == "getDpiScale") {
        // Return the DPI scale factor for the current window.
        HWND hwnd = registrar_->GetView()->GetNativeWindow();
        HWND top = GetAncestor(hwnd, GA_ROOT);
        HWND target = top ? top : hwnd;
        UINT dpi = 96;
        HMODULE user32 = GetModuleHandle(L"user32.dll");
        if (user32) {
            typedef UINT(WINAPI* GetDpiForWindowFunc)(HWND);
            auto fn = (GetDpiForWindowFunc)GetProcAddress(user32, "GetDpiForWindow");
            if (fn && target) dpi = fn(target);
        }
        double scale = dpi / 96.0;
        result->Success(flutter::EncodableValue(scale));
    } else if (method == "setWindowSize") {
        // Resize a window by HWND without moving it.
        if (args && std::holds_alternative<flutter::EncodableMap>(*args)) {
            auto& map = std::get<flutter::EncodableMap>(*args);
            HWND hwnd = HwndFromHandle(map);

            int w = 0, h = 0;
            auto wIt = map.find(flutter::EncodableValue("width"));
            if (wIt != map.end()) {
                if (std::holds_alternative<int32_t>(wIt->second))
                    w = std::get<int32_t>(wIt->second);
                else if (std::holds_alternative<int64_t>(wIt->second))
                    w = static_cast<int>(std::get<int64_t>(wIt->second));
            }
            auto hIt = map.find(flutter::EncodableValue("height"));
            if (hIt != map.end()) {
                if (std::holds_alternative<int32_t>(hIt->second))
                    h = std::get<int32_t>(hIt->second);
                else if (std::holds_alternative<int64_t>(hIt->second))
                    h = static_cast<int>(std::get<int64_t>(hIt->second));
            }

            if (IsWindow(hwnd) && w > 0 && h > 0) {
                SetWindowPos(hwnd, nullptr, 0, 0, w, h,
                    SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
                result->Success(flutter::EncodableValue(true));
            } else {
                result->Error("INVALID_ARGS", "Invalid handle or dimensions");
            }
        } else {
            result->Error("INVALID_ARGS", "Expected EncodableMap");
        }
    } else if (method == "setWindowPos") {
        // Direct SetWindowPos on any HWND — used by child windows to position themselves.
        if (args && std::holds_alternative<flutter::EncodableMap>(*args)) {
            auto& map = std::get<flutter::EncodableMap>(*args);
            HWND hwnd = HwndFromHandle(map);
            RECT frame = GetFrame(map);

            if (IsWindow(hwnd)) {
                SetWindowPos(hwnd, nullptr,
                    frame.left, frame.top,
                    frame.right - frame.left,
                    frame.bottom - frame.top,
                    SWP_NOZORDER | SWP_NOACTIVATE);
                result->Success(flutter::EncodableValue(true));
            } else {
                result->Error("INVALID_HANDLE", "Window handle is not valid");
            }
        } else {
            result->Error("INVALID_ARGS", "Expected EncodableMap");
        }
    } else if (method == "setFrameless") {
        // Remove title bar and borders from a window.
        if (args && std::holds_alternative<flutter::EncodableMap>(*args)) {
            auto& map = std::get<flutter::EncodableMap>(*args);
            HWND hwnd = HwndFromHandle(map);
            if (IsWindow(hwnd)) {
                LONG style = GetWindowLong(hwnd, GWL_STYLE);
                style &= ~(WS_CAPTION | WS_THICKFRAME | WS_SYSMENU |
                           WS_MINIMIZEBOX | WS_MAXIMIZEBOX);
                SetWindowLong(hwnd, GWL_STYLE, style);
                SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                    SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER);
                result->Success(flutter::EncodableValue(true));
            } else {
                result->Error("INVALID_HANDLE", "Window handle is not valid");
            }
        } else {
            result->Error("INVALID_ARGS", "Expected EncodableMap");
        }
    } else if (method == "setToolWindow") {
        // Add WS_EX_TOOLWINDOW to hide from Alt+Tab.
        if (args && std::holds_alternative<flutter::EncodableMap>(*args)) {
            auto& map = std::get<flutter::EncodableMap>(*args);
            HWND hwnd = HwndFromHandle(map);
            if (IsWindow(hwnd)) {
                LONG exStyle = GetWindowLong(hwnd, GWL_EXSTYLE);
                exStyle |= WS_EX_TOOLWINDOW;
                exStyle &= ~WS_EX_APPWINDOW;
                SetWindowLong(hwnd, GWL_EXSTYLE, exStyle);
                result->Success(flutter::EncodableValue(true));
            } else {
                result->Error("INVALID_HANDLE", "Window handle is not valid");
            }
        } else {
            result->Error("INVALID_ARGS", "Expected EncodableMap");
        }
    } else if (method == "setOwner") {
        // Set owner window (z-order grouping: child always above owner).
        if (args && std::holds_alternative<flutter::EncodableMap>(*args)) {
            auto& map = std::get<flutter::EncodableMap>(*args);
            HWND hwnd = HwndFromHandle(map);
            auto ownerIt = map.find(flutter::EncodableValue("ownerHandle"));
            HWND owner = nullptr;
            if (ownerIt != map.end()) {
                int64_t ownerVal = 0;
                if (std::holds_alternative<int32_t>(ownerIt->second))
                    ownerVal = std::get<int32_t>(ownerIt->second);
                else if (std::holds_alternative<int64_t>(ownerIt->second))
                    ownerVal = std::get<int64_t>(ownerIt->second);
                owner = reinterpret_cast<HWND>(static_cast<intptr_t>(ownerVal));
            }
            if (IsWindow(hwnd) && IsWindow(owner)) {
                SetWindowLongPtr(hwnd, GWLP_HWNDPARENT,
                    reinterpret_cast<LONG_PTR>(owner));
                result->Success(flutter::EncodableValue(true));
            } else {
                result->Error("INVALID_HANDLE", "Invalid HWND pair");
            }
        } else {
            result->Error("INVALID_ARGS", "Expected EncodableMap");
        }
    } else if (method == "installMoveHook") {
        // Subclass a window to track WM_MOVE/WM_SIZE and emit events.
        if (args && std::holds_alternative<flutter::EncodableMap>(*args)) {
            auto& map = std::get<flutter::EncodableMap>(*args);
            HWND hwnd = HwndFromHandle(map);
            if (IsWindow(hwnd)) {
                // Register in handle registry if not already.
                {
                    std::lock_guard<std::mutex> lock(registry_mutex_);
                    if (handle_registry_.find(hwnd) == handle_registry_.end()) {
                        handle_registry_[hwnd] = { hwnd, "__primary__", true };
                    }
                }
                SetWindowSubclass(hwnd, SubclassProc, 0,
                    reinterpret_cast<DWORD_PTR>(this));
                result->Success(flutter::EncodableValue(true));
            } else {
                result->Error("INVALID_HANDLE", "Window handle is not valid");
            }
        } else {
            result->Error("INVALID_ARGS", "Expected EncodableMap");
        }
    } else if (method == "findChildHwnds") {
        // Enumerate all child windows created by desktop_multi_window.
        // They use class name "FLUTTER_MULTI_WINDOW_WIN32_WINDOW".
        // Returns list of HWNDs (excluding the primary window).
        HWND primaryHwnd = nullptr;
        if (args && std::holds_alternative<flutter::EncodableMap>(*args)) {
            auto& map = std::get<flutter::EncodableMap>(*args);
            primaryHwnd = HwndFromHandle(map);
        }

        struct EnumData {
            DWORD processId;
            HWND primaryHwnd;
            std::vector<HWND> children;
        };

        EnumData data;
        data.processId = GetCurrentProcessId();
        data.primaryHwnd = primaryHwnd;

        EnumWindows([](HWND hwnd, LPARAM lParam) -> BOOL {
            auto* data = reinterpret_cast<EnumData*>(lParam);

            // Must belong to our process.
            DWORD pid = 0;
            GetWindowThreadProcessId(hwnd, &pid);
            if (pid != data->processId) return TRUE;

            // Skip the primary window.
            if (hwnd == data->primaryHwnd) return TRUE;

            // Check window class name.
            wchar_t className[256] = {};
            GetClassNameW(hwnd, className, 256);
            if (wcscmp(className, L"FLUTTER_MULTI_WINDOW_WIN32_WINDOW") == 0) {
                data->children.push_back(hwnd);
            }

            return TRUE;
        }, reinterpret_cast<LPARAM>(&data));

        // Return as list of int64.
        flutter::EncodableList list;
        for (HWND h : data.children) {
            list.push_back(flutter::EncodableValue(
                static_cast<int64_t>(reinterpret_cast<intptr_t>(h))));
        }
        result->Success(flutter::EncodableValue(list));
    } else if (method == "setDwmEffect") {
        // Apply DWM backdrop effect directly (works without flutter_acrylic).
        // effect: "acrylic", "mica", "transparent", "solid", "none"
        if (args && std::holds_alternative<flutter::EncodableMap>(*args)) {
            auto& map = std::get<flutter::EncodableMap>(*args);
            HWND hwnd = HwndFromHandle(map);
            auto effectType = GetString(map, "effect");

            if (!IsWindow(hwnd)) {
                result->Error("INVALID_HANDLE", "Invalid HWND");
                return;
            }

            // DWM_SYSTEMBACKDROP_TYPE (Win11 22H2+)
            // 0 = Auto, 1 = None, 2 = Mica, 3 = Acrylic, 4 = Tabbed
            #ifndef DWMWA_SYSTEMBACKDROP_TYPE
            #define DWMWA_SYSTEMBACKDROP_TYPE 38
            #endif

            // Enable dark mode for DWM.
            BOOL darkMode = TRUE;
            DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE,
                &darkMode, sizeof(darkMode));

            // Enable extending frame into client area (required for backdrop).
            MARGINS margins = { -1, -1, -1, -1 };
            DwmExtendFrameIntoClientArea(hwnd, &margins);

            int backdropType = 0; // Auto
            if (effectType == "mica") backdropType = 2;
            else if (effectType == "acrylic") backdropType = 3;
            else if (effectType == "tabbed") backdropType = 4;
            else if (effectType == "transparent") backdropType = 3;
            else if (effectType == "solid") backdropType = 1;
            else if (effectType == "none") backdropType = 1;

            HRESULT hr = DwmSetWindowAttribute(hwnd, DWMWA_SYSTEMBACKDROP_TYPE,
                &backdropType, sizeof(backdropType));

            if (SUCCEEDED(hr)) {
                result->Success(flutter::EncodableValue(true));
            } else {
                // Fallback for older Win11: try DWMWA_USE_IMMERSIVE_DARK_MODE only
                result->Success(flutter::EncodableValue(false));
            }
        } else {
            result->Error("INVALID_ARGS", "Expected EncodableMap");
        }
    } else if (method == "setCornerPreference") {
        // Set window corner rounding (Win11 22H2+).
        // DWMWA_WINDOW_CORNER_PREFERENCE = 33
        // DWMWCP_DEFAULT=0, DWMWCP_DONOTROUND=1, DWMWCP_ROUND=2, DWMWCP_ROUNDSMALL=3
        #ifndef DWMWA_WINDOW_CORNER_PREFERENCE
        #define DWMWA_WINDOW_CORNER_PREFERENCE 33
        #endif
        if (args && std::holds_alternative<flutter::EncodableMap>(*args)) {
            auto& map = std::get<flutter::EncodableMap>(*args);
            HWND hwnd = HwndFromHandle(map);
            auto pref = GetString(map, "preference");

            int cornerPref = 0; // Default
            if (pref == "round") cornerPref = 2;
            else if (pref == "roundSmall") cornerPref = 3;
            else if (pref == "none") cornerPref = 1;

            HRESULT hr = DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE,
                &cornerPref, sizeof(cornerPref));
            result->Success(flutter::EncodableValue(SUCCEEDED(hr)));
        } else {
            result->Error("INVALID_ARGS", "Expected EncodableMap");
        }
    } else if (method == "removeShadow") {
        // Remove drop shadow from a window.
        // Strips the CS_DROPSHADOW class style and disables DWM non-client
        // rendering so no shadow is painted around the window frame.
        if (args && std::holds_alternative<flutter::EncodableMap>(*args)) {
            auto& map = std::get<flutter::EncodableMap>(*args);
            HWND hwnd = HwndFromHandle(map);
            if (IsWindow(hwnd)) {
                // Remove CS_DROPSHADOW from the window class style.
                ULONG_PTR classStyle = GetClassLongPtr(hwnd, GCL_STYLE);
                SetClassLongPtr(hwnd, GCL_STYLE, classStyle & ~CS_DROPSHADOW);

                // Disable DWM non-client rendering (removes DWM shadow).
                #ifndef DWMWA_NCRENDERING_POLICY
                #define DWMWA_NCRENDERING_POLICY 2
                #endif
                int ncrp = 1; // DWMNCRP_DISABLED
                DwmSetWindowAttribute(hwnd, DWMWA_NCRENDERING_POLICY,
                    &ncrp, sizeof(ncrp));

                // Reset DWM extended frame margins to zero.
                // setDwmEffect sets {-1,-1,-1,-1} which creates a shadow;
                // resetting to {0,0,0,0} removes it.  The backdrop type
                // (DWMWA_SYSTEMBACKDROP_TYPE) still works independently
                // on Windows 11 22H2+.
                MARGINS margins = {0, 0, 0, 0};
                DwmExtendFrameIntoClientArea(hwnd, &margins);

                // Defence-in-depth: also set WS_EX_TOOLWINDOW which
                // prevents the OS from adding a shadow to this window.
                LONG exStyle = GetWindowLong(hwnd, GWL_EXSTYLE);
                exStyle |= WS_EX_TOOLWINDOW;
                SetWindowLong(hwnd, GWL_EXSTYLE, exStyle);

                // Force the frame to repaint without shadow.
                SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                    SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE |
                    SWP_NOZORDER | SWP_NOACTIVATE);
                result->Success(flutter::EncodableValue(true));
            } else {
                result->Error("INVALID_HANDLE", "Invalid HWND");
            }
        } else {
            result->Error("INVALID_ARGS", "Expected EncodableMap");
        }
    } else if (method == "setZOrder") {
        // Deterministic z-order control. Dart decides stacking;
        // native just executes. No conditional logic.
        // insertAfter: HWND to place this window above.
        //              0 = HWND_BOTTOM.
        if (args && std::holds_alternative<flutter::EncodableMap>(*args)) {
            auto& map = std::get<flutter::EncodableMap>(*args);
            HWND hwnd = HwndFromHandle(map);

            auto iaIt = map.find(flutter::EncodableValue("insertAfter"));
            HWND insertAfter = HWND_BOTTOM;
            if (iaIt != map.end()) {
                int64_t val = 0;
                if (std::holds_alternative<int32_t>(iaIt->second))
                    val = std::get<int32_t>(iaIt->second);
                else if (std::holds_alternative<int64_t>(iaIt->second))
                    val = std::get<int64_t>(iaIt->second);
                if (val != 0)
                    insertAfter = reinterpret_cast<HWND>(static_cast<intptr_t>(val));
            }

            if (IsWindow(hwnd)) {
                SetWindowPos(hwnd, insertAfter, 0, 0, 0, 0,
                    SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
                result->Success(flutter::EncodableValue(true));
            } else {
                result->Error("INVALID_HANDLE", "Invalid HWND");
            }
        } else {
            result->Error("INVALID_ARGS", "Expected EncodableMap");
        }
    } else if (method == "setTopMost") {
        // Explicit TOPMOST/NOTOPMOST control.
        // Dart decides when a window should be topmost.
        // topMost: true → HWND_TOPMOST, false → HWND_NOTOPMOST.
        if (args && std::holds_alternative<flutter::EncodableMap>(*args)) {
            auto& map = std::get<flutter::EncodableMap>(*args);
            HWND hwnd = HwndFromHandle(map);

            bool topMost = false;
            auto tmIt = map.find(flutter::EncodableValue("topMost"));
            if (tmIt != map.end() && std::holds_alternative<bool>(tmIt->second))
                topMost = std::get<bool>(tmIt->second);

            if (IsWindow(hwnd)) {
                SetWindowPos(hwnd,
                    topMost ? HWND_TOPMOST : HWND_NOTOPMOST,
                    0, 0, 0, 0,
                    SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
                result->Success(flutter::EncodableValue(true));
            } else {
                result->Error("INVALID_HANDLE", "Invalid HWND");
            }
        } else {
            result->Error("INVALID_ARGS", "Expected EncodableMap");
        }
    } else if (method == "getPhysicalRect") {
        // Return physical screen coordinates of a window.
        if (args && std::holds_alternative<flutter::EncodableMap>(*args)) {
            auto& map = std::get<flutter::EncodableMap>(*args);
            HWND hwnd = HwndFromHandle(map);
            if (IsWindow(hwnd)) {
                RECT r;
                GetWindowRect(hwnd, &r);
                flutter::EncodableMap rect;
                rect[flutter::EncodableValue("x")] = flutter::EncodableValue(static_cast<int64_t>(r.left));
                rect[flutter::EncodableValue("y")] = flutter::EncodableValue(static_cast<int64_t>(r.top));
                rect[flutter::EncodableValue("w")] = flutter::EncodableValue(static_cast<int64_t>(r.right - r.left));
                rect[flutter::EncodableValue("h")] = flutter::EncodableValue(static_cast<int64_t>(r.bottom - r.top));
                result->Success(flutter::EncodableValue(rect));
            } else {
                result->Error("INVALID_HANDLE", "Invalid HWND");
            }
        } else {
            result->Error("INVALID_ARGS", "Expected EncodableMap");
        }
    } else if (method == "dragPrimaryWindow") {
        // Move ALL cluster windows by dx/dy delta (physical pixels).
        if (args && std::holds_alternative<flutter::EncodableMap>(*args)) {
            auto& map = std::get<flutter::EncodableMap>(*args);

            double dx = 0, dy = 0;
            auto dxIt = map.find(flutter::EncodableValue("dx"));
            if (dxIt != map.end()) {
                if (std::holds_alternative<double>(dxIt->second))
                    dx = std::get<double>(dxIt->second);
                else if (std::holds_alternative<int32_t>(dxIt->second))
                    dx = static_cast<double>(std::get<int32_t>(dxIt->second));
                else if (std::holds_alternative<int64_t>(dxIt->second))
                    dx = static_cast<double>(std::get<int64_t>(dxIt->second));
            }
            auto dyIt = map.find(flutter::EncodableValue("dy"));
            if (dyIt != map.end()) {
                if (std::holds_alternative<double>(dyIt->second))
                    dy = std::get<double>(dyIt->second);
                else if (std::holds_alternative<int32_t>(dyIt->second))
                    dy = static_cast<double>(std::get<int32_t>(dyIt->second));
                else if (std::holds_alternative<int64_t>(dyIt->second))
                    dy = static_cast<double>(std::get<int64_t>(dyIt->second));
            }

            // Get DPI scale from primary.
            HWND primary = FindPrimaryRunnerWindow();
            UINT dpi = 96;
            HMODULE user32 = GetModuleHandle(L"user32.dll");
            if (user32) {
                typedef UINT(WINAPI* GetDpiForWindowFunc)(HWND);
                auto fn = (GetDpiForWindowFunc)GetProcAddress(user32, "GetDpiForWindow");
                if (fn && primary) dpi = fn(primary);
            }
            double scale = dpi / 96.0;
            int pdx = static_cast<int>(dx * scale);
            int pdy = static_cast<int>(dy * scale);

            // Find ALL windows in the cluster.
            struct EnumData {
                DWORD processId;
                std::vector<HWND> all;
            };
            EnumData data;
            data.processId = GetCurrentProcessId();

            EnumWindows([](HWND hwnd, LPARAM lParam) -> BOOL {
                auto* data = reinterpret_cast<EnumData*>(lParam);
                DWORD pid = 0;
                GetWindowThreadProcessId(hwnd, &pid);
                if (pid != data->processId) return TRUE;
                wchar_t className[256] = {};
                GetClassNameW(hwnd, className, 256);
                if (wcscmp(className, L"FLUTTER_RUNNER_WIN32_WINDOW") == 0 ||
                    wcscmp(className, L"FLUTTER_MULTI_WINDOW_WIN32_WINDOW") == 0) {
                    if (IsWindowVisible(hwnd)) {
                        data->all.push_back(hwnd);
                    }
                }
                return TRUE;
            }, reinterpret_cast<LPARAM>(&data));

            // Move ALL windows atomically using DeferWindowPos.
            HDWP hdwp = BeginDeferWindowPos(static_cast<int>(data.all.size()));
            if (hdwp) {
                for (HWND h : data.all) {
                    RECT r;
                    GetWindowRect(h, &r);
                    hdwp = DeferWindowPos(hdwp, h, nullptr,
                        r.left + pdx, r.top + pdy,
                        0, 0,
                        SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
                    if (!hdwp) break;
                }
                if (hdwp) EndDeferWindowPos(hdwp);
            }
            result->Success(flutter::EncodableValue(true));
        } else {
            // No args: legacy SC_MOVE approach.
            HWND primary = FindPrimaryRunnerWindow();
            if (primary && IsWindow(primary)) {
                ReleaseCapture();
                SendMessage(primary, WM_SYSCOMMAND, SC_MOVE | HTCAPTION, 0);
                result->Success(flutter::EncodableValue(true));
            } else {
                result->Error("NO_PRIMARY", "Could not find primary window");
            }
        }
    } else if (method == "minimizePrimaryWindow") {
        HWND primary = FindPrimaryRunnerWindow();
        if (primary && IsWindow(primary)) {
            ShowWindow(primary, SW_MINIMIZE);
            result->Success(flutter::EncodableValue(true));
        } else {
            result->Error("NO_PRIMARY", "Could not find primary window");
        }
    } else if (method == "maximizePrimaryWindow") {
        // Cluster-aware maximize: tile ALL windows into work area.
        // Keeps sidebar width & titlebar height fixed. Expands main to fill.
        HWND primary = FindPrimaryRunnerWindow();
        if (!primary || !IsWindow(primary)) {
            result->Error("NO_PRIMARY", "Could not find primary window");
            return;
        }

        // Check if we have saved pre-maximize rects.
        static bool is_cluster_maximized = false;
        static RECT saved_primary_rect = {};
        static std::vector<std::pair<HWND, RECT>> saved_child_rects;

        if (is_cluster_maximized) {
            // Restore from saved positions.
            HDWP hdwp = BeginDeferWindowPos(1 + static_cast<int>(saved_child_rects.size()));
            if (hdwp) {
                hdwp = DeferWindowPos(hdwp, primary, nullptr,
                    saved_primary_rect.left, saved_primary_rect.top,
                    saved_primary_rect.right - saved_primary_rect.left,
                    saved_primary_rect.bottom - saved_primary_rect.top,
                    SWP_NOZORDER | SWP_NOACTIVATE);
                for (auto& p : saved_child_rects) {
                    if (hdwp) {
                        hdwp = DeferWindowPos(hdwp, p.first, nullptr,
                            p.second.left, p.second.top,
                            p.second.right - p.second.left,
                            p.second.bottom - p.second.top,
                            SWP_NOZORDER | SWP_NOACTIVATE);
                    }
                }
                if (hdwp) EndDeferWindowPos(hdwp);
            }
            is_cluster_maximized = false;
            saved_child_rects.clear();
            result->Success(flutter::EncodableValue(true));
            return;
        }

        // Save current positions for restore.
        GetWindowRect(primary, &saved_primary_rect);

        // Get work area.
        HMONITOR mon = MonitorFromWindow(primary, MONITOR_DEFAULTTONEAREST);
        MONITORINFO mi = {};
        mi.cbSize = sizeof(mi);
        GetMonitorInfo(mon, &mi);
        RECT wa = mi.rcWork;
        int waW = wa.right - wa.left;
        int waH = wa.bottom - wa.top;

        // Find all children.
        struct EnumData {
            DWORD processId;
            HWND primaryHwnd;
            std::vector<HWND> children;
        };
        EnumData data;
        data.processId = GetCurrentProcessId();
        data.primaryHwnd = primary;
        EnumWindows([](HWND hwnd, LPARAM lParam) -> BOOL {
            auto* data = reinterpret_cast<EnumData*>(lParam);
            DWORD pid = 0;
            GetWindowThreadProcessId(hwnd, &pid);
            if (pid != data->processId) return TRUE;
            if (hwnd == data->primaryHwnd) return TRUE;
            wchar_t className[256] = {};
            GetClassNameW(hwnd, className, 256);
            if (wcscmp(className, L"FLUTTER_MULTI_WINDOW_WIN32_WINDOW") == 0) {
                if (IsWindowVisible(hwnd)) {
                    data->children.push_back(hwnd);
                }
            }
            return TRUE;
        }, reinterpret_cast<LPARAM>(&data));

        // Save child positions.
        saved_child_rects.clear();
        for (HWND ch : data.children) {
            RECT cr;
            GetWindowRect(ch, &cr);
            saved_child_rects.push_back({ch, cr});
        }

        // Get current layout metrics.
        RECT pr;
        GetWindowRect(primary, &pr);

        // Find cluster bounding box.
        int clLeft = pr.left, clTop = pr.top, clRight = pr.right, clBottom = pr.bottom;
        for (auto& ch : data.children) {
            RECT cr;
            GetWindowRect(ch, &cr);
            clLeft = min(clLeft, (int)cr.left);
            clTop = min(clTop, (int)cr.top);
            clRight = max(clRight, (int)cr.right);
            clBottom = max(clBottom, (int)cr.bottom);
        }

        // Compute gaps: distance between cluster left and primary left, etc.
        int leftReserve = pr.left - clLeft;    // sidebar width + gap
        int topReserve = pr.top - clTop;       // titlebar height + gap

        // New layout: fill work area.
        int newPrimaryX = wa.left + leftReserve;
        int newPrimaryY = wa.top + topReserve;
        int newPrimaryW = waW - leftReserve;
        int newPrimaryH = waH - topReserve;

        HDWP hdwp = BeginDeferWindowPos(1 + static_cast<int>(data.children.size()));
        if (hdwp) {
            hdwp = DeferWindowPos(hdwp, primary, nullptr,
                newPrimaryX, newPrimaryY, newPrimaryW, newPrimaryH,
                SWP_NOZORDER | SWP_NOACTIVATE);

            // Reposition children: keep their offset from primary, scale height to match.
            for (HWND ch : data.children) {
                RECT cr;
                GetWindowRect(ch, &cr);
                int chW = cr.right - cr.left;
                int chH = cr.bottom - cr.top;

                // Is this a "left" window (sidebar)?
                if (cr.right <= pr.left) {
                    // Sidebar: keep width, match primary height, align top.
                    int gap = pr.left - cr.right;
                    int newX = newPrimaryX - chW - gap;
                    int newY = newPrimaryY;
                    int newH = newPrimaryH;
                    if (hdwp) {
                        hdwp = DeferWindowPos(hdwp, ch, nullptr,
                            newX, newY, chW, newH,
                            SWP_NOZORDER | SWP_NOACTIVATE);
                    }
                }
                // Is this a "top" window (titlebar)?
                else if (cr.bottom <= pr.top) {
                    // Titlebar: span full width (sidebar + gap + primary), keep height.
                    int newX = wa.left;
                    int newY = wa.top;
                    int newW = waW;
                    if (hdwp) {
                        hdwp = DeferWindowPos(hdwp, ch, nullptr,
                            newX, newY, newW, chH,
                            SWP_NOZORDER | SWP_NOACTIVATE);
                    }
                }
                // Is this a "right" window?
                else if (cr.left >= pr.right) {
                    int gap = cr.left - pr.right;
                    int newX = newPrimaryX + newPrimaryW + gap;
                    int newY = newPrimaryY;
                    int newH = newPrimaryH;
                    if (hdwp) {
                        hdwp = DeferWindowPos(hdwp, ch, nullptr,
                            newX, newY, chW, newH,
                            SWP_NOZORDER | SWP_NOACTIVATE);
                    }
                }
                // Otherwise keep relative position.
                else {
                    int dx = cr.left - pr.left;
                    int dy = cr.top - pr.top;
                    if (hdwp) {
                        hdwp = DeferWindowPos(hdwp, ch, nullptr,
                            newPrimaryX + dx, newPrimaryY + dy, chW, chH,
                            SWP_NOZORDER | SWP_NOACTIVATE);
                    }
                }
            }
            if (hdwp) EndDeferWindowPos(hdwp);
        }

        is_cluster_maximized = true;
        result->Success(flutter::EncodableValue(true));
    } else if (method == "closePrimaryWindow") {
        HWND primary = FindPrimaryRunnerWindow();
        if (primary && IsWindow(primary)) {
            // Close ALL cluster windows.
            struct EnumData {
                DWORD processId;
                std::vector<HWND> all;
            };
            EnumData data;
            data.processId = GetCurrentProcessId();
            EnumWindows([](HWND hwnd, LPARAM lParam) -> BOOL {
                auto* data = reinterpret_cast<EnumData*>(lParam);
                DWORD pid = 0;
                GetWindowThreadProcessId(hwnd, &pid);
                if (pid != data->processId) return TRUE;
                wchar_t className[256] = {};
                GetClassNameW(hwnd, className, 256);
                if (wcscmp(className, L"FLUTTER_MULTI_WINDOW_WIN32_WINDOW") == 0) {
                    data->all.push_back(hwnd);
                }
                return TRUE;
            }, reinterpret_cast<LPARAM>(&data));

            // Close children first.
            for (HWND h : data.all) {
                PostMessage(h, WM_CLOSE, 0, 0);
            }
            // Then close primary.
            PostMessage(primary, WM_CLOSE, 0, 0);
            result->Success(flutter::EncodableValue(true));
        } else {
            result->Error("NO_PRIMARY", "Could not find primary window");
        }
    } else if (method == "toggleOverlay") {
        // Uses explicit HWNDs passed from Dart.
        if (!args || !std::holds_alternative<flutter::EncodableMap>(*args)) {
            result->Error("INVALID_ARGS", "Expected overlayHandle, primaryHandle, clusterHandles");
            return;
        }
        auto& map = std::get<flutter::EncodableMap>(*args);

        // Get overlay HWND.
        int64_t overlayHandle = 0;
        auto oIt = map.find(flutter::EncodableValue("overlayHandle"));
        if (oIt != map.end() && std::holds_alternative<int32_t>(oIt->second))
            overlayHandle = std::get<int32_t>(oIt->second);
        else if (oIt != map.end() && std::holds_alternative<int64_t>(oIt->second))
            overlayHandle = std::get<int64_t>(oIt->second);
        HWND overlay = reinterpret_cast<HWND>(static_cast<intptr_t>(overlayHandle));

        // Get primary HWND.
        int64_t primaryHandle = 0;
        auto pIt = map.find(flutter::EncodableValue("primaryHandle"));
        if (pIt != map.end() && std::holds_alternative<int32_t>(pIt->second))
            primaryHandle = std::get<int32_t>(pIt->second);
        else if (pIt != map.end() && std::holds_alternative<int64_t>(pIt->second))
            primaryHandle = std::get<int64_t>(pIt->second);
        HWND primary = reinterpret_cast<HWND>(static_cast<intptr_t>(primaryHandle));

        // Get cluster child HWNDs.
        std::vector<HWND> clusterChildren;
        auto cIt = map.find(flutter::EncodableValue("clusterHandles"));
        if (cIt != map.end() && std::holds_alternative<flutter::EncodableList>(cIt->second)) {
            auto& list = std::get<flutter::EncodableList>(cIt->second);
            for (auto& v : list) {
                int64_t h = 0;
                if (std::holds_alternative<int32_t>(v)) h = std::get<int32_t>(v);
                else if (std::holds_alternative<int64_t>(v)) h = std::get<int64_t>(v);
                clusterChildren.push_back(reinterpret_cast<HWND>(static_cast<intptr_t>(h)));
            }
        }

        if (!overlay || !IsWindow(overlay)) {
            result->Error("INVALID_OVERLAY", "Invalid overlay HWND");
            return;
        }

        // Read hideCluster flag (default: true).
        bool hideCluster = true;
        auto hcIt = map.find(flutter::EncodableValue("hideCluster"));
        if (hcIt != map.end() && std::holds_alternative<bool>(hcIt->second)) {
            hideCluster = std::get<bool>(hcIt->second);
        }

        if (IsWindowVisible(overlay)) {
            // HIDE overlay → RESTORE cluster (only if we hid it).

            // Remove TOPMOST first so overlay doesn't stay above everything.
            SetWindowPos(overlay, HWND_NOTOPMOST, 0, 0, 0, 0,
                SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
            ShowWindow(overlay, SW_HIDE);

            if (hideCluster) {
                // Restore primary first, then show children.
                if (primary && IsWindow(primary)) {
                    ShowWindow(primary, SW_RESTORE);
                    // Restore focus to primary after overlay hide.
                    SetForegroundWindow(primary);
                }
                for (HWND ch : clusterChildren) {
                    if (IsWindow(ch)) {
                        ShowWindow(ch, SW_SHOWNOACTIVATE);
                    }
                }
            } else {
                // Even without hideCluster, restore focus to primary.
                if (primary && IsWindow(primary)) {
                    SetForegroundWindow(primary);
                }
            }
        } else {
            // SHOW overlay.
            // Position overlay at bottom-right of DISPLAY work area.
            HMONITOR mon = primary ? MonitorFromWindow(primary, MONITOR_DEFAULTTONEAREST)
                                   : MonitorFromPoint({0, 0}, MONITOR_DEFAULTTOPRIMARY);
            MONITORINFO mi = {};
            mi.cbSize = sizeof(mi);
            GetMonitorInfo(mon, &mi);
            RECT wa = mi.rcWork;

            int overlayW = 320;
            int overlayH = 200;
            int x = wa.right - overlayW - 16;
            int y = wa.bottom - overlayH - 16;

            SetWindowPos(overlay, HWND_TOPMOST, x, y, overlayW, overlayH,
                SWP_NOACTIVATE);
            ShowWindow(overlay, SW_SHOWNA);

            // Only minimize cluster if hideCluster is true.
            if (hideCluster) {
                if (primary && IsWindow(primary)) {
                    ShowWindow(primary, SW_MINIMIZE);
                }
            }
        }
        result->Success(flutter::EncodableValue(true));
    } else {
        result->NotImplemented();
    }
}

HWND FlutterClusterWindowPlugin::FindPrimaryRunnerWindow() {
    struct EnumData {
        DWORD processId;
        HWND result;
    };

    EnumData data;
    data.processId = GetCurrentProcessId();
    data.result = nullptr;

    // Look for the Flutter runner window (main app window).
    EnumWindows([](HWND hwnd, LPARAM lParam) -> BOOL {
        auto* data = reinterpret_cast<EnumData*>(lParam);
        DWORD pid = 0;
        GetWindowThreadProcessId(hwnd, &pid);
        if (pid != data->processId) return TRUE;

        wchar_t className[256] = {};
        GetClassNameW(hwnd, className, 256);

        // The Flutter runner window uses this class name.
        if (wcscmp(className, L"FLUTTER_RUNNER_WIN32_WINDOW") == 0) {
            data->result = hwnd;
            return FALSE; // Found it, stop.
        }

        return TRUE;
    }, reinterpret_cast<LPARAM>(&data));

    return data.result;
}

void FlutterClusterWindowPlugin::RegisterWindowClass() {
    if (window_class_registered_) return;

    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(WNDCLASSEXW);
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = DefWindowProcW;
    wc.hInstance = GetModuleHandle(nullptr);
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    wc.lpszClassName = kWindowClassName;

    RegisterClassExW(&wc);
    window_class_registered_ = true;
}

void FlutterClusterWindowPlugin::DoCreateWindow(
    const flutter::EncodableMap& args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

    auto surface_id = GetString(args, "surfaceId");
    RECT frame = GetFrame(args);

    HWND hwnd = CreateWindowExW(
        WS_EX_APPWINDOW | WS_EX_TOOLWINDOW,
        kWindowClassName,
        L"Cluster Surface",
        WS_POPUP | WS_VISIBLE,
        frame.left, frame.top,
        frame.right - frame.left,
        frame.bottom - frame.top,
        nullptr, nullptr,
        GetModuleHandle(nullptr),
        nullptr);

    if (!hwnd) {
        result->Error("CREATE_FAILED", "CreateWindowEx failed");
        return;
    }

    // Subclass for event forwarding.
    SetWindowSubclass(hwnd, SubclassProc, 0, reinterpret_cast<DWORD_PTR>(this));

    // Register in handle registry.
    {
        std::lock_guard<std::mutex> lock(registry_mutex_);
        handle_registry_[hwnd] = { hwnd, surface_id, true };
        surface_to_hwnd_[surface_id] = hwnd;
    }

    // Emit WindowCreated event.
    int seq = ++sequence_counter_;
    flutter::EncodableMap event;
    event[flutter::EncodableValue("type")] = flutter::EncodableValue("WINDOW_CREATED");
    event[flutter::EncodableValue("sequenceId")] = flutter::EncodableValue(seq);
    event[flutter::EncodableValue("surfaceId")] = flutter::EncodableValue(surface_id);
    event[flutter::EncodableValue("nativeHandle")] = flutter::EncodableValue(
        static_cast<int64_t>(reinterpret_cast<intptr_t>(hwnd)));
    EmitEvent(event);

    result->Success(flutter::EncodableValue(
        static_cast<int64_t>(reinterpret_cast<intptr_t>(hwnd))));
}

void FlutterClusterWindowPlugin::DoMoveWindow(
    const flutter::EncodableMap& args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

    HWND hwnd = HwndFromHandle(args);
    RECT frame = GetFrame(args);

    if (!IsWindow(hwnd)) {
        result->Error("INVALID_HANDLE", "Window handle is not valid");
        return;
    }

    SetWindowPos(hwnd, nullptr,
        frame.left, frame.top,
        frame.right - frame.left,
        frame.bottom - frame.top,
        SWP_NOZORDER | SWP_NOACTIVATE);

    result->Success();
}

void FlutterClusterWindowPlugin::DoShowWindow(
    const flutter::EncodableMap& args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

    HWND hwnd = HwndFromHandle(args);
    if (!IsWindow(hwnd)) {
        result->Error("INVALID_HANDLE", "Window handle is not valid");
        return;
    }

    ShowWindow(hwnd, SW_SHOW);
    result->Success();
}

void FlutterClusterWindowPlugin::DoHideWindow(
    const flutter::EncodableMap& args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

    HWND hwnd = HwndFromHandle(args);
    if (!IsWindow(hwnd)) {
        result->Error("INVALID_HANDLE", "Window handle is not valid");
        return;
    }

    ShowWindow(hwnd, SW_HIDE);
    result->Success();
}

void FlutterClusterWindowPlugin::DoFocusWindow(
    const flutter::EncodableMap& args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

    HWND hwnd = HwndFromHandle(args);
    if (!IsWindow(hwnd)) {
        result->Error("INVALID_HANDLE", "Window handle is not valid");
        return;
    }

    SetForegroundWindow(hwnd);
    result->Success();
}

void FlutterClusterWindowPlugin::DoDestroyWindow(
    const flutter::EncodableMap& args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

    HWND hwnd = HwndFromHandle(args);
    auto surface_id = GetString(args, "surfaceId");

    if (IsWindow(hwnd)) {
        RemoveWindowSubclass(hwnd, SubclassProc, 0);
        // Hide first so it disappears immediately.
        ShowWindow(hwnd, SW_HIDE);
        // Then forcefully destroy from the owning thread.
        DWORD threadId = GetWindowThreadProcessId(hwnd, nullptr);
        DWORD currentThread = GetCurrentThreadId();
        if (threadId == currentThread) {
            DestroyWindow(hwnd);
        } else {
            // For cross-thread: post WM_CLOSE and WM_DESTROY.
            PostMessage(hwnd, WM_CLOSE, 0, 0);
        }
    }

    // Remove from registry.
    {
        std::lock_guard<std::mutex> lock(registry_mutex_);
        handle_registry_.erase(hwnd);
        surface_to_hwnd_.erase(surface_id);
    }

    result->Success();
}

void FlutterClusterWindowPlugin::DoExecuteBatch(
    const flutter::EncodableMap& args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

    auto it = args.find(flutter::EncodableValue("commands"));
    if (it == args.end() || !std::holds_alternative<flutter::EncodableList>(it->second)) {
        result->Error("INVALID_ARGS", "Expected 'commands' list");
        return;
    }

    const auto& commands = std::get<flutter::EncodableList>(it->second);

    // Count move commands for DeferWindowPos.
    int move_count = 0;
    for (const auto& cmd_val : commands) {
        if (std::holds_alternative<flutter::EncodableMap>(cmd_val)) {
            auto& cmd = std::get<flutter::EncodableMap>(cmd_val);
            if (GetString(cmd, "type") == "moveWindow") move_count++;
        }
    }

    // Use DeferWindowPos for batched moves.
    HDWP hdwp = nullptr;
    if (move_count > 0) {
        hdwp = BeginDeferWindowPos(move_count);
    }

    bool batch_ok = true;
    for (const auto& cmd_val : commands) {
        if (!std::holds_alternative<flutter::EncodableMap>(cmd_val)) continue;
        auto& cmd = std::get<flutter::EncodableMap>(cmd_val);
        auto type = GetString(cmd, "type");

        if (type == "moveWindow" && hdwp) {
            HWND hwnd = HwndFromHandle(cmd);
            RECT frame = GetFrame(cmd);

            if (IsWindow(hwnd)) {
                HDWP new_hdwp = DeferWindowPos(hdwp, hwnd, nullptr,
                    frame.left, frame.top,
                    frame.right - frame.left,
                    frame.bottom - frame.top,
                    SWP_NOZORDER | SWP_NOACTIVATE);

                if (new_hdwp) {
                    hdwp = new_hdwp;
                } else {
                    batch_ok = false;
                    SetWindowPos(hwnd, nullptr,
                        frame.left, frame.top,
                        frame.right - frame.left,
                        frame.bottom - frame.top,
                        SWP_NOZORDER | SWP_NOACTIVATE);
                }
            }
        }
    }

    if (hdwp && batch_ok) {
        EndDeferWindowPos(hdwp);
    }

    result->Success(flutter::EncodableValue(batch_ok));
}

void FlutterClusterWindowPlugin::DoQueryAllPositions(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

    flutter::EncodableMap positions;

    std::lock_guard<std::mutex> lock(registry_mutex_);
    for (const auto& [hwnd, entry] : handle_registry_) {
        if (!entry.is_alive || !IsWindow(hwnd)) continue;

        RECT rect;
        if (GetWindowRect(hwnd, &rect)) {
            flutter::EncodableMap frame;
            frame[flutter::EncodableValue("x")] = flutter::EncodableValue(static_cast<int32_t>(rect.left));
            frame[flutter::EncodableValue("y")] = flutter::EncodableValue(static_cast<int32_t>(rect.top));
            frame[flutter::EncodableValue("w")] = flutter::EncodableValue(static_cast<int32_t>(rect.right - rect.left));
            frame[flutter::EncodableValue("h")] = flutter::EncodableValue(static_cast<int32_t>(rect.bottom - rect.top));

            positions[flutter::EncodableValue(entry.surface_id)] = flutter::EncodableValue(frame);
        }
    }

    result->Success(flutter::EncodableValue(positions));
}

void FlutterClusterWindowPlugin::EmitEvent(const flutter::EncodableMap& event) {
    if (event_sink_) {
        event_sink_->Success(flutter::EncodableValue(event));
    }
}

LRESULT CALLBACK FlutterClusterWindowPlugin::SubclassProc(
    HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam,
    UINT_PTR subclass_id, DWORD_PTR ref_data) {

    auto* plugin = reinterpret_cast<FlutterClusterWindowPlugin*>(ref_data);

    // Find surface ID for this HWND.
    std::string surface_id;
    {
        std::lock_guard<std::mutex> lock(plugin->registry_mutex_);
        auto it = plugin->handle_registry_.find(hwnd);
        if (it != plugin->handle_registry_.end()) {
            surface_id = it->second.surface_id;
        } else {
            return DefSubclassProc(hwnd, message, wparam, lparam);
        }
    }

    switch (message) {
        case WM_ENTERSIZEMOVE: {
            plugin->is_dragging_ = true;
            plugin->dragging_surface_id_ = surface_id;

            int seq = ++(plugin->sequence_counter_);
            flutter::EncodableMap event;
            event[flutter::EncodableValue("type")] = flutter::EncodableValue("DRAG_STARTED");
            event[flutter::EncodableValue("sequenceId")] = flutter::EncodableValue(seq);
            event[flutter::EncodableValue("surfaceId")] = flutter::EncodableValue(surface_id);
            plugin->EmitEvent(event);
            break;
        }

        case WM_EXITSIZEMOVE: {
            plugin->is_dragging_ = false;
            plugin->dragging_surface_id_ = "";

            int seq = ++(plugin->sequence_counter_);
            flutter::EncodableMap event;
            event[flutter::EncodableValue("type")] = flutter::EncodableValue("DRAG_ENDED");
            event[flutter::EncodableValue("sequenceId")] = flutter::EncodableValue(seq);
            event[flutter::EncodableValue("surfaceId")] = flutter::EncodableValue(surface_id);
            plugin->EmitEvent(event);
            break;
        }

        case WM_MOVE: {
            RECT rect;
            if (GetWindowRect(hwnd, &rect)) {
                int seq = ++(plugin->sequence_counter_);
                std::string source = plugin->is_dragging_ ? "userDrag" : "system";

                flutter::EncodableMap frame;
                frame[flutter::EncodableValue("x")] = flutter::EncodableValue(static_cast<int32_t>(rect.left));
                frame[flutter::EncodableValue("y")] = flutter::EncodableValue(static_cast<int32_t>(rect.top));
                frame[flutter::EncodableValue("w")] = flutter::EncodableValue(static_cast<int32_t>(rect.right - rect.left));
                frame[flutter::EncodableValue("h")] = flutter::EncodableValue(static_cast<int32_t>(rect.bottom - rect.top));

                flutter::EncodableMap event;
                event[flutter::EncodableValue("type")] = flutter::EncodableValue("WINDOW_MOVED");
                event[flutter::EncodableValue("sequenceId")] = flutter::EncodableValue(seq);
                event[flutter::EncodableValue("surfaceId")] = flutter::EncodableValue(surface_id);
                event[flutter::EncodableValue("actualFrame")] = flutter::EncodableValue(frame);
                event[flutter::EncodableValue("source")] = flutter::EncodableValue(source);
                plugin->EmitEvent(event);
            }
            break;
        }

        case WM_SIZE: {
            RECT rect;
            if (GetWindowRect(hwnd, &rect)) {
                int seq = ++(plugin->sequence_counter_);
                std::string source = plugin->is_dragging_ ? "userDrag" : "system";

                flutter::EncodableMap frame;
                frame[flutter::EncodableValue("x")] = flutter::EncodableValue(static_cast<int32_t>(rect.left));
                frame[flutter::EncodableValue("y")] = flutter::EncodableValue(static_cast<int32_t>(rect.top));
                frame[flutter::EncodableValue("w")] = flutter::EncodableValue(static_cast<int32_t>(rect.right - rect.left));
                frame[flutter::EncodableValue("h")] = flutter::EncodableValue(static_cast<int32_t>(rect.bottom - rect.top));

                flutter::EncodableMap event;
                event[flutter::EncodableValue("type")] = flutter::EncodableValue("WINDOW_RESIZED");
                event[flutter::EncodableValue("sequenceId")] = flutter::EncodableValue(seq);
                event[flutter::EncodableValue("surfaceId")] = flutter::EncodableValue(surface_id);
                event[flutter::EncodableValue("actualFrame")] = flutter::EncodableValue(frame);
                event[flutter::EncodableValue("source")] = flutter::EncodableValue(source);
                plugin->EmitEvent(event);
            }
            break;
        }

        case WM_SETFOCUS:
        case WM_ACTIVATE: {
            if (message == WM_ACTIVATE && LOWORD(wparam) == WA_INACTIVE) break;

            int seq = ++(plugin->sequence_counter_);
            flutter::EncodableMap event;
            event[flutter::EncodableValue("type")] = flutter::EncodableValue("WINDOW_FOCUSED");
            event[flutter::EncodableValue("sequenceId")] = flutter::EncodableValue(seq);
            event[flutter::EncodableValue("surfaceId")] = flutter::EncodableValue(surface_id);
            plugin->EmitEvent(event);
            break;
        }

        case WM_DESTROY: {
            int seq = ++(plugin->sequence_counter_);
            flutter::EncodableMap event;
            event[flutter::EncodableValue("type")] = flutter::EncodableValue("WINDOW_DESTROYED");
            event[flutter::EncodableValue("sequenceId")] = flutter::EncodableValue(seq);
            event[flutter::EncodableValue("surfaceId")] = flutter::EncodableValue(surface_id);
            plugin->EmitEvent(event);

            {
                std::lock_guard<std::mutex> lock(plugin->registry_mutex_);
                auto it = plugin->handle_registry_.find(hwnd);
                if (it != plugin->handle_registry_.end()) {
                    it->second.is_alive = false;
                }
            }
            break;
        }

        case WM_NCDESTROY: {
            {
                std::lock_guard<std::mutex> lock(plugin->registry_mutex_);
                plugin->handle_registry_.erase(hwnd);
                plugin->surface_to_hwnd_.erase(surface_id);
            }
            RemoveWindowSubclass(hwnd, SubclassProc, subclass_id);
            break;
        }
    }

    return DefSubclassProc(hwnd, message, wparam, lparam);
}

}  // namespace flutter_cluster_window
