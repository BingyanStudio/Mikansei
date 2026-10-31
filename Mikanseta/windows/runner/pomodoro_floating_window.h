#ifndef RUNNER_POMODORO_FLOATING_WINDOW_H_
#define RUNNER_POMODORO_FLOATING_WINDOW_H_

#include <flutter/standard_message_codec.h>

#include <functional>
#include <string>

#include <windows.h>

/// A native, resizable always-on-top window controlled by the owning Flutter
/// engine. It renders snapshots and sends button actions back to Dart.
class PomodoroFloatingWindow {
 public:
  using ActionHandler = std::function<void(const std::string&, const std::string&)>;

  PomodoroFloatingWindow(HWND owner, ActionHandler action_handler);
  ~PomodoroFloatingWindow();

  void Show(const flutter::EncodableValue& snapshot);
  void Hide();
  void UpdateSnapshot(const flutter::EncodableValue& snapshot);
  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                                     LPARAM lparam) noexcept;

 private:
  LRESULT HandleMessage(HWND window, UINT message, WPARAM wparam, LPARAM lparam) noexcept;
  bool Create();
  void Layout();
  void Render();
  void SendAction(const std::string& action);

  HWND owner_ = nullptr;
  HWND window_ = nullptr;
  HWND subject_ = nullptr;
  HWND clock_ = nullptr;
  HWND status_ = nullptr;
  HWND primary_ = nullptr;
  HWND finish_ = nullptr;
  HFONT clock_font_ = nullptr;
  HBRUSH background_ = nullptr;
  int clock_font_size_ = 0;
  ActionHandler action_handler_;
  std::string session_id_;
  std::string subject_text_;
  std::string mode_;
  double target_seconds_ = 0;
  double accumulated_seconds_ = 0;
  double running_since_ = 0;
};

#endif  // RUNNER_POMODORO_FLOATING_WINDOW_H_
