#include "pomodoro_floating_window.h"

#include <algorithm>
#include <cstdint>
#include <iomanip>
#include <map>
#include <sstream>
#include <utility>
#include <variant>

#include <flutter/encodable_value.h>

namespace {
constexpr wchar_t kWindowClass[] = L"MIKANSETA_POMODORO_FLOATING_WINDOW";
constexpr UINT_PTR kTimer = 1;
constexpr int kPrimaryButton = 1001;
constexpr int kFinishButton = 1002;

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) return L"";
  const int count = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, nullptr, 0);
  if (count <= 1) return L"";
  std::wstring output(static_cast<size_t>(count), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, output.data(), count);
  output.pop_back();
  return output;
}

const flutter::EncodableValue* Find(const flutter::EncodableMap& map,
                                    const char* key) {
  const auto found = map.find(flutter::EncodableValue(std::string(key)));
  return found == map.end() ? nullptr : &found->second;
}

std::string StringValue(const flutter::EncodableValue* value) {
  if (value == nullptr) return {};
  const auto string = std::get_if<std::string>(value);
  return string == nullptr ? std::string{} : *string;
}

double NumberValue(const flutter::EncodableValue* value, double fallback = 0) {
  if (value == nullptr) return fallback;
  if (const auto number = std::get_if<double>(value)) return *number;
  if (const auto number = std::get_if<int32_t>(value)) return *number;
  if (const auto number = std::get_if<int64_t>(value)) return static_cast<double>(*number);
  return fallback;
}

double CurrentEpoch() {
  FILETIME file_time;
  GetSystemTimeAsFileTime(&file_time);
  ULARGE_INTEGER value;
  value.LowPart = file_time.dwLowDateTime;
  value.HighPart = file_time.dwHighDateTime;
  return static_cast<double>(value.QuadPart) / 10000000.0 - 11644473600.0;
}

std::wstring FormatClock(double seconds) {
  const auto value = static_cast<int64_t>(std::max(0.0, seconds));
  const auto hours = value / 3600;
  const auto minutes = (value / 60) % 60;
  const auto remainder = value % 60;
  std::wostringstream output;
  output << std::setfill(L'0');
  if (hours > 0) {
    output << std::setw(2) << hours << L":" << std::setw(2) << minutes << L":"
           << std::setw(2) << remainder;
  } else {
    output << std::setw(2) << value / 60 << L":" << std::setw(2) << remainder;
  }
  return output.str();
}

bool RegisterWindowClass() {
  static bool registered = false;
  if (registered) return true;
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = PomodoroFloatingWindow::WindowProc;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpszClassName = kWindowClass;
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.hbrBackground = reinterpret_cast<HBRUSH>(static_cast<INT_PTR>(COLOR_WINDOW + 1));
  registered = RegisterClassW(&window_class) != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
  return registered;
}
}  // namespace

PomodoroFloatingWindow::PomodoroFloatingWindow(HWND owner,
                                               ActionHandler action_handler)
    : owner_(owner), action_handler_(std::move(action_handler)) {
  background_ = CreateSolidBrush(RGB(245, 237, 222));
}

PomodoroFloatingWindow::~PomodoroFloatingWindow() {
  if (window_ != nullptr) DestroyWindow(window_);
  if (clock_font_ != nullptr) DeleteObject(clock_font_);
  if (background_ != nullptr) DeleteObject(background_);
}

