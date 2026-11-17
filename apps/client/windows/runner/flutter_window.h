#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/method_channel.h>
#include <flutter/flutter_view_controller.h>

#include <memory>
#include <string>
#include <utility>
#include <vector>
#include <flutter/encodable_value.h>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project, bool start_hidden);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

  void AddTrayIcon();
  void RemoveTrayIcon();
  void UpdateTrayIcon();
  void ShowTrayMenu();
  void ApplyTrayState(const flutter::EncodableMap& state);
  bool SetAutoStart(bool enabled, bool hidden);
  void ShowMainWindow();

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> window_channel_;
  bool start_hidden_ = false;
  bool tray_added_ = false;
  UINT taskbar_created_message_ = 0;
  std::string vpn_state_ = "idle";
  std::string country_;
  std::string picker_ = "hidden";
  std::string selected_node_;
  std::string selected_transport_ = "automatic";
  std::vector<std::pair<std::string, std::string>> nodes_;
  std::vector<std::string> transports_;
  int latency_ = 0;
  bool busy_ = true;
  bool can_connect_ = false;
  bool close_requested_ = false;
  bool exit_requested_ = false;
  bool exit_in_progress_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
