import Foundation
import Supabase
import AuthenticationServices
import CryptoKit

enum SignUpResult {
    case verificationRequired(email: String)
    case signedIn
}

@MainActor
final class SupabaseManager: ObservableObject {
    static let shared = SupabaseManager()

    let client = SupabaseClient(
        supabaseURL: URL(string: "https://glbhvockgnfnuisqydgy.supabase.co")!,
        supabaseKey: "sb_publishable_5nyexPefOq1LCY8Hm6ycoA_pv9Yk20m"
    )

    @Published var session: Session?
    @Published var isLoading = false
    @Published var authError: String?

    private var pendingRawNonce: String?

    private init() {}

    func restoreSession() async {
        do {
            session = try await client.auth.session
        } catch {
            session = nil
        }
    }

    /// Call from SignInWithAppleButton.onRequest — stores the raw nonce and returns the hashed one for Apple.
    func prepareSignIn() -> String {
        let raw = randomNonceString()
        pendingRawNonce = raw
        return sha256(raw)
    }

    /// Call from SignInWithAppleButton.onCompletion.
    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) async {
        isLoading = true
        authError = nil
        defer { isLoading = false }

        do {
            let authorization = try result.get()
            guard
                let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = appleCredential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                let rawNonce = pendingRawNonce
            else {
                authError = "Invalid Apple credential received."
                return
            }
            pendingRawNonce = nil

            session = try await client.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken, nonce: rawNonce)
            )

            await performPostAuthSync()
        } catch {
            // Apple SDK errors are user-safe; bypass friendlyAuthMessage
            authError = error.localizedDescription
        }
    }

    func signOut() async {
        isLoading = true
        authError = nil
        defer { isLoading = false }
        do {
            try await client.auth.signOut()
            session = nil
        } catch {
            authError = error.localizedDescription
        }
    }

    // MARK: - Email Auth

    @discardableResult
    func signUpWithEmail(_ email: String, password: String) async -> SignUpResult {
        guard !isLoading else { return .verificationRequired(email: email) }
        isLoading = true
        authError = nil
        defer { isLoading = false }

        do {
            let response = try await client.auth.signUp(
                email: email,
                password: password,
                redirectTo: URL(string: "boop://auth/callback")
            )
            if let newSession = response.session {
                // Email confirmation disabled at project level (defensive path)
                session = newSession
                print("[Supabase] signUpWithEmail result: signedIn")
                await performPostAuthSync()
                return .signedIn
            } else {
                print("[Supabase] signUpWithEmail result: verificationRequired")
                return .verificationRequired(email: email)
            }
        } catch {
            // Surface only network/transport errors; account-state errors swallowed (anti-enum)
            if error is URLError {
                authError = "Network error — please try again."
            }
            return .verificationRequired(email: email)
        }
    }

    func signInWithEmail(_ email: String, password: String) async {
        guard !isLoading else { return }
        isLoading = true
        authError = nil
        defer { isLoading = false }

        do {
            session = try await client.auth.signIn(email: email, password: password)
            print("[Supabase] signInWithEmail — outcome: success")
            await performPostAuthSync()
        } catch {
            print("[Supabase] signInWithEmail — outcome: failed")
            authError = friendlyAuthMessage(error)
        }
    }

    func sendPasswordReset(for email: String) async {
        guard !isLoading else { return }
        isLoading = true
        authError = nil
        defer { isLoading = false }

        do {
            try await client.auth.resetPasswordForEmail(
                email,
                redirectTo: URL(string: "boop://auth/callback")
            )
        } catch {
            // Swallow silently — anti-enumeration; view always shows confirmation
        }
        print("[Supabase] sendPasswordReset — sent")
    }

    func syncProfile(_ contact: Contact) async {
        guard let userId = session?.user.id else { return }
        print("[Supabase] syncProfile — userId: \(userId), avatarBytes: \(contact.avatarData?.count ?? 0)")

        var avatarURL: String? = nil
        if let avatarData = contact.avatarData {
            avatarURL = await uploadAvatar(data: avatarData, userId: userId)
            print("[Supabase] avatar upload result: \(avatarURL ?? "nil")")
        } else {
            print("[Supabase] no avatarData on contact — skipping upload")
        }

        struct ProfileRow: Encodable {
            let id: UUID
            let ble_device_uuid: UUID?
            let name: String
            let birthday: String?
            let bio: String?
            let avatar_url: String?
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        let bleUUIDString = UserDefaults.standard.string(forKey: UserDefaultsKeys.localDeviceUUID)
        let bleUUID = bleUUIDString.flatMap { UUID(uuidString: $0) }

        let row = ProfileRow(
            id: userId,
            ble_device_uuid: bleUUID,
            name: contact.displayName,
            birthday: contact.birthday.map { formatter.string(from: $0) },
            bio: contact.bio,
            avatar_url: avatarURL
        )

        do {
            try await client.from("profiles").upsert(row).execute()
        } catch {
            authError = error.localizedDescription
        }
    }

    /// Records a boop connection to Supabase. Call after a boop event with the contact's BLE device UUID.
    /// Requires the contact to have previously synced their profile (so their ble_device_uuid is on file).
    func recordBoopConnection(withBLEDeviceUUID bleUUID: UUID, lastBoopedAt: Date = Date()) async {
        guard let myUserId = session?.user.id else { return }

        struct ProfileLookup: Decodable {
            let id: UUID
        }
        struct Connection: Encodable {
            let participants: [UUID]
            let last_seen: String
        }

        let iso = ISO8601DateFormatter()

        do {
            let results: [ProfileLookup] = try await client
                .from("profiles")
                .select("id")
                .eq("ble_device_uuid", value: bleUUID.uuidString)
                .limit(1)
                .execute()
                .value

            guard let contactUserId = results.first?.id else {
                print("[Supabase] recordBoopConnection — no profile found for BLE UUID \(bleUUID.uuidString.prefix(8)), skipping")
                return
            }

            // Sort UUIDs so the array is order-independent — extends naturally to N participants
            let participants = [myUserId, contactUserId].sorted { $0.uuidString < $1.uuidString }

            try await client.from("boop_connections")
                .upsert(
                    Connection(
                        participants: participants,
                        last_seen: iso.string(from: lastBoopedAt)
                    ),
                    onConflict: "participants"
                )
                .execute()
            print("[Supabase] recordBoopConnection — upserted connection with \(contactUserId.uuidString.prefix(8))")
        } catch {
            print("[Supabase] recordBoopConnection — error: \(error)")
        }
    }

    /// Syncs all locally stored boop contacts to Supabase boop_connections and fetches their avatars.
    /// Call on login so existing offline boops are reflected in the remote table.
    func syncAllBoopConnections() async {
        guard session?.user.id != nil else { return }

        let ownUUID = UserDefaults.standard.string(forKey: UserDefaultsKeys.localDeviceUUID)
            .flatMap { UUID(uuidString: $0) }

        let contacts = ContactRepository.shared.fetchAllContacts()

        for contact in contacts {
            // Skip the user's own profile
            if let ownUUID, contact.uuid == ownUUID { continue }

            let latestTimestamp = contact.interactions
                .compactMap { $0.timestamp as Date? }
                .max() ?? Date()

            await recordBoopConnection(withBLEDeviceUUID: contact.uuid, lastBoopedAt: latestTimestamp)
            await fetchAndSaveAvatar(forBLEDeviceUUID: contact.uuid, into: contact)
        }
    }

    /// Downloads a contact's avatar from Supabase and saves it to the local Contact record.
    func fetchAndSaveAvatar(forBLEDeviceUUID bleUUID: UUID, into contact: Contact) async {
        struct ProfileAvatarLookup: Decodable {
            let avatar_url: String?
        }

        do {
            let results: [ProfileAvatarLookup] = try await client
                .from("profiles")
                .select("avatar_url")
                .eq("ble_device_uuid", value: bleUUID.uuidString)
                .limit(1)
                .execute()
                .value

            guard let urlString = results.first?.avatar_url,
                  let avatarURL = URL(string: urlString) else { return }

            let (data, _) = try await URLSession.shared.data(from: avatarURL)
            contact.avatarData = data
        } catch {
            // Best-effort — non-fatal
        }
    }

    func handleDeepLink(_ url: URL) async {
        do {
            session = try await client.auth.session(from: url)
            await performPostAuthSync()
        } catch {
            authError = friendlyAuthMessage(error)
        }
    }

    // MARK: - Private

    private func performPostAuthSync() async {
        if let contact = ContactRepository.shared.getOwnProfile() {
            await syncProfile(contact)
        } else {
            print("[Supabase] performPostAuthSync — getOwnProfile returned nil")
        }
        await syncAllBoopConnections()
    }

    private func friendlyAuthMessage(_ error: Error) -> String {
        if let authError = error as? AuthError {
            switch authError.errorCode {
            case .emailNotConfirmed:
                return "Please verify your email — check your inbox."
            case .invalidCredentials, .userNotFound:
                return "Email or password is incorrect."
            case .weakPassword:
                return "Password is too weak. Please use at least 8 characters."
            case .overRequestRateLimit, .overEmailSendRateLimit:
                return "Too many attempts — please wait a moment and try again."
            default:
                break
            }
        }
        if error is URLError {
            return "Network error — please try again."
        }
        return "Something went wrong. Please try again."
    }

    private func uploadAvatar(data: Data, userId: UUID) async -> String? {
        let path = "\(userId.uuidString.lowercased())/avatar.jpg"
        do {
            _ = try await client.storage
                .from("avatars")
                .upload(path: path, file: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
            // Private bucket — use a signed URL (1 year expiry) instead of a public URL
            let url = try await client.storage
                .from("avatars")
                .createSignedURL(path: path, expiresIn: 31_536_000)
            return url.absoluteString
        } catch {
            print("[Supabase] avatar upload error: \(error)")
            authError = "Avatar upload failed: \(error.localizedDescription)"
            return nil
        }
    }

    private func randomNonceString(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            for random in randoms {
                guard remaining > 0 else { break }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()
    }
}
