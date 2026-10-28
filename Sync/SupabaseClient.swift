import Foundation
import Security

struct SupabaseConfiguration {
    let url: URL?
    let anonKey: String

    var isConfigured: Bool {
        guard let url,
              url.scheme?.lowercased() == "https",
              url.host != nil,
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil,
              url.path.isEmpty || url.path == "/",
              !Self.isUnexpandedBuildSetting(anonKey),
              Self.isPublicAPIKey(anonKey) else {
            return false
        }
        return true
    }

    init(url: URL?, anonKey: String) {
        self.url = url
        self.anonKey = anonKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func fromBundle() -> SupabaseConfiguration {
        let fallback = Bundle.main.url(forResource: "SupabaseClient", withExtension: "plist")
            .flatMap { NSDictionary(contentsOf: $0) as? [String: Any] } ?? [:]
        let info = Bundle.main.infoDictionary ?? [:]

        let urlValue = resolvedString(primary: info["MikanseiSupabaseURL"], fallback: fallback["MikanseiSupabaseURL"])
        let keyValue = resolvedString(primary: info["MikanseiSupabaseAnonKey"], fallback: fallback["MikanseiSupabaseAnonKey"])
        let url = urlValue.flatMap(URL.init(string:))

        return SupabaseConfiguration(url: url, anonKey: keyValue ?? "")
    }

    private static func resolvedString(primary: Any?, fallback: Any?) -> String? {
        for candidate in [primary, fallback] {
            guard let value = candidate as? String else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !isUnexpandedBuildSetting(trimmed) else { continue }
            return trimmed
        }
        return nil
    }

    private static func isUnexpandedBuildSetting(_ value: String) -> Bool {
        value.contains("$(")
    }

    private static func isPublicAPIKey(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        guard !lowercased.hasPrefix("sb_secret_"),
              lowercased != "service_role",
              !value.isEmpty else {
            return false
        }

        if value.hasPrefix("sb_publishable_") {
            return value.count > "sb_publishable_".count
        }

        let tokenParts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard tokenParts.count == 3 else { return false }
        var payload = String(tokenParts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 {
            payload.append("=")
        }
        guard let payloadData = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let role = object["role"] as? String else {
            return false
        }
        return role == "anon"
    }
}

struct SupabaseSession: Codable, Equatable {
    let userID: String
    let email: String
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}

struct SupabaseArchiveRecord: Equatable {
    let revision: Int64
    let content: String
}

enum SupabaseClientError: LocalizedError {
    case notConfigured
    case insecureEndpoint
    case invalidResponse
    case transportUnavailable
    case requestCancelled
    case operationSuperseded
    case noSession
    case sessionExpired
    case invalidEmail
    case invalidCode
    case rateLimited
    case conflict
    case deleteAccountNotReady
    case keychainUnavailable
    case keychainCouldNotClear
    case accountDeletedButSessionCouldNotClear
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "云同步尚未配置。"
        case .insecureEndpoint:
            return "云同步地址必须使用 HTTPS。"
        case .invalidResponse:
            return "云端返回的数据格式无法识别。"
        case .transportUnavailable:
            return "暂时无法连接 Supabase，请检查网络后重试。"
        case .requestCancelled:
            return "请求已取消。"
        case .operationSuperseded:
            return "登录状态已变化，请重试刚才的操作。"
        case .noSession:
            return "请先登录 Supabase 账户。"
        case .sessionExpired:
            return "登录已过期，请重新登录。"
        case .invalidEmail:
            return "请输入有效的电子邮箱地址。"
        case .invalidCode:
            return "验证码无效或已过期，请检查后重试。"
        case .rateLimited:
            return "验证码发送过于频繁，请稍后再试。"
        case .conflict:
            return "云端内容已被其他设备更新，请先同步最新内容再重试。"
        case .deleteAccountNotReady:
            return "账户删除服务尚未部署，请稍后重试或联系管理员。"
        case .keychainUnavailable:
            return "无法安全保存登录状态，请检查设备钥匙串设置后重试。"
        case .keychainCouldNotClear:
            return "无法删除设备上保存的登录凭据，退出状态未能确认。"
        case .accountDeletedButSessionCouldNotClear:
            return "云端账户已删除，但设备上保存的登录凭据无法清除。请重试退出登录。"
        case .httpStatus(let status):
            return "Supabase 请求失败（HTTP \(status)），请稍后重试。"
        }
    }
}

@MainActor
final class SupabaseClient {
    let configuration: SupabaseConfiguration
    private(set) var session: SupabaseSession?

    private let urlSession: URLSession
    private let webSocketSession: URLSession
    private let sessionStore: SupabaseSessionStore

    private var generation = 0
    private var activeRequests: [UUID: URLSessionDataTask] = [:]
    private var authenticationTransitionInProgress = false
    private var sessionIsExpired = false

    private var refreshTask: Task<SupabaseSession, Error>?
    private var refreshTaskID: UUID?
    private var refreshTokenBeingUsed: String?

