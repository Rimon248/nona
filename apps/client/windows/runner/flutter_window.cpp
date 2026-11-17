#include "flutter_window.h"

#include <optional>
#include <algorithm>
#include <cwchar>
#include <map>
#include <shellapi.h>
#include <variant>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {
constexpr UINT kTrayMessage = WM_APP + 41;
constexpr UINT kTrayIconId = 1;
constexpr UINT kConnect = 1000;
constexpr UINT kDisconnect = 1001;
constexpr UINT kRestart = 1002;
constexpr UINT kPing = 1003;
constexpr UINT kShow = 1004;
constexpr UINT kQuit = 1005;
constexpr UINT kAutomaticNode = 1100;
constexpr UINT kAutomaticTransport = 1300;

std::string StringValue(const flutter::EncodableMap& map, const char* key) {
  const auto found = map.find(flutter::EncodableValue(std::string(key)));
  if (found == map.end()) return {};
  const auto value = std::get_if<std::string>(&found->second);
  return value ? *value : std::string();
}

bool BoolValue(const flutter::EncodableMap& map, const char* key) {
  const auto found = map.find(flutter::EncodableValue(std::string(key)));
  if (found == map.end()) return false;
  const auto value = std::get_if<bool>(&found->second);
  return value && *value;
}

int IntValue(const flutter::EncodableMap& map, const char* key) {
  const auto found = map.find(flutter::EncodableValue(std::string(key)));
  if (found == map.end()) return 0;
  if (const auto value = std::get_if<int32_t>(&found->second)) return *value;
  if (const auto value = std::get_if<int64_t>(&found->second)) {
    return static_cast<int>(*value);
  }
  return 0;
}

std::wstring Wide(const std::string& text) {
  if (text.empty()) return {};
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                         text.c_str(), -1, nullptr, 0);
  if (length <= 1) return {};
  std::wstring result(static_cast<size_t>(length), L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.c_str(), -1,
                      result.data(), length);
  result.pop_back();
  return result;
}

std::wstring Status(const std::string& state) {
  if (state == "connected") return L"Подключено";
  if (state == "connecting") return L"Подключение";
  if (state == "disconnecting") return L"Отключение";
  if (state == "blocked" || state == "error") return L"Ошибка подключения";
  return L"Не подключено";
}
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             bool start_hidden)
    : project_(project), start_hidden_(start_hidden) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  window_channel_ = std::make_unique<
      flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "nona.window",
      &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "exitNow") {
          exit_requested_ = true;
          close_requested_ = false;
          PostMessage(GetHandle(), WM_CLOSE, 0, 0);
          result->Success();
        } else if (call.method_name() == "cancelExit") {
          exit_requested_ = false;
          close_requested_ = false;
          ShowMainWindow();
          result->Success();
        } else if (call.method_name() == "hideWindow") {
          close_requested_ = false;
          ShowWindow(GetHandle(), SW_HIDE);
          result->Success();
        } else if (call.method_name() == "showWindow") {
          ShowMainWindow();
          result->Success();
        } else if (call.method_name() == "setAutoStart") {
          const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
          if (args && SetAutoStart(BoolValue(*args, "enabled"),
                                   BoolValue(*args, "hidden"))) {
            result->Success();
          } else {
            result->Error("AUTOSTART_FAILED", "Could not change Windows startup");
          }
        } else if (call.method_name() == "updateTray") {
          const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
          if (args) ApplyTrayState(*args);
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  taskbar_created_message_ = RegisterWindowMessageW(L"TaskbarCreated");
  AddTrayIcon();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (!start_hidden_) this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
  window_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_DESTROY) RemoveTrayIcon();
  if (message == WM_CLOSE && !exit_requested_) {
    if (close_requested_) return 0;
    close_requested_ = true;
    if (window_channel_) {
      window_channel_->InvokeMethod(
          "requestExit", std::make_unique<flutter::EncodableValue>());
      return 0;
    }
    close_requested_ = false;
  }
  if (message == taskbar_created_message_ && taskbar_created_message_ != 0) {
    tray_added_ = false;
    AddTrayIcon();
    return 0;
  }
  if (message == kTrayMessage) {
    if (lparam == WM_RBUTTONUP || lparam == WM_CONTEXTMENU) {
      ShowTrayMenu();
    } else if (lparam == WM_LBUTTONDBLCLK) {
      ShowMainWindow();
    }
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::AddTrayIcon() {
  if (tray_added_ || !GetHandle()) return;
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = GetHandle();
  data.uID = kTrayIconId;
  data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  data.uCallbackMessage = kTrayMessage;
  data.hIcon = LoadIconW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON));
  const std::wstring tip = L"Нона — " + Status(vpn_state_);
  wcsncpy_s(data.szTip, _countof(data.szTip), tip.c_str(), _TRUNCATE);
  tray_added_ = Shell_NotifyIconW(NIM_ADD, &data) != FALSE;
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_added_) return;
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = GetHandle();
  data.uID = kTrayIconId;
  Shell_NotifyIconW(NIM_DELETE, &data);
  tray_added_ = false;
}