void PomodoroFloatingWindow::Show(const flutter::EncodableValue& snapshot) {
  UpdateSnapshot(snapshot);
  if (window_ == nullptr && !Create()) return;
  Render();
  ShowWindow(window_, SW_SHOWNORMAL);
  SetWindowPos(window_, HWND_TOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
  SetForegroundWindow(window_);
}

void PomodoroFloatingWindow::Hide() {
  if (window_ != nullptr) ShowWindow(window_, SW_HIDE);
}

void PomodoroFloatingWindow::UpdateSnapshot(const flutter::EncodableValue& snapshot) {
  const auto root = std::get_if<flutter::EncodableMap>(&snapshot);
  if (root == nullptr) return;
  const auto active_value = Find(*root, "active");
  const auto active = active_value == nullptr
                          ? nullptr
                          : std::get_if<flutter::EncodableMap>(active_value);
  if (active == nullptr) {
    session_id_.clear();
    subject_text_.clear();
    mode_.clear();
    target_seconds_ = 0;
    accumulated_seconds_ = 0;
    running_since_ = 0;
  } else {
    session_id_ = StringValue(Find(*active, "id"));
    subject_text_ = StringValue(Find(*active, "subject"));
    mode_ = StringValue(Find(*active, "mode"));
    target_seconds_ = NumberValue(Find(*active, "targetSeconds"));
    accumulated_seconds_ = NumberValue(Find(*active, "accumulatedSeconds"));
    running_since_ = NumberValue(Find(*active, "runningSince"));
  }
  if (window_ != nullptr) Render();
}

bool PomodoroFloatingWindow::Create() {
  if (!RegisterWindowClass()) return false;
  const DWORD style = WS_OVERLAPPEDWINDOW;
  const DWORD extended = WS_EX_TOOLWINDOW | WS_EX_TOPMOST;
  window_ = CreateWindowExW(extended, kWindowClass, L"专注计时器", style,
                            CW_USEDEFAULT, CW_USEDEFAULT, 360, 255, owner_, nullptr,
                            GetModuleHandle(nullptr), this);
  if (window_ == nullptr) return false;

  subject_ = CreateWindowW(L"STATIC", L"", WS_CHILD | WS_VISIBLE | SS_LEFT,
                           0, 0, 0, 0, window_, nullptr, GetModuleHandle(nullptr), nullptr);
  clock_ = CreateWindowW(L"STATIC", L"00:00", WS_CHILD | WS_VISIBLE | SS_CENTER,
                         0, 0, 0, 0, window_, nullptr, GetModuleHandle(nullptr), nullptr);
  status_ = CreateWindowW(L"STATIC", L"", WS_CHILD | WS_VISIBLE | SS_CENTER,
                          0, 0, 0, 0, window_, nullptr, GetModuleHandle(nullptr), nullptr);
  primary_ = CreateWindowW(L"BUTTON", L"打开专注页", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                           0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kPrimaryButton)),
                           GetModuleHandle(nullptr), nullptr);
  finish_ = CreateWindowW(L"BUTTON", L"结束", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                          0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kFinishButton)),
                          GetModuleHandle(nullptr), nullptr);
  clock_font_ = CreateFontW(48, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
                            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                            CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                            DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
  SendMessageW(clock_, WM_SETFONT, reinterpret_cast<WPARAM>(clock_font_), TRUE);
  SendMessageW(subject_, WM_SETFONT, reinterpret_cast<WPARAM>(GetStockObject(DEFAULT_GUI_FONT)), TRUE);
  SendMessageW(status_, WM_SETFONT, reinterpret_cast<WPARAM>(GetStockObject(DEFAULT_GUI_FONT)), TRUE);
  SendMessageW(primary_, WM_SETFONT, reinterpret_cast<WPARAM>(GetStockObject(DEFAULT_GUI_FONT)), TRUE);
  SendMessageW(finish_, WM_SETFONT, reinterpret_cast<WPARAM>(GetStockObject(DEFAULT_GUI_FONT)), TRUE);
  SetTimer(window_, kTimer, 1000, nullptr);
  Layout();
  return true;
}