    private var realtimeWanted = false
    private var realtimeGeneration = 0
    private var realtimeCallback: (@MainActor () -> Void)?
    private var realtimeSocket: URLSessionWebSocketTask?
    private var realtimeTopic: String?
    private var realtimeJoinReference: String?
    private var realtimeSubscriptionIDs: Set<String> = []
    private var realtimeJoined = false
    private var realtimeReceiveTask: Task<Void, Never>?
    private var realtimeHeartbeatTask: Task<Void, Never>?
    private var realtimeJoinTimeoutTask: Task<Void, Never>?
    private var realtimeHeartbeatTimeoutTask: Task<Void, Never>?
    private var realtimeHeartbeatReference: String?
    private var realtimeReconnectTask: Task<Void, Never>?
    private var realtimeTokenRefreshTask: Task<Void, Never>?
    private var realtimeReconnectAttempts = 0

    init(configuration: SupabaseConfiguration = .fromBundle()) {
        self.configuration = configuration

        let urlConfiguration = URLSessionConfiguration.ephemeral
        urlConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        urlConfiguration.urlCache = nil
        urlConfiguration.httpCookieStorage = nil
        urlConfiguration.timeoutIntervalForRequest = 30
        urlConfiguration.timeoutIntervalForResource = 60
        self.urlSession = URLSession(configuration: urlConfiguration)
        let webSocketConfiguration = URLSessionConfiguration.ephemeral
        webSocketConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        webSocketConfiguration.urlCache = nil
        webSocketConfiguration.httpCookieStorage = nil
        self.webSocketSession = URLSession(configuration: webSocketConfiguration)
        self.sessionStore = SupabaseSessionStore(configuration: configuration, bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown.bundle")
    }

    func restoreSession() async throws {
        try requireConfiguration()
        invalidateAccountWork(stopRealtime: true)
        authenticationTransitionInProgress = true
        let restoreGeneration = generation
        let restored: SupabaseSession?
        do {
            restored = try sessionStore.load()
        } catch {
            if generation == restoreGeneration {
                authenticationTransitionInProgress = false
            }
            throw error
        }
        guard generation == restoreGeneration else { throw SupabaseClientError.operationSuperseded }
        session = restored
        sessionIsExpired = false
        authenticationTransitionInProgress = false

        guard let restored else { return }
        let binding = SessionBinding(generation: restoreGeneration, userID: restored.userID)
        if restored.expiresAt <= Date().addingTimeInterval(60) {
            _ = try await refreshSession(for: binding, failedAccessToken: restored.accessToken)
        }
    }

    func sendCode(email: String) async throws {
        try requireConfiguration()
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.looksLikeEmail(normalizedEmail) else { throw SupabaseClientError.invalidEmail }

        let body = OTPRequest(email: normalizedEmail, createUser: true)
        let request = try makeRequest(path: "auth/v1/otp", method: "POST", body: body, authenticatedBy: nil)
        let response = try await perform(request)
        try requireSuccess(response, context: .sendCode)
    }

    func verifyCode(email: String, code: String) async throws {
        try requireConfiguration()
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.looksLikeEmail(normalizedEmail), !normalizedCode.isEmpty else {
            throw SupabaseClientError.invalidCode
        }

        invalidateAccountWork(stopRealtime: true)
        authenticationTransitionInProgress = true
        let verificationGeneration = generation
        defer {
            if generation == verificationGeneration {
                authenticationTransitionInProgress = false
            }
        }

        let body = VerifyOTPRequest(email: normalizedEmail, token: normalizedCode, type: "email")
        let request = try makeRequest(path: "auth/v1/verify", method: "POST", body: body, authenticatedBy: nil)
        let response = try await perform(request)
        guard generation == verificationGeneration else { throw SupabaseClientError.operationSuperseded }
        try requireSuccess(response, context: .verifyCode)

        let decoded = try decodeAuthToken(response.data)
        let newSession = try makeSession(from: decoded, fallbackEmail: normalizedEmail, existingSession: nil)
        guard generation == verificationGeneration else { throw SupabaseClientError.operationSuperseded }
        do {
            try sessionStore.save(newSession)
        } catch {
            throw SupabaseClientError.keychainUnavailable
        }
        guard generation == verificationGeneration else { throw SupabaseClientError.operationSuperseded }

        session = newSession
        sessionIsExpired = false
    }

    func fetchArchive() async throws -> SupabaseArchiveRecord? {
        let binding = try await requireCurrentSession()
        let query = [
            URLQueryItem(name: "select", value: "revision,content"),
            URLQueryItem(name: "user_id", value: "eq.\(binding.userID)"),
            URLQueryItem(name: "limit", value: "1")
        ]
        let data = try await authenticatedData(
            path: "rest/v1/mikanseta_archives",
            queryItems: query,
            method: "GET",
            body: Optional<EmptyRequestBody>.none,
            binding: binding,
            context: .archive
        )

        let rows: [ArchiveRow]
        do {
            rows = try JSONDecoder().decode([ArchiveRow].self, from: data)
        } catch {
            throw SupabaseClientError.invalidResponse
        }
        guard rows.count <= 1 else { throw SupabaseClientError.invalidResponse }
        guard let row = rows.first else { return nil }
        return SupabaseArchiveRecord(revision: row.revision, content: row.content)
    }

    @discardableResult
    func uploadArchive(_ content: String, expectedRevision: Int64?) async throws -> Int64 {
        let binding = try await requireCurrentSession()
        let revision = try Self.nextRevision(after: expectedRevision)
        let write = ArchiveWrite(
            userID: binding.userID,
            revision: revision,
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            content: content
        )

        if let expectedRevision {
            let query = [
                URLQueryItem(name: "user_id", value: "eq.\(binding.userID)"),
                URLQueryItem(name: "revision", value: "eq.\(expectedRevision)")
            ]
            let data = try await authenticatedData(
                path: "rest/v1/mikanseta_archives",
                queryItems: query,
                method: "PATCH",
                body: write,
                extraHeaders: ["Prefer": "return=representation"],
                binding: binding,
                context: .archive
            )
            return try returnedRevision(from: data)
        } else {
            do {
                let data = try await authenticatedData(
                    path: "rest/v1/mikanseta_archives",
                    queryItems: [],
                    method: "POST",
                    body: write,
                    extraHeaders: ["Prefer": "return=representation"],
                    binding: binding,
                    context: .archiveInsert
                )
                return try returnedRevision(from: data)
            } catch SupabaseClientError.conflict {
                throw SupabaseClientError.conflict
            } catch {
                throw error
            }
        }
    }

    func signOut() async throws {
        let previousSession = session
        invalidateAccountWork(stopRealtime: true)
        authenticationTransitionInProgress = true

        do {
            try sessionStore.delete()
        } catch {
            authenticationTransitionInProgress = false
            throw SupabaseClientError.keychainCouldNotClear
        }

        session = nil
        sessionIsExpired = false
        authenticationTransitionInProgress = false

        guard let previousSession else { return }
        let request: URLRequest
        do {
            request = try makeRequest(
                path: "auth/v1/logout",
                queryItems: [URLQueryItem(name: "scope", value: "local")],
                method: "POST",
                body: Optional<EmptyRequestBody>.none,
                authenticatedBy: previousSession.accessToken
            )
        } catch {
            throw error
        }

        let response: HTTPResult
        do {
            response = try await perform(request)
        } catch {
            throw error
        }
        if response.statusCode == 401 {
            return
        }
        try requireSuccess(response, context: .generic)
    }

    func deleteAccount() async throws {
        let binding = try await requireCurrentSession()
        _ = try await authenticatedData(
            path: "rest/v1/rpc/mikansei_delete_account",
            queryItems: [],
            method: "POST",
            body: EmptyRequestBody(),
            binding: binding,
            context: .deleteAccount
        )
        try validate(binding)

        invalidateAccountWork(stopRealtime: true)
        authenticationTransitionInProgress = true
        do {
            try sessionStore.delete()
        } catch {
            sessionIsExpired = true
            authenticationTransitionInProgress = false
            throw SupabaseClientError.accountDeletedButSessionCouldNotClear
        }
        session = nil
        sessionIsExpired = false
        authenticationTransitionInProgress = false
    }

    func startRealtime(onChange: @escaping @MainActor () -> Void) async throws {
        try requireConfiguration()
        _ = try await requireCurrentSession()

        stopRealtime()
        realtimeWanted = true
        realtimeCallback = onChange
        realtimeReconnectAttempts = 0
        realtimeGeneration &+= 1
        await connectRealtime(generation: realtimeGeneration)
    }

    func stopRealtime() {
        realtimeWanted = false
        realtimeGeneration &+= 1
        realtimeCallback = nil
        cancelRealtimeConnection()
    }

    private func requireCurrentSession() async throws -> SessionBinding {
        try requireConfiguration()
        guard !authenticationTransitionInProgress else { throw SupabaseClientError.operationSuperseded }
        guard !sessionIsExpired else { throw SupabaseClientError.sessionExpired }
        guard let current = session else { throw SupabaseClientError.noSession }

        let binding = SessionBinding(generation: generation, userID: current.userID)
        if current.expiresAt <= Date().addingTimeInterval(60) {
            _ = try await refreshSession(for: binding, failedAccessToken: current.accessToken)
            try validate(binding)
        }
        return binding
    }

    private func authenticatedData<Body: Encodable>(
        path: String,
        queryItems: [URLQueryItem],
        method: String,
        body: Body?,
        extraHeaders: [String: String] = [:],
        binding: SessionBinding,
        context: RequestContext,
        mayRefreshAfterUnauthorized: Bool = true
    ) async throws -> Data {
        try validate(binding)
        guard let current = session else { throw SupabaseClientError.noSession }

        var request = try makeRequest(
            path: path,
            queryItems: queryItems,
            method: method,
            body: body,
            authenticatedBy: current.accessToken,
            extraHeaders: extraHeaders
        )
        request.setValue("Bearer \(current.accessToken)", forHTTPHeaderField: "Authorization")

        let result = try await perform(request)
        try validate(binding)

        if result.statusCode == 401 {
            if mayRefreshAfterUnauthorized {
                _ = try await refreshSession(for: binding, failedAccessToken: current.accessToken)
                return try await authenticatedData(
                    path: path,
                    queryItems: queryItems,
                    method: method,
                    body: body,
                    extraHeaders: extraHeaders,
                    binding: binding,
                    context: context,
                    mayRefreshAfterUnauthorized: false
                )
            }
            sessionIsExpired = true
            stopRealtime()
            throw SupabaseClientError.sessionExpired
        }

        try requireSuccess(result, context: context)
        return result.data
    }

    private func refreshSession(for binding: SessionBinding, failedAccessToken: String) async throws -> SupabaseSession {
        try validate(binding)
        guard let current = session else { throw SupabaseClientError.noSession }
        if current.accessToken != failedAccessToken {
            return current
        }

        let refreshToken = current.refreshToken
        if let refreshTask, refreshTokenBeingUsed == refreshToken {
            return try await refreshTask.value
        }

        let taskID = UUID()
        refreshTaskID = taskID
        refreshTokenBeingUsed = refreshToken
        let task = Task<SupabaseSession, Error> { @MainActor [weak self] in
            guard let self else { throw SupabaseClientError.operationSuperseded }
            return try await self.performRefresh(refreshToken: refreshToken, binding: binding)
        }
        refreshTask = task

        do {
            let value = try await task.value
            if refreshTaskID == taskID {
                refreshTask = nil
                refreshTaskID = nil
                refreshTokenBeingUsed = nil
            }
            return value
        } catch {
            if refreshTaskID == taskID {
                refreshTask = nil
                refreshTaskID = nil
                refreshTokenBeingUsed = nil
            }
            throw error
        }
    }

    private func performRefresh(refreshToken: String, binding: SessionBinding) async throws -> SupabaseSession {
        try validate(binding)
        let body = RefreshRequest(refreshToken: refreshToken)
        let request = try makeRequest(
            path: "auth/v1/token",
            queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            method: "POST",
            body: body,
            authenticatedBy: nil
        )
        let result = try await perform(request)
        try validate(binding)

        guard (200..<300).contains(result.statusCode) else {
            if result.statusCode == 401 || Self.isRefreshTokenExpired(result.data) {
                sessionIsExpired = true
                stopRealtime()
                throw SupabaseClientError.sessionExpired
            }
            try requireSuccess(result, context: .refresh)
            throw SupabaseClientError.httpStatus(result.statusCode)
        }

        let decoded = try decodeAuthToken(result.data)
        let refreshed = try makeSession(from: decoded, fallbackEmail: currentEmail(for: binding), existingSession: session)
        guard refreshed.userID == binding.userID else { throw SupabaseClientError.sessionExpired }
        try validate(binding)
        do {
            try sessionStore.save(refreshed)
        } catch {
            throw SupabaseClientError.keychainUnavailable
        }
        let previousToken = session?.accessToken
        session = refreshed
        sessionIsExpired = false

        if previousToken != refreshed.accessToken, realtimeWanted {
            restartRealtimeAfterTokenChange()
        }
        return refreshed
    }

    private func currentEmail(for binding: SessionBinding) -> String {
        guard let current = session, current.userID == binding.userID else { return "" }
        return current.email
    }

    private func makeSession(
        from response: AuthTokenResponse,
        fallbackEmail: String,
        existingSession: SupabaseSession?
    ) throws -> SupabaseSession {
        let userID = response.user?.id ?? existingSession?.userID ?? ""
        guard !userID.isEmpty,
              let accessToken = response.accessToken, !accessToken.isEmpty,
              let refreshToken = response.refreshToken, !refreshToken.isEmpty else {
            throw SupabaseClientError.invalidResponse
        }

        let email = response.user?.email ?? existingSession?.email ?? fallbackEmail
        let expiresAt: Date
        if let epoch = response.expiresAt {
            expiresAt = Date(timeIntervalSince1970: epoch)
        } else if let expiresIn = response.expiresIn {
            expiresAt = Date().addingTimeInterval(expiresIn)
        } else {
            throw SupabaseClientError.invalidResponse
        }

        return SupabaseSession(
            userID: userID,
            email: email,
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt
        )
    }

    private func decodeAuthToken(_ data: Data) throws -> AuthTokenResponse {
        do {
            return try JSONDecoder().decode(AuthTokenResponse.self, from: data)
        } catch {
            throw SupabaseClientError.invalidResponse
        }
    }

    private func returnedRevision(from data: Data) throws -> Int64 {
        let rows: [ArchiveRevisionRow]
        do {
            rows = try JSONDecoder().decode([ArchiveRevisionRow].self, from: data)
        } catch {
            throw SupabaseClientError.invalidResponse
        }
        guard rows.count == 1, rows[0].revision > 0 else {
            if rows.isEmpty { throw SupabaseClientError.conflict }
            throw SupabaseClientError.invalidResponse
        }
        return rows[0].revision
    }

    private func requireSuccess(_ result: HTTPResult, context: RequestContext) throws {
        guard (200..<300).contains(result.statusCode) else {
            throw httpError(status: result.statusCode, data: result.data, context: context)
        }
    }

    private func httpError(status: Int, data: Data, context: RequestContext) -> SupabaseClientError {
        let fields = Self.errorFields(in: data)
        let code = (fields["code"] ?? fields["error_code"] ?? fields["error"] ?? "").lowercased()

        if context == .archiveInsert, status == 409 || code.contains("23505") || code.contains("unique") {
            return .conflict
        }
        if context == .archive, status == 409 {
            return .conflict
        }
        if context == .deleteAccount,
           status == 404 || code.contains("pgrst202") || code.contains("42883") || code.contains("function") {
            return .deleteAccountNotReady
        }
        if context == .verifyCode, status == 400 || status == 422 {
            return .invalidCode
        }
        if status == 429 {
            return .rateLimited
        }
        if status == 401 {
            return .sessionExpired
        }
        return .httpStatus(status)
    }

    private static func errorFields(in data: Data) -> [String: String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var fields: [String: String] = [:]
        for key in ["code", "error_code", "error", "message", "msg"] {
            if let value = object[key] as? String {
                fields[key] = value
            }
        }
        return fields
    }

    private static func isRefreshTokenExpired(_ data: Data) -> Bool {
        let fields = errorFields(in: data)
        let description = ["code", "error_code", "error", "message", "msg"]
            .compactMap { fields[$0] }
            .joined(separator: " ")
            .lowercased()
        return description.contains("refresh_token_not_found")
            || description.contains("refresh token not found")
            || description.contains("invalid refresh token")
            || description.contains("invalid_grant")
            || description.contains("refresh_token_already_used")
            || description.contains("session_not_found")
    }

    private func makeRequest<Body: Encodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: String,
        body: Body?,
        authenticatedBy accessToken: String?,
        extraHeaders: [String: String] = [:]
    ) throws -> URLRequest {
        try requireConfiguration()
        guard let baseURL = configuration.url else { throw SupabaseClientError.notConfigured }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let basePath = (components?.path ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components?.path = "/" + [basePath, normalizedPath].filter { !$0.isEmpty }.joined(separator: "/")
        components?.query = nil
        components?.fragment = nil
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else { throw SupabaseClientError.notConfigured }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                request.httpBody = try JSONEncoder().encode(body)
            } catch {
                throw SupabaseClientError.invalidResponse
            }
        }
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        for (name, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> HTTPResult {
        let requestID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HTTPResult, Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: SupabaseClientError.requestCancelled)
                    return
                }

