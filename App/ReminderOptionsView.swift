import SwiftUI
import AVFoundation
import AudioToolbox

struct ReminderOptionsView: View {
    @EnvironmentObject private var notifications: NotificationManager
    @Binding var delivery: ReminderDelivery
    @Binding var sound: ReminderSound
    @Binding var snoozeMinutes: Int
    var body: some View {
        Picker("提醒形式", selection: $delivery) {
            ForEach(ReminderDelivery.allCases) { Text($0.title).tag($0) }
        }.clearOptionText().accessibilityIdentifier("reminder-delivery")
        NavigationLink { RingtonePicker(selection: $sound) } label: {
            LabeledContent { Text(sound.title).foregroundStyle(Color(uiColor: .label)) } label: { Text("铃声") }
        }.accessibilityIdentifier("reminder-ringtone")
        Picker("稍后提醒", selection: $snoozeMinutes) {
            ForEach([5, 10, 15], id: \.self) { Text("\($0) 分钟").tag($0) }
        }.clearOptionText()
        Text(delivery == .popup ? "使用 App 时显示弹窗；锁屏或后台显示系统通知。声音和横幅遵循系统通知设置。" :
            notifications.supportsAlarms ? "由系统闹钟响铃，可停止或稍后提醒。停止铃声不会将事项标为完成。" : "闹钟需要 iOS 26 或更新版本；当前系统请使用弹窗提醒。")
            .font(.caption).foregroundStyle(delivery == .alarm && !notifications.supportsAlarms ? Theme.warm : .secondary)
    }
}

struct RingtonePicker: View {
    @Binding var selection: ReminderSound
    @State private var player: AVAudioPlayer?
    @State private var error: String?
    var body: some View {
        List {
            Section {
                ForEach(ReminderSound.allCases) { sound in
                    Button {
                        selection = sound
                        preview(sound)
                    } label: {
                        HStack {
                            Text(sound.title).foregroundStyle(Color(uiColor: .label))
                            Spacer()
                            if sound == selection { Image(systemName: "checkmark").foregroundStyle(Theme.accent).fontWeight(.semibold) }
                        }.contentShape(Rectangle())
                    }.accessibilityIdentifier("ringtone-\(sound.rawValue)")
                        .accessibilityAddTraits(sound == selection ? .isSelected : [])
                }
            } footer: { Text("点选即可试听。晨光、清脆、节拍为 Mikansei 原创铃声；系统默认的试听为系统提示音，实际闹钟音由 iOS 决定。") }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }.navigationTitle("铃声").navigationBarTitleDisplayMode(.inline)
            .onDisappear { stopPreview() }
    }
    private func preview(_ sound: ReminderSound) {
        stopPreview(); error = nil
        guard let file = sound.fileName else { AudioServicesPlaySystemSound(1007); return }
        guard let url = Bundle.main.url(forResource: file, withExtension: nil) else { error = "未找到铃声文件。"; return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url); player?.prepareToPlay(); player?.play()
        } catch { self.error = "无法试听：\(error.localizedDescription)" }
    }
    private func stopPreview() {
        player?.stop(); player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

struct ReminderPopup: View {
    @EnvironmentObject private var notifications: NotificationManager
    let reminder: ForegroundReminder
    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("待办提醒", systemImage: "bell.fill").font(.subheadline).foregroundStyle(Theme.accent)
                    Spacer()
                    Button { notifications.dismissPopup(reminder) } label: { Image(systemName: "xmark").padding(6) }.accessibilityLabel("关闭提醒")
                }
                Text(reminder.content.title).font(.title3.weight(.semibold))
                Text(reminder.content.body).font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    Button("稍后 \(reminder.snoozeMinutes) 分钟") { Task { await notifications.snoozePopup(reminder) } }.buttonStyle(.bordered)
                    Spacer()
                    Button("查看") { notifications.openPopup(reminder) }.buttonStyle(.bordered)
                    if reminder.entryID != nil {
                        Button("完成") { notifications.completePopup(reminder) }.buttonStyle(.borderedProminent)
                    }
                }.font(.subheadline)
            }.padding(20).background(Theme.card, in: RoundedRectangle(cornerRadius: 22)).padding(20)
                .accessibilityAddTraits(.isModal)
        }
    }
}
