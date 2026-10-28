import SwiftUI

struct CloudAccountSettings: View {
    @ObservedObject var cloud: CloudAccountManager

    @State private var emailInput = ""
    @State private var codeInput = ""
    @State private var confirmedAccountAndMerge = false
    @State private var resendUntil: Date?
    @State private var showSignOutConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var showFinalDeleteConfirmation = false

    private var normalizedEmail: String {
        emailInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedCode: String {
        codeInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var emailLooksValid: Bool {
        let parts = normalizedEmail.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".")
    }

    private var codeLooksValid: Bool {
        (6...10).contains(normalizedCode.count)
            && normalizedCode.allSatisfy { ("0"..."9").contains($0) }
    }

    private var accountDeletionSummary: String {
        "这会删除你的 Mikansei 与 Mikanseta 共享云端归档。其他设备将无法继续正常刷新登录状态或读写此归档；已有登录令牌可能在到期前仍有效。本机备份会保留，其他设备上的本地副本也不会自动删除。此操作无法撤销。"
    }

    var body: some View {
        Section {
            if !cloud.configured {
                Label("云账号同步暂不可用", systemImage: "icloud.slash")
                    .foregroundStyle(.secondary)
                Text("你仍可离线使用 Mikansei，事项会保存在本机。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if cloud.initializing && cloud.email == nil {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在恢复云账号登录状态…")
                }
                Text("你可以继续离线使用；恢复完成后即可登录或同步。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let email = cloud.email {
                signedInSection(email: email)
            } else {
                signInSection
            }
        } header: {
            Text("Mikansei · Mikanseta 云账号")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("同一邮箱可用于 Mikansei 和 Mikanseta。发送验证码时，邮箱会交由 Supabase 处理；确认登录后会同步完整归档。云同步不是端到端加密。")
                Link("查看隐私政策", destination: URL(string: "https://github.com/KikuchiHeinrich/Mikansei/blob/experimental/sync/Documentation/TestFlight/PRIVACY_POLICY.md")!)
            }
        }
        .onChange(of: emailInput) { _, _ in
            codeInput = ""
            confirmedAccountAndMerge = false
        }
        .confirmationDialog(
            "退出云账号？",
            isPresented: $showSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("退出登录", role: .destructive) {
                Task { await cloud.signOut() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("退出后会停止此账号的云同步，但本机事项和备份都会保留。")
        }
        .confirmationDialog(
            "申请删除云端账户？",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("继续", role: .destructive) {
                showFinalDeleteConfirmation = true
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(accountDeletionSummary)
        }
        .confirmationDialog(
            "最后确认：永久删除云端账户",
            isPresented: $showFinalDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("永久删除我的云端账户", role: .destructive) {
                Task { _ = await cloud.deleteAccount() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(accountDeletionSummary)
        }
    }

    private var signInSection: some View {
        Group {
            Text("使用邮箱验证码登录")
                .font(.headline)
            Text("首次登录会将本机数据与该账号的云端归档合并。请勿登录他人账号。你可以不登录并继续离线使用。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("邮箱地址", text: $emailInput)
                .textFieldStyle(.roundedBorder)
                .disabled(cloud.busy || cloud.initializing || cloud.sendingCode || cloud.verifyingCode || cloud.sessionTransitionInProgress)
                .accessibilityIdentifier("cloud-account-email")
            #if os(iOS)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            #endif

            sendCodeButton

            if let target = cloud.codeTarget {
                Text("验证码已发送至 \(target)。请输入邮件中的 6–10 位数字验证码。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("邮箱验证码", text: codeBinding)
                    .textFieldStyle(.roundedBorder)
                    .disabled(cloud.busy || cloud.initializing || cloud.sendingCode || cloud.verifyingCode || cloud.sessionTransitionInProgress)
                    .accessibilityIdentifier("cloud-account-code")
                #if os(iOS)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                #endif

                Toggle("我确认这是我的邮箱，并同意将本机数据与此账号合并", isOn: $confirmedAccountAndMerge)
                    .disabled(cloud.busy || cloud.initializing || cloud.sendingCode || cloud.verifyingCode || cloud.sessionTransitionInProgress)

                Button {
                    Task {
                        if await cloud.verifyCode(normalizedCode) {
                            codeInput = ""
                            confirmedAccountAndMerge = false
                            resendUntil = nil
                        }
                    }
                } label: {
                    if cloud.verifyingCode {
                        Label("正在验证…", systemImage: "hourglass")
                    } else {
                        Label("确认并登录", systemImage: "person.crop.circle.badge.checkmark")
                    }
                }
                .disabled(
                    !codeLooksValid
                        || !confirmedAccountAndMerge
                        || cloud.codeTarget?.caseInsensitiveCompare(normalizedEmail) != .orderedSame
                        || cloud.busy
                        || cloud.initializing
                        || cloud.verifyingCode
                        || cloud.sessionTransitionInProgress
                )
                .accessibilityIdentifier("cloud-account-verify")
            }

            if let error = cloud.loginError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var sendCodeButton: some View {
        if let resendUntil {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let secondsRemaining = max(0, Int(ceil(resendUntil.timeIntervalSince(context.date))))
                Button {
                    requestCode()
                } label: {
                    if cloud.sendingCode {
                        Label("正在发送验证码…", systemImage: "hourglass")
                    } else if secondsRemaining > 0 {
                        Label("重新发送（\(secondsRemaining) 秒）", systemImage: "envelope")
                    } else {
                        Label("重新发送验证码", systemImage: "envelope")
                    }
                }
                .disabled(
                    !emailLooksValid
                        || secondsRemaining > 0
                        || cloud.busy
                        || cloud.initializing
                        || cloud.sendingCode
                        || cloud.verifyingCode
                        || cloud.sessionTransitionInProgress
                )
                .accessibilityIdentifier("cloud-account-send-code")
            }
        } else {
            Button {
                requestCode()
            } label: {
                if cloud.sendingCode {
                    Label("正在发送验证码…", systemImage: "hourglass")
                } else {
                    Label("发送邮箱验证码", systemImage: "envelope")
                }
            }
            .disabled(
                !emailLooksValid
                    || cloud.busy
                    || cloud.initializing
                    || cloud.sendingCode
                    || cloud.verifyingCode
                    || cloud.sessionTransitionInProgress
            )
            .accessibilityIdentifier("cloud-account-send-code")
        }
    }

    private var codeBinding: Binding<String> {
        Binding(
            get: { codeInput },
            set: { newValue in
                codeInput = String(newValue.filter { ("0"..."9").contains($0) }.prefix(10))
            }
        )
    }

    private func signedInSection(email: String) -> some View {
        Group {
            Label("已登录", systemImage: "checkmark.icloud")
                .font(.headline)
            LabeledContent("邮箱", value: email)
            if let date = cloud.lastSyncedAt {
                LabeledContent("最后同步", value: date.formatted(date: .abbreviated, time: .shortened))
            } else {
                LabeledContent("最后同步", value: "尚未同步")
            }

            if cloud.needsInitialMergeConfirmation {
                Label("首次同步需要确认", systemImage: "exclamationmark.icloud")
                    .font(.headline)
                Text("此设备尚未记录这个账号的同步状态。确认后，系统会合并本机与云端归档，并开始同步。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await cloud.confirmInitialMerge() }
                } label: {
                    Label("确认合并并开始同步", systemImage: "arrow.triangle.2.circlepath.icloud")
                }
                .disabled(cloud.busy || cloud.initializing || cloud.sessionTransitionInProgress)
                .accessibilityIdentifier("cloud-account-confirm-initial-merge")
            }

            Button {
                Task { await cloud.syncNow() }
            } label: {
                if cloud.busy {
                    Label("正在同步…", systemImage: "arrow.triangle.2.circlepath")
                } else {
                    Label("立即同步", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .disabled(
                cloud.busy || cloud.initializing || cloud.deletingAccount
                    || cloud.needsInitialMergeConfirmation || cloud.sessionTransitionInProgress
            )
            .accessibilityIdentifier("cloud-account-sync-now")

            if let error = cloud.syncError {
                Label(error, systemImage: "exclamationmark.icloud")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let error = cloud.loginError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button("退出登录", systemImage: "rectangle.portrait.and.arrow.right") {
                showSignOutConfirmation = true
            }
            .disabled(cloud.busy || cloud.initializing || cloud.deletingAccount || cloud.sessionTransitionInProgress)

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                if cloud.deletingAccount {
                    Label("正在删除云端账户…", systemImage: "trash")
                } else {
                    Label("删除云端账户", systemImage: "trash")
                }
            }
            .disabled(cloud.busy || cloud.initializing || cloud.deletingAccount || cloud.sessionTransitionInProgress)
            .accessibilityIdentifier("cloud-account-delete")
        }
    }

    private func requestCode() {
        guard emailLooksValid else { return }
        let target = normalizedEmail
        resendUntil = Date().addingTimeInterval(60)
        Task {
            await cloud.sendCode(target)
            if cloud.loginError != nil {
                resendUntil = nil
            } else {
                codeInput = ""
                confirmedAccountAndMerge = false
            }
        }
    }
}