                let task = urlSession.dataTask(with: request) { [weak self] data, response, error in
                    Task { @MainActor [weak self] in
                        guard let self else {
                            continuation.resume(throwing: SupabaseClientError.requestCancelled)
                            return
                        }
                        self.activeRequests.removeValue(forKey: requestID)

                        if let error = error as NSError? {
                            if error.code == NSURLErrorCancelled {
                                continuation.resume(throwing: SupabaseClientError.requestCancelled)
                            } else {
                                continuation.resume(throwing: SupabaseClientError.transportUnavailable)
                            }
                            return
                        }
                        guard let response = response as? HTTPURLResponse else {
                            continuation.resume(throwing: SupabaseClientError.invalidResponse)
                            return
                        }
                        continuation.resume(returning: HTTPResult(statusCode: response.statusCode, data: data ?? Data()))
                    }
                }
                activeRequests[requestID] = task
                task.resume()
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                self?.activeRequests[requestID]?.cancel()
            }
        }
    }

    private func requireConfiguration() throws {
        guard let url = configuration.url else { throw SupabaseClientError.notConfigured }
        guard url.scheme?.lowercased() == "https" else {
            throw SupabaseClientError.insecureEndpoint
        }
        guard configuration.isConfigured else { throw SupabaseClientError.notConfigured }
    }

    private func validate(_ binding: SessionBinding) throws {
        guard generation == binding.generation,
              session?.userID == binding.userID,
              !authenticationTransitionInProgress else {
            throw SupabaseClientError.operationSuperseded
        }
        guard !sessionIsExpired else { throw SupabaseClientError.sessionExpired }
    }

    private func invalidateAccountWork(stopRealtime shouldStopRealtime: Bool) {
        generation &+= 1
        for task in activeRequests.values {
            task.cancel()
        }
        activeRequests.removeAll()
        refreshTask?.cancel()
        refreshTask = nil
        refreshTaskID = nil
        refreshTokenBeingUsed = nil
        if shouldStopRealtime {
            stopRealtime()
        }
    }

    private static func looksLikeEmail(_ email: String) -> Bool {
        guard let at = email.firstIndex(of: "@"),
              at != email.startIndex,
              email[at...].contains("."),
              !email.hasSuffix(".") else {
            return false
        }
        return !email.contains(where: { $0.isWhitespace })
    }

    private static func nextRevision(after expectedRevision: Int64?) throws -> Int64 {
        let now = Int64(Date().timeIntervalSince1970 * 1_000)
        guard let expectedRevision else { return max(1, now) }
        let (next, overflow) = expectedRevision.addingReportingOverflow(1)
        guard !overflow else { throw SupabaseClientError.invalidResponse }
        return max(now, next)
    }

    private func connectRealtime(generation expectedGeneration: Int) async {
        guard realtimeWanted, realtimeGeneration == expectedGeneration,
              let currentSession = session,
              !sessionIsExpired,
              !authenticationTransitionInProgress else {
            return
        }
        guard let baseURL = configuration.url,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            scheduleRealtimeReconnect(for: expectedGeneration)
            return
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, "realtime/v1/websocket"].filter { !$0.isEmpty }.joined(separator: "/")
        components.scheme = "wss"
        components.queryItems = [
            URLQueryItem(name: "apikey", value: configuration.anonKey),
            URLQueryItem(name: "vsn", value: "2.0.0")
        ]
        components.fragment = nil
        guard let socketURL = components.url else {
            scheduleRealtimeReconnect(for: expectedGeneration)
            return
        }

        let socket = webSocketSession.webSocketTask(with: socketURL)
        let topic = "realtime:public:mikanseta_archives"
        let joinReference = UUID().uuidString
        realtimeSocket = socket
        realtimeTopic = topic
        realtimeJoinReference = joinReference
        realtimeSubscriptionIDs = []
        realtimeJoined = false
        realtimeHeartbeatReference = nil
        socket.resume()
        scheduleRealtimeJoinTimeout(on: socket, generation: expectedGeneration)

        let joinPayload: [String: Any] = [
            "config": [
                "broadcast": ["ack": false, "self": false],
                "presence": ["key": ""],
                "postgres_changes": [[
                    "event": "*",
                    "schema": "public",
                    "table": "mikanseta_archives",
                    "filter": "user_id=eq.\(currentSession.userID)"
                ]],
                "private": false
            ],
            "access_token": currentSession.accessToken
        ]

        do {
            let frame = try realtimeFrame(
                joinReference: joinReference,
                reference: joinReference,
                topic: topic,
                event: "phx_join",
                payload: joinPayload
            )
            try await socket.send(.string(frame))
        } catch {
            guard realtimeWanted,
                  realtimeGeneration == expectedGeneration,
                  realtimeSocket === socket else {
                return
            }
            retireRealtimeSocket(socket)
            scheduleRealtimeReconnect(for: expectedGeneration)
            return
        }

        guard realtimeWanted,
              realtimeGeneration == expectedGeneration,
              realtimeSocket === socket else {
            socket.cancel(with: .goingAway, reason: nil)
            return
        }

        realtimeReceiveTask = Task { @MainActor [weak self] in
            await self?.receiveRealtimeMessages(from: socket, generation: expectedGeneration)
        }
        realtimeHeartbeatTask = Task { @MainActor [weak self] in
            await self?.sendRealtimeHeartbeats(on: socket, generation: expectedGeneration)
        }
        scheduleRealtimeTokenRefresh(for: currentSession, generation: expectedGeneration)
    }

    private func receiveRealtimeMessages(from socket: URLSessionWebSocketTask, generation expectedGeneration: Int) async {
        do {
            while !Task.isCancelled {
                let message = try await socket.receive()
                guard realtimeWanted,
                      realtimeGeneration == expectedGeneration,
                      realtimeSocket === socket else {
                    return
                }
                if case .string(let text) = message {
                    handleRealtimeFrame(text, generation: expectedGeneration, socket: socket)
                }
            }
        } catch {
            guard realtimeWanted,
                  realtimeGeneration == expectedGeneration,
                  realtimeSocket === socket else {
                return
            }
            retireRealtimeSocket(socket)
            scheduleRealtimeReconnect(for: expectedGeneration)
        }
    }

    private func handleRealtimeFrame(_ text: String, generation expectedGeneration: Int, socket: URLSessionWebSocketTask) {
        guard realtimeWanted,
              realtimeGeneration == expectedGeneration,
              realtimeSocket === socket,
              let data = text.data(using: .utf8),
              let frame = try? JSONSerialization.jsonObject(with: data) as? [Any],
              frame.count == 5,
              let event = frame[3] as? String,
              let payload = frame[4] as? [String: Any] else {
            return
        }

        let topic = frame[2] as? String ?? ""
        let reference = frame[1] as? String

        if event == "phx_error" || event == "phx_close" {
            guard topic == realtimeTopic || topic == "phoenix" else { return }
            retireRealtimeSocket(socket)
            scheduleRealtimeReconnect(for: expectedGeneration)
            return
        }

        if event == "phx_reply" {
            if topic == realtimeTopic, reference == realtimeJoinReference {
                let status = payload["status"] as? String
                guard status == "ok",
                      let response = payload["response"] as? [String: Any],
                      let changes = response["postgres_changes"] as? [[String: Any]] else {
                    retireRealtimeSocket(socket)
                    scheduleRealtimeReconnect(for: expectedGeneration)
                    return
                }
                let ids = Set(changes.compactMap { Self.stringID($0["id"]) })
                guard !ids.isEmpty else {
                    retireRealtimeSocket(socket)
                    scheduleRealtimeReconnect(for: expectedGeneration)
                    return
                }
                realtimeJoinTimeoutTask?.cancel()
                realtimeJoinTimeoutTask = nil
                realtimeSubscriptionIDs = ids
                realtimeJoined = true
                realtimeReconnectAttempts = 0
                return
            }

            if topic == "phoenix", reference == realtimeHeartbeatReference {
                guard payload["status"] as? String == "ok" else {
                    retireRealtimeSocket(socket)
                    scheduleRealtimeReconnect(for: expectedGeneration)
                    return
                }
                realtimeHeartbeatTimeoutTask?.cancel()
                realtimeHeartbeatTimeoutTask = nil
                realtimeHeartbeatReference = nil
            }
            return
        }

        guard event == "postgres_changes",
              topic == realtimeTopic,
              realtimeJoined,
              let incomingIDs = payload["ids"] as? [Any] else {
            return
        }
        let matches = incomingIDs.contains { id in
            guard let identifier = Self.stringID(id) else { return false }
            return realtimeSubscriptionIDs.contains(identifier)
        }
        guard matches else { return }
        realtimeCallback?()
    }

    private func sendRealtimeHeartbeats(on socket: URLSessionWebSocketTask, generation expectedGeneration: Int) async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: 25_000_000_000)
            } catch {
                return
            }
            guard realtimeWanted,
                  realtimeGeneration == expectedGeneration,
                  realtimeSocket === socket else {
                return
            }
            guard realtimeHeartbeatReference == nil else {
                retireRealtimeSocket(socket)
                scheduleRealtimeReconnect(for: expectedGeneration)
                return
            }

            let reference = UUID().uuidString
            realtimeHeartbeatReference = reference
            do {
                let frame = try realtimeFrame(
                    joinReference: nil,
                    reference: reference,
                    topic: "phoenix",
                    event: "heartbeat",
                    payload: [:]
                )
                scheduleRealtimeHeartbeatTimeout(
                    reference: reference,
                    on: socket,
                    generation: expectedGeneration
                )
                try await socket.send(.string(frame))
            } catch {
                guard realtimeWanted,
                      realtimeGeneration == expectedGeneration,
                      realtimeSocket === socket else {
                    return
                }
                retireRealtimeSocket(socket)
                scheduleRealtimeReconnect(for: expectedGeneration)
                return
            }

            guard realtimeWanted,
                  realtimeGeneration == expectedGeneration,
                  realtimeSocket === socket else {
                return
            }
        }
    }

    private func scheduleRealtimeJoinTimeout(on socket: URLSessionWebSocketTask, generation expectedGeneration: Int) {
        realtimeJoinTimeoutTask?.cancel()
        realtimeJoinTimeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 10_000_000_000)
            } catch {
                return
            }
            guard let self,
                  self.realtimeWanted,
                  self.realtimeGeneration == expectedGeneration,
                  self.realtimeSocket === socket,
                  !self.realtimeJoined else {
                return
            }
            self.retireRealtimeSocket(socket)
            self.scheduleRealtimeReconnect(for: expectedGeneration)
        }
    }

    private func scheduleRealtimeHeartbeatTimeout(
        reference: String,
        on socket: URLSessionWebSocketTask,
        generation expectedGeneration: Int
    ) {
        realtimeHeartbeatTimeoutTask?.cancel()
        realtimeHeartbeatTimeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 10_000_000_000)
            } catch {
                return
            }
            guard let self,
                  self.realtimeWanted,
                  self.realtimeGeneration == expectedGeneration,
                  self.realtimeSocket === socket,
                  self.realtimeHeartbeatReference == reference else {
                return
            }
            self.retireRealtimeSocket(socket)
            self.scheduleRealtimeReconnect(for: expectedGeneration)
        }
    }

    private func scheduleRealtimeReconnect(for expectedGeneration: Int, immediately: Bool = false) {
        guard realtimeWanted,
              realtimeGeneration == expectedGeneration,
              realtimeReconnectTask == nil else {
            return
        }
        let attempt = realtimeReconnectAttempts
        realtimeReconnectAttempts += 1
        let delaySeconds = immediately ? 0 : min(30, 1 << min(attempt, 5))

        realtimeReconnectTask = Task { @MainActor [weak self] in
            if delaySeconds > 0 {
                do {
                    try await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)
                } catch {
                    return
                }
            }
            guard let self,
                  self.realtimeWanted,
                  self.realtimeGeneration == expectedGeneration else {
                return
            }
            self.realtimeReconnectTask = nil
            await self.connectRealtime(generation: expectedGeneration)
        }
    }

    private func scheduleRealtimeTokenRefresh(for currentSession: SupabaseSession, generation expectedGeneration: Int) {
        realtimeTokenRefreshTask?.cancel()
        let timeUntilRefresh = min(86_400, max(1, currentSession.expiresAt.timeIntervalSinceNow - 60))
        realtimeTokenRefreshTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(timeUntilRefresh * 1_000_000_000))
            } catch {
                return
            }
            guard let self,
                  self.realtimeWanted,
                  self.realtimeGeneration == expectedGeneration,
                  let active = self.session,
                  active.userID == currentSession.userID else {
                return
            }
            let binding = SessionBinding(generation: self.generation, userID: active.userID)
            do {
                _ = try await self.refreshSession(for: binding, failedAccessToken: active.accessToken)
            } catch SupabaseClientError.sessionExpired {
                self.stopRealtime()
            } catch {
                guard self.realtimeWanted, self.realtimeGeneration == expectedGeneration else { return }
                self.scheduleRealtimeTokenRefreshRetry(for: active, generation: expectedGeneration)
            }
        }
    }

    private func scheduleRealtimeTokenRefreshRetry(for currentSession: SupabaseSession, generation expectedGeneration: Int) {
        realtimeTokenRefreshTask?.cancel()
        realtimeTokenRefreshTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 15_000_000_000)
            } catch {
                return
            }
            guard let self,
                  self.realtimeWanted,
                  self.realtimeGeneration == expectedGeneration,
                  let active = self.session,
                  active.userID == currentSession.userID else {
                return
            }
            let binding = SessionBinding(generation: self.generation, userID: active.userID)
            do {
                _ = try await self.refreshSession(for: binding, failedAccessToken: active.accessToken)
            } catch SupabaseClientError.sessionExpired {
                self.stopRealtime()
            } catch {
                self.scheduleRealtimeTokenRefreshRetry(for: active, generation: expectedGeneration)
            }
        }
    }

    private func restartRealtimeAfterTokenChange() {
        guard realtimeWanted else { return }
        realtimeGeneration &+= 1
        cancelRealtimeConnection()
        realtimeReconnectAttempts = 0
        scheduleRealtimeReconnect(for: realtimeGeneration, immediately: true)
    }

    private func retireRealtimeSocket(_ socket: URLSessionWebSocketTask) {
        guard realtimeSocket === socket else { return }
        realtimeSocket = nil
        realtimeJoined = false
        realtimeSubscriptionIDs = []
        realtimeJoinTimeoutTask?.cancel()
        realtimeJoinTimeoutTask = nil
        realtimeHeartbeatTimeoutTask?.cancel()
        realtimeHeartbeatTimeoutTask = nil
        realtimeHeartbeatReference = nil
        realtimeReceiveTask?.cancel()
        realtimeReceiveTask = nil
        realtimeHeartbeatTask?.cancel()
        realtimeHeartbeatTask = nil
        realtimeTokenRefreshTask?.cancel()
        realtimeTokenRefreshTask = nil
        socket.cancel(with: .goingAway, reason: nil)
    }

    private func cancelRealtimeConnection() {
        realtimeReceiveTask?.cancel()
        realtimeReceiveTask = nil
        realtimeHeartbeatTask?.cancel()
        realtimeHeartbeatTask = nil
        realtimeJoinTimeoutTask?.cancel()
        realtimeJoinTimeoutTask = nil
        realtimeHeartbeatTimeoutTask?.cancel()
        realtimeHeartbeatTimeoutTask = nil
        realtimeHeartbeatReference = nil
        realtimeReconnectTask?.cancel()
        realtimeReconnectTask = nil
        realtimeTokenRefreshTask?.cancel()
        realtimeTokenRefreshTask = nil
        realtimeSocket?.cancel(with: .goingAway, reason: nil)
        realtimeSocket = nil
        realtimeTopic = nil
        realtimeJoinReference = nil
        realtimeSubscriptionIDs = []
        realtimeJoined = false
    }

    private func realtimeFrame(
        joinReference: String?,
        reference: String,
        topic: String,
        event: String,
        payload: [String: Any]
    ) throws -> String {
        let frame: [Any] = [joinReference.map { $0 as Any } ?? NSNull(), reference, topic, event, payload]
        do {
            let data = try JSONSerialization.data(withJSONObject: frame, options: [.fragmentsAllowed])
            guard let value = String(data: data, encoding: .utf8) else {
                throw SupabaseClientError.invalidResponse
            }
            return value
        } catch {
            throw SupabaseClientError.invalidResponse
        }
    }

    private static func stringID(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private struct SessionBinding {
        let generation: Int
        let userID: String
    }

    private struct HTTPResult {
        let statusCode: Int
        let data: Data
    }

    private enum RequestContext: Equatable {
        case generic
        case sendCode
        case verifyCode
        case refresh
        case archive
        case archiveInsert
        case deleteAccount
    }

    private struct OTPRequest: Encodable {
        let email: String
        let createUser: Bool

        enum CodingKeys: String, CodingKey {
            case email
            case createUser = "create_user"
        }
    }

    private struct VerifyOTPRequest: Encodable {
        let email: String
        let token: String
        let type: String
    }

    private struct RefreshRequest: Encodable {
        let refreshToken: String

        enum CodingKeys: String, CodingKey {
            case refreshToken = "refresh_token"
        }
    }

    private struct EmptyRequestBody: Encodable {}

    private struct ArchiveWrite: Encodable {
        let userID: String
        let revision: Int64
        let updatedAt: String
        let content: String

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case revision
            case updatedAt = "updated_at"
            case content
        }
    }

    private struct ArchiveRow: Decodable {
        let revision: Int64
        let content: String
    }

    private struct ArchiveRevisionRow: Decodable {
        let revision: Int64
    }

    private struct AuthTokenResponse: Decodable {
        let accessToken: String?
        let refreshToken: String?
        let expiresIn: TimeInterval?
        let expiresAt: TimeInterval?
        let user: AuthUser?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case expiresAt = "expires_at"
            case user
        }
    }

    private struct AuthUser: Decodable {
        let id: String
        let email: String?
    }
}

