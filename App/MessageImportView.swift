import SwiftUI

struct MessageImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var parsed: MessageParseResult?
    @State private var draft: Entry?
    var body: some View {
        if let draft { EntryEditor(entry: draft, isNew: true) }
        else {
            NavigationStack {
                Form {
                    Section {
                        TextEditor(text: $message).frame(minHeight: 180).accessibilityLabel("群消息原文")
                        PasteButton(payloadType: String.self) { strings in message = strings.joined(separator: "\n"); parsed = nil }
                        Button("提取建议", systemImage: "text.magnifyingglass") { parsed = MessageParser.parse(message) }
                            .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } header: { Text("粘贴一件事相关的群消息") } footer: {
                        Text("仅在本机解析，不读取 QQ 账号，也不会上传消息。每次整理一件事，确认后再保存。")
                    }
                    if let parsed {
                        Section("建议 · 请核对") {
                            Text(parsed.entry.title).font(.headline)
                            if !parsed.entry.platform.isEmpty { LabeledContent("平台", value: parsed.entry.platform) }
                            if let date = parsed.entry.dueDate { LabeledContent("截止", value: Theme.dateLabel(date)) }
                            if let minutes = parsed.entry.estimatedMinutes { LabeledContent("耗时", value: "\(minutes) 分钟") }
                            ForEach(parsed.assumptions, id: \.self) { Text($0).font(.caption).foregroundStyle(Theme.warm) }
                            Button("核对并编辑事项") { draft = parsed.entry }
                        }
                    }
                }.navigationTitle("从消息添加").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
                    .onChange(of: message) { _, _ in parsed = nil }
            }
        }
    }
}