void PomodoroFloatingWindow::Layout() {
  if (window_ == nullptr) return;
  RECT client{};
  GetClientRect(window_, &client);
  const int width = client.right - client.left;
  const int height = client.bottom - client.top;
  const int margin = 18;
  const int button_height = 34;
  const int button_gap = 10;
  const int usable_width = std::max(0, width - margin * 2);
  const int half_width = (usable_width - button_gap) / 2;
  const int clock_font_size = std::max(28, std::min(48, usable_width / 7));
  if (clock_font_size != clock_font_size_) {
    if (clock_font_ != nullptr) DeleteObject(clock_font_);
    clock_font_ = CreateFontW(clock_font_size, 0, 0, 0, FW_BOLD, FALSE, FALSE,
                              FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                              CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                              DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
    SendMessageW(clock_, WM_SETFONT, reinterpret_cast<WPARAM>(clock_font_), TRUE);
    clock_font_size_ = clock_font_size;
  }
  MoveWindow(subject_, margin, 12, usable_width, 42, TRUE);
  MoveWindow(clock_, margin, std::max(50, height / 2 - 30), usable_width, 58, TRUE);
  MoveWindow(status_, margin, std::max(104, height - 88), usable_width, 20, TRUE);
  MoveWindow(primary_, margin, height - 58, half_width, button_height, TRUE);
  MoveWindow(finish_, margin + half_width + button_gap, height - 58,
             half_width, button_height, TRUE);
}

void PomodoroFloatingWindow::Render() {
  if (window_ == nullptr) return;
  if (session_id_.empty()) {
    SetWindowTextW(subject_, L"还没有正在进行的专注");
    SetWindowTextW(clock_, L"00:00");
    SetWindowTextW(status_, L"打开 Mikanseta 设置主题和计时方式");
    SetWindowTextW(primary_, L"打开专注页");
    ShowWindow(finish_, SW_HIDE);
    return;
  }
  SetWindowTextW(subject_, Utf8ToWide(subject_text_).c_str());
  const double elapsed = accumulated_seconds_ +
      (running_since_ > 0 ? std::max(0.0, CurrentEpoch() - running_since_) : 0.0);
  const double remaining = std::max(0.0, target_seconds_ - elapsed);
  const bool countdown = mode_ == "countdown";
  SetWindowTextW(clock_, FormatClock(countdown ? remaining : elapsed).c_str());
  const wchar_t* label = running_since_ <= 0
                             ? L"已暂停 · 暂停时间不计入专注"
                             : countdown && remaining <= 0
                                   ? L"已到时间 · 打开应用归档"
                                   : countdown ? L"剩余时间" : L"已专注";
  SetWindowTextW(status_, label);
  SetWindowTextW(primary_, running_since_ > 0 ? L"暂停" : L"继续");
  SetWindowTextW(finish_, mode_ == "countUp" ? L"结束并保存" : L"提前结束");
  ShowWindow(finish_, SW_SHOW);
}

void PomodoroFloatingWindow::SendAction(const std::string& action) {
  if (action_handler_) action_handler_(action, session_id_);
}

LRESULT CALLBACK PomodoroFloatingWindow::WindowProc(HWND window, UINT message,
                                                      WPARAM wparam,
                                                      LPARAM lparam) noexcept {
  PomodoroFloatingWindow* self = nullptr;
  if (message == WM_NCCREATE) {
    const auto create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    self = static_cast<PomodoroFloatingWindow*>(create->lpCreateParams);
    SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
  } else {
    self = reinterpret_cast<PomodoroFloatingWindow*>(GetWindowLongPtrW(window, GWLP_USERDATA));
  }
  if (self != nullptr) return self->HandleMessage(window, message, wparam, lparam);
  return DefWindowProcW(window, message, wparam, lparam);
}

LRESULT PomodoroFloatingWindow::HandleMessage(HWND window, UINT message,
                                               WPARAM wparam,
                                               LPARAM lparam) noexcept {
  switch (message) {
    case WM_SIZE:
      Layout();
      return 0;
    case WM_TIMER:
      Render();
      return 0;
    case WM_COMMAND:
      if (LOWORD(wparam) == kPrimaryButton) {
        if (session_id_.empty()) {
          if (action_handler_) action_handler_("open", "");
        } else {
          SendAction(running_since_ > 0 ? "pause" : "resume");
        }
        return 0;
      }
      if (LOWORD(wparam) == kFinishButton) {
        SendAction("finish");
        return 0;
      }
      break;
    case WM_CLOSE:
      ShowWindow(window, SW_HIDE);
      return 0;
    case WM_GETMINMAXINFO: {
      auto limits = reinterpret_cast<MINMAXINFO*>(lparam);
      HDC dc = GetDC(window);
      const int dpi = dc == nullptr ? 96 : GetDeviceCaps(dc, LOGPIXELSX);
      if (dc != nullptr) ReleaseDC(window, dc);
      limits->ptMinTrackSize.x = MulDiv(280, dpi, 96);
      limits->ptMinTrackSize.y = MulDiv(260, dpi, 96);
      return 0;
    }
    case WM_DPICHANGED: {
      const auto suggested = reinterpret_cast<RECT*>(lparam);
      SetWindowPos(window, nullptr, suggested->left, suggested->top,
                   suggested->right - suggested->left,
                   suggested->bottom - suggested->top,
                   SWP_NOZORDER | SWP_NOACTIVATE);
      return 0;
    }
    case WM_CTLCOLORSTATIC: {
      HDC dc = reinterpret_cast<HDC>(wparam);
      SetTextColor(dc, RGB(56, 41, 30));
      SetBkMode(dc, TRANSPARENT);
      return reinterpret_cast<LRESULT>(background_);
    }
    case WM_ERASEBKGND: {
      RECT client{};
      GetClientRect(window, &client);
      FillRect(reinterpret_cast<HDC>(wparam), &client, background_);
      return 1;
    }
  }
  return DefWindowProcW(window, message, wparam, lparam);
}