private struct SupabaseSessionEnvelope: Codable {
    let projectIdentity: String
    let bundleIdentifier: String
    let session: SupabaseSession
}

private struct SupabaseSessionStore {
    private let service: String
    private let account: String
    private let projectIdentity: String
    private let bundleIdentifier: String

    init(configuration: SupabaseConfiguration, bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier
        self.projectIdentity = configuration.url.map {
            "\($0.scheme?.lowercased() ?? "")://\($0.host?.lowercased() ?? ""):\($0.port.map { String($0) } ?? "")\($0.path)"
        } ?? "unconfigured"
        self.service = "com.mikansei.supabase.session.v1.\(bundleIdentifier).\(projectIdentity)"
        self.account = "\(bundleIdentifier)|\(projectIdentity)"
    }

    func load() throws -> SupabaseSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data else {
            throw SupabaseClientError.keychainUnavailable
        }

        let envelope: SupabaseSessionEnvelope
        do {
            envelope = try JSONDecoder().decode(SupabaseSessionEnvelope.self, from: data)
        } catch {
            try? delete()
            return nil
        }
        guard envelope.projectIdentity == projectIdentity,
              envelope.bundleIdentifier == bundleIdentifier else {
            try? delete()
            return nil
        }
        return envelope.session
    }

    func save(_ session: SupabaseSession) throws {
        let envelope = SupabaseSessionEnvelope(
            projectIdentity: projectIdentity,
            bundleIdentifier: bundleIdentifier,
            session: session
        )
        let data: Data
        do {
            data = try JSONEncoder().encode(envelope)
        } catch {
            throw SupabaseClientError.keychainUnavailable
        }

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw SupabaseClientError.keychainUnavailable
        }

        var addQuery = baseQuery
        for (key, value) in attributes {
            addQuery[key] = value
        }
        guard SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess else {
            throw SupabaseClientError.keychainUnavailable
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SupabaseClientError.keychainCouldNotClear
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