void FlutterWindow::UpdateTrayIcon() {
  if (!tray_added_) {
    AddTrayIcon();
    return;
  }
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = GetHandle();
  data.uID = kTrayIconId;
  data.uFlags = NIF_TIP;
  const std::wstring tip = L"Нона — " + Status(vpn_state_);
  wcsncpy_s(data.szTip, _countof(data.szTip), tip.c_str(), _TRUNCATE);
  Shell_NotifyIconW(NIM_MODIFY, &data);
}

void FlutterWindow::ApplyTrayState(const flutter::EncodableMap& state) {
  vpn_state_ = StringValue(state, "vpnState");
  country_ = StringValue(state, "country");
  picker_ = StringValue(state, "picker");
  selected_node_ = StringValue(state, "selectedNode");
  selected_transport_ = StringValue(state, "selectedTransport");
  latency_ = IntValue(state, "latency");
  busy_ = BoolValue(state, "busy");
  can_connect_ = BoolValue(state, "canConnect");
  nodes_.clear();
  transports_.clear();
  const auto nodes = state.find(flutter::EncodableValue(std::string("nodes")));
  if (nodes != state.end()) {
    if (const auto items = std::get_if<flutter::EncodableList>(&nodes->second)) {
      for (const auto& item : *items) {
        if (const auto node = std::get_if<flutter::EncodableMap>(&item)) {
          const auto id = StringValue(*node, "id");
          if (!id.empty()) nodes_.emplace_back(id, StringValue(*node, "country"));
        }
      }
    }
  }
  const auto transports = state.find(flutter::EncodableValue(std::string("transports")));
  if (transports != state.end()) {
    if (const auto items = std::get_if<flutter::EncodableList>(&transports->second)) {
      for (const auto& item : *items) {
        if (const auto name = std::get_if<std::string>(&item)) {
          transports_.push_back(*name);
        }
      }
    }
  }
  UpdateTrayIcon();
}

