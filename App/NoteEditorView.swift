import SwiftUI

/// Apple-Notes style full-screen note editor. Notes no longer open in a
/// floating sheet: the page fills the screen and only 关闭/完成 leave it, so
/// an accidental tap cannot drop the editor.
struct NoteEditorView: View {
    @EnvironmentObject private var store: EntryStore
    @Environment(\.dismiss) private var dismiss
    let isNew: Bool
    @State private var draft: Entry
    @State private var title: String
    @State private var bodyText: String
    @State private var category: String
    @State private var checklist: [ChecklistItem]
    @State private var newStep = ""
    @FocusState private var titleFocused: Bool
    @State private var confirmDelete = false
    @FocusState private var bodyFocused: Bool

    init(entry: Entry, isNew: Bool) {
        self.isNew = isNew
        _draft = State(initialValue: entry)
        _title = State(initialValue: entry.title)
        _bodyText = State(initialValue: entry.body)
        _category = State(initialValue: entry.category)
        _checklist = State(initialValue: entry.checklist)
    }

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("关闭") { dismiss() }
                Spacer()
                if !isNew {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Image(systemName: "trash")
                    }.accessibilityLabel("删除笔记")
                }
                Button("完成") { save() }.fontWeight(.semibold).disabled(!canSave)
            }
            .font(.body)
            .padding(.horizontal, 20).padding(.vertical, 10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("标题", text: $title, axis: .vertical)
                        .font(.system(.title2, design: .default).weight(.bold))
                        .focused($titleFocused)
                        .submitLabel(.next)
                        .padding(.top, 8)
                    HStack(spacing: 12) {
                        TextField("分类（学习、生活、社团…）", text: $category)
                            .font(.footnote).foregroundStyle(.secondary)
                        Text(draft.updatedAt, format: .dateTime.month().day())
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    TextField("开始记录", text: $bodyText, axis: .vertical)
                        .font(.body)
                        .lineLimit(4...30)
                        .focused($bodyFocused)
                        .padding(.top, 2)
                    checklistSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.background)
        .task { if isNew && title.isEmpty { titleFocused = true } }
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                HStack {
                    Spacer()
                    Button("收起键盘") { titleFocused = false; bodyFocused = false }
                }
            }
        }
        .confirmationDialog("删除笔记？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除笔记", role: .destructive) {
                store.delete(draft.id)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后通过同步与备份仍可能保留副本。")
        }
    }

    @ViewBuilder private var checklistSection: some View {
        let steps = Binding(
            get: { checklist },
            set: { checklist = $0 }
        )
        ForEach(steps) { $step in
            HStack(alignment: .top, spacing: 10) {
                Button {
                    step.isDone.toggle()
                } label: {
                    Image(systemName: step.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.body)
                        .foregroundStyle(step.isDone ? Theme.accent : Color.secondary)
                }.buttonStyle(.plain)
                TextField("清单项", text: $step.title, axis: .vertical)
                    .strikethrough(step.isDone)
                    .foregroundStyle(step.isDone ? Color.secondary : Color.primary)
                Button {
                    checklist.removeAll { $0.id == step.id }
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(Color.secondary)
                }.buttonStyle(.plain).accessibilityLabel("删除清单项")
            }
            .padding(.vertical, 2)
        }
        HStack(spacing: 10) {
            Image(systemName: "plus.circle").foregroundStyle(Color.secondary)
            TextField("添加清单项", text: $newStep) {
                appendStep()
            }
            .onSubmit(appendStep)
        }
        .padding(.vertical, 2)
    }

    private func appendStep() {
        let trimmed = newStep.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        checklist.append(ChecklistItem(title: trimmed))
        newStep = ""
    }

    private func save() {
        guard canSave else { return }
        var next = draft
        next.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        next.body = bodyText
        next.category = category.trimmingCharacters(in: .whitespacesAndNewlines)
        next.checklist = checklist.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard store.save(next) else { return }
        dismiss()
    }
}