void FlutterWindow::ShowTrayMenu() {
  HMENU menu = CreatePopupMenu();
  if (!menu) return;
  std::map<UINT, std::string> actions{
      {kConnect, "connect"}, {kDisconnect, "disconnect"},
      {kRestart, "restart"}, {kPing, "ping"},
      {kShow, "show"}, {kQuit, "quit"}};
  const bool connected = vpn_state_ == "connected";
  const std::wstring status = L"Состояние: " + Status(vpn_state_);
  const std::wstring country = L"Страна: " +
      (country_.empty() ? std::wstring(L"—") : Wide(country_));
  const std::wstring ping = latency_ > 0
      ? L"Пинг: " + std::to_wstring(latency_) + L" мс" : L"Пинг: —";
  AppendMenuW(menu, MF_STRING | MF_GRAYED, 0, status.c_str());
  AppendMenuW(menu, MF_STRING | MF_GRAYED, 0, country.c_str());
  AppendMenuW(menu, MF_STRING | MF_GRAYED, 0, ping.c_str());
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING | (can_connect_ && !busy_ ? 0 : MF_GRAYED),
              kConnect, L"Включить VPN");
  AppendMenuW(menu, MF_STRING | (connected && !busy_ ? 0 : MF_GRAYED),
              kDisconnect, L"Отключить VPN");
  AppendMenuW(menu, MF_STRING | (connected && !busy_ ? 0 : MF_GRAYED),
              kRestart, L"Переподключить VPN");
  AppendMenuW(menu, MF_STRING | (connected && !busy_ ? 0 : MF_GRAYED),
              kPing, L"Проверить пинг");

  if ((picker_ == "country" || picker_ == "both") && !nodes_.empty()) {
    HMENU choices = CreatePopupMenu();
    if (choices) {
      actions[kAutomaticNode] = "node:";
      AppendMenuW(choices, MF_STRING | (selected_node_.empty() ? MF_CHECKED : 0) |
                   (busy_ ? MF_GRAYED : 0), kAutomaticNode, L"Автоматически");
      for (size_t index = 0; index < nodes_.size() && index < 150; ++index) {
        const UINT id = kAutomaticNode + 1 + static_cast<UINT>(index);
        actions[id] = "node:" + nodes_[index].first;
        const std::wstring label = Wide(nodes_[index].second);
        AppendMenuW(choices, MF_STRING |
                    (selected_node_ == nodes_[index].first ? MF_CHECKED : 0) |
                    (busy_ ? MF_GRAYED : 0), id, label.c_str());
      }
      AppendMenuW(menu, MF_POPUP, reinterpret_cast<UINT_PTR>(choices),
                  L"Страна сервера");
    }
  }
  if (picker_ == "transport" || picker_ == "both") {
    HMENU choices = CreatePopupMenu();
    if (choices) {
      actions[kAutomaticTransport] = "transport:automatic";
      AppendMenuW(choices, MF_STRING |
                  (selected_transport_ == "automatic" ? MF_CHECKED : 0) |
                  (busy_ ? MF_GRAYED : 0), kAutomaticTransport,
                  L"Автоматически");
      for (size_t index = 0; index < transports_.size() && index < 100; ++index) {
        const UINT id = kAutomaticTransport + 1 + static_cast<UINT>(index);
        const auto& transport = transports_[index];
        actions[id] = "transport:" + transport;
        const wchar_t* label = transport == "hysteria2" ? L"Hysteria2" : L"VLESS";
        AppendMenuW(choices, MF_STRING |
                    (selected_transport_ == transport ? MF_CHECKED : 0) |
                    (busy_ ? MF_GRAYED : 0), id, label);
      }
      AppendMenuW(menu, MF_POPUP, reinterpret_cast<UINT_PTR>(choices),
                  L"Способ подключения");
    }
  }
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kShow, L"Открыть Нону");
  AppendMenuW(menu, MF_STRING, kQuit, L"Полностью выйти");

  POINT point{};
  GetCursorPos(&point);
  SetForegroundWindow(GetHandle());
  const UINT selected = TrackPopupMenu(menu,
      TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_BOTTOMALIGN,
      point.x, point.y, 0, GetHandle(), nullptr);
  DestroyMenu(menu);
  PostMessageW(GetHandle(), WM_NULL, 0, 0);
  const auto action = actions.find(selected);
  if (action != actions.end() && window_channel_) {
    window_channel_->InvokeMethod("trayAction",
        std::make_unique<flutter::EncodableValue>(action->second));
  }
}

bool FlutterWindow::SetAutoStart(bool enabled, bool hidden) {
  wchar_t system[MAX_PATH]{};
  if (!GetSystemDirectoryW(system, MAX_PATH)) return false;
  const std::wstring scheduler = std::wstring(system) + L"\\schtasks.exe";
  std::wstring command = L"\"" + scheduler + L"\"";
  if (!enabled) {
    command += L" /Delete /TN \"Nona VPN\" /F";
  } else {
    wchar_t path[MAX_PATH]{};
    const DWORD length = GetModuleFileNameW(nullptr, path, MAX_PATH);
    if (length == 0 || length >= MAX_PATH) return false;
    command += L" /Create /SC ONLOGON /TN \"Nona VPN\" /TR \"\\\"";
    command += path;
    command += L"\\\"";
    if (hidden) command += L" --nona-start-hidden";
    command += L"\" /RL HIGHEST /IT /F";
  }
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process{};
  if (!CreateProcessW(scheduler.c_str(), command.data(), nullptr, nullptr,
                      FALSE, CREATE_NO_WINDOW, nullptr, nullptr,
                      &startup, &process)) {
    return false;
  }
  const DWORD wait = WaitForSingleObject(process.hProcess, 15000);
  DWORD exit_code = 1;
  if (wait == WAIT_OBJECT_0) GetExitCodeProcess(process.hProcess, &exit_code);
  if (wait == WAIT_TIMEOUT) TerminateProcess(process.hProcess, 1);
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  return wait == WAIT_OBJECT_0 && exit_code == 0;
}

void FlutterWindow::ShowMainWindow() {
  start_hidden_ = false;
  close_requested_ = false;
  ShowWindow(GetHandle(), SW_RESTORE);
  SetForegroundWindow(GetHandle());
}
