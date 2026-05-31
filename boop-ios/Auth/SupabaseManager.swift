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
    @Published var isSessionLoading = true
    @Published var hasProfile: Bool = false

    private var pendingRawNonce: String?

    private init() {}

    /// Validates the session server-side and hydrates local caches from Supabase.
    /// This is the single call needed at app startup — no separate performPostAuthSync needed.
    func restoreSession() async {
        do {
            // Refresh validates the session server-side and rotates tokens.
            session = try await client.auth.refreshSession()
        } catch let error as AuthError {
            // Session is genuinely invalid (revoked, expired refresh token) — force re-login.
            print("[Auth] Session invalid, clearing: \(error)")
            session = nil
            hasProfile = false
            return
        } catch {
            // Network error — fall back to the locally cached session.
            print("[Auth] Network error during session refresh, using cached session: \(error)")
            do {
                session = try await client.auth.session
            } catch {
                session = nil
                hasProfile = false
                return
            }
        }
        // Session is valid — hydrate local caches fresh from Supabase.
        await performPostAuthSync()
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

            isSessionLoading = true
            await performPostAuthSync()
            isSessionLoading = false
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
            hasProfile = false
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
                isSessionLoading = true
                await performPostAuthSync()
                isSessionLoading = false
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
            isSessionLoading = true
            await performPostAuthSync()
            isSessionLoading = false
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
        guard let userId = session?.user.id else {
            print("[Supabase] syncProfile — skipped, no session")
            return
        }
        print("[Supabase] syncProfile — userId: \(userId), name: \(contact.displayName), avatarBytes: \(contact.avatarData?.count ?? 0)")

        var avatarURL: String? = nil
        if let avatarData = contact.avatarData {
            avatarURL = await uploadAvatar(data: avatarData, userId: userId)
            print("[Supabase] avatar upload result: \(avatarURL ?? "nil")")
        } else {
            print("[Supabase] no avatarData on contact — skipping upload")
        }

        struct ProfileRow: Encodable {
            let id: UUID
            let display_name: String
            let birthday: String?
            let bio: String?
            let avatar_url: String?
            let gradient_colors: [String]
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        let row = ProfileRow(
            id: userId,
            display_name: contact.displayName,
            birthday: contact.birthday.map { formatter.string(from: $0) },
            bio: contact.bio,
            avatar_url: avatarURL,
            gradient_colors: contact.gradientColorsData
        )

        do {
            try await client.from("profiles").upsert(row).execute()
            print("[Supabase] syncProfile — upsert succeeded for \(userId.uuidString.prefix(8))")
        } catch {
            print("[Supabase] syncProfile — upsert FAILED: \(error)")
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

            try await client.from("boop_interactions")
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

    /// Syncs all locally stored boop contacts to Supabase boop_interactions and fetches their avatars.
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

    /// Fetches all boop connections from Supabase and restores the corresponding Contact records locally.
    /// Call on login to recover contacts after reinstall or on a new device.
    func restoreContacts() async {
        guard let userId = session?.user.id else { return }

        struct ConnectionRow: Decodable {
            let participants: [UUID]
        }
        struct RemoteContact: Decodable {
            let ble_device_uuid: UUID?
            let display_name: String
            let birthday: String?
            let bio: String?
            let avatar_url: String?
        }

        do {
            let connections: [ConnectionRow] = try await client
                .from("boop_interactions")
                .select("participants")
                .filter("participants", operator: "cs", value: "{\(userId.uuidString.lowercased())}")
                .execute()
                .value

            var restoredCount = 0
            for connection in connections {
                guard let otherUserId = connection.participants.first(where: { $0 != userId }) else { continue }

                let profiles: [RemoteContact] = try await client
                    .from("profiles")
                    .select("ble_device_uuid, display_name, birthday, bio, avatar_url")
                    .eq("id", value: otherUserId.uuidString)
                    .limit(1)
                    .execute()
                    .value

                guard let profile = profiles.first, let bleUUID = profile.ble_device_uuid else { continue }

                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withFullDate]
                let birthday = profile.birthday.flatMap { formatter.date(from: $0) }

                guard let contact = ContactRepository.shared.findOrCreate(
                    uuid: bleUUID,
                    displayName: profile.display_name,
                    birthday: birthday,
                    bio: profile.bio,
                    gradientColors: []
                ) else { continue }

                if let urlString = profile.avatar_url, let url = URL(string: urlString) {
                    contact.avatarData = try? await URLSession.shared.data(from: url).0
                }
                restoredCount += 1
            }
            print("[Supabase] restoreContacts — restored \(restoredCount) contact(s)")
        } catch {
            print("[Supabase] restoreContacts — error: \(error)")
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

    // MARK: - Interaction Photos

    struct InteractionPhotoRow: Decodable {
        let id: UUID
        let storagePath: String
        let uploadedBy: UUID

        enum CodingKeys: String, CodingKey {
            case id
            case storagePath = "storage_path"
            case uploadedBy = "uploaded_by"
        }
    }

    func resolveSupabaseUserID(forBLEDeviceUUID bleUUID: UUID) async -> UUID? {
        struct ProfileLookup: Decodable { let id: UUID }
        let results: [ProfileLookup]? = try? await client
            .from("profiles")
            .select("id")
            .eq("ble_device_uuid", value: bleUUID.uuidString)
            .limit(1)
            .execute()
            .value
        return results?.first?.id
    }

    private func participantsForContact(_ contactBLEUUID: UUID) async -> [UUID]? {
        guard let myID = session?.user.id,
              let contactID = await resolveSupabaseUserID(forBLEDeviceUUID: contactBLEUUID) else { return nil }
        return [myID, contactID].sorted { $0.uuidString < $1.uuidString }
    }

    func uploadInteractionPhoto(data: Data, contactBLEUUID: UUID, interactionDate: Date) async -> String? {
        guard let myID = session?.user.id,
              let participants = await participantsForContact(contactBLEUUID),
              let interactionID = await findInteractionID(participants: participants, near: interactionDate) else { return nil }

        struct PhotoRow: Encodable {
            let interaction_id: UUID
            let uploaded_by: UUID
            let storage_path: String
        }

        let path = "\(myID.uuidString.lowercased())/interactions/\(UUID().uuidString.lowercased()).jpg"

        do {
            _ = try await client.storage
                .from("interaction-photos")
                .upload(path: path, file: data, options: FileOptions(contentType: "image/jpeg", upsert: false))
            try await client.from("photos")
                .insert(PhotoRow(interaction_id: interactionID, uploaded_by: myID, storage_path: path))
                .execute()
            print("[Supabase] uploadInteractionPhoto — uploaded \(path)")
            return path
        } catch {
            print("[Supabase] uploadInteractionPhoto — error: \(error)")
            return nil
        }
    }

    func fetchInteractionPhotoRows(contactBLEUUID: UUID, interactionDate: Date) async -> [InteractionPhotoRow] {
        guard let participants = await participantsForContact(contactBLEUUID),
              let interactionID = await findInteractionID(participants: participants, near: interactionDate) else { return [] }
        do {
            return try await client
                .from("photos")
                .select("id, storage_path, uploaded_by")
                .eq("interaction_id", value: interactionID.uuidString)
                .execute()
                .value
        } catch {
            print("[Supabase] fetchInteractionPhotoRows — error: \(error)")
            return []
        }
    }

    /// Finds the boop_interactions row for the given participants closest in time to `date` (within 24h).
    private func findInteractionID(participants: [UUID], near date: Date) async -> UUID? {
        struct Row: Decodable { let id: UUID; let started_at: String }
        let participantsLiteral = "{\(participants.map { $0.uuidString.lowercased() }.joined(separator: ","))}"
        guard let rows: [Row] = try? await client
            .from("boop_interactions")
            .select("id, started_at")
            .filter("participants", operator: "cs", value: participantsLiteral)
            .execute()
            .value else { return nil }
        let formatter = ISO8601DateFormatter()
        return rows
            .compactMap { row -> (UUID, TimeInterval)? in
                guard let d = formatter.date(from: row.started_at) else { return nil }
                let delta = abs(d.timeIntervalSince(date))
                return delta < 86400 ? (row.id, delta) : nil
            }
            .min(by: { $0.1 < $1.1 })?
            .0
    }

    func downloadPhoto(storagePath: String) async -> Data? {
        do {
            return try await client.storage
                .from("interaction-photos")
                .download(path: storagePath)
        } catch {
            print("[Supabase] downloadPhoto — error: \(error)")
            return nil
        }
    }

    func deleteInteractionPhoto(storagePath: String) async {
        do {
            try await client.from("photos")
                .delete()
                .eq("storage_path", value: storagePath)
                .execute()
            try await client.storage
                .from("interaction-photos")
                .remove(paths: [storagePath])
            print("[Supabase] deleteInteractionPhoto — deleted \(storagePath)")
        } catch {
            print("[Supabase] deleteInteractionPhoto — error: \(error)")
        }
    }

    func syncPendingPhotoUploads() async {
        guard let myID = session?.user.id else { return }
        let myIDString = myID.uuidString
        for interaction in BoopInteractionRepository.shared.fetchAll() {
            guard let contactBLEUUID = interaction.contact?.uuid else { continue }
            var metadata = interaction.photoMetadata
            var changed = false
            for i in metadata.indices where metadata[i].storagePath == nil && metadata[i].uploadedByUserID == myIDString {
                guard i < interaction.imageData.count else { continue }
                if let path = await uploadInteractionPhoto(
                    data: interaction.imageData[i],
                    contactBLEUUID: contactBLEUUID,
                    interactionDate: interaction.timestamp
                ) {
                    metadata[i].storagePath = path
                    changed = true
                }
            }
            if changed { interaction.photoMetadata = metadata }
        }
    }

    // MARK: - Private

    func performPostAuthSync() async {
        if let contact = ContactRepository.shared.getOwnProfile() {
            await syncProfile(contact)
        } else {
            await restoreProfileFromRemote()
            if let contact = ContactRepository.shared.getOwnProfile() {
                await syncProfile(contact)
            }
        }
        await restoreContacts()
        await restoreInteractions()
        await syncAllBoopConnections()
        await syncPendingPhotoUploads()
        hasProfile = ContactRepository.shared.getOwnProfile() != nil
    }

    /// Restores interactions from boop_interactions, fetching associated photos by interaction_id.
    func restoreInteractions() async {
        guard let userId = session?.user.id else { return }

        struct InteractionRow: Decodable {
            let id: UUID
            let participants: [UUID]
            let started_at: String
        }
        struct PhotoRow: Decodable {
            let storage_path: String
            let uploaded_by: UUID
        }
        struct BLELookup: Decodable { let ble_device_uuid: UUID? }

        let dateFormatter = ISO8601DateFormatter()

        do {
            let interactions: [InteractionRow] = try await client
                .from("boop_interactions")
                .select("id, participants, started_at")
                .filter("participants", operator: "cs", value: "{\(userId.uuidString.lowercased())}")
                .execute()
                .value

            var restoredCount = 0
            for interaction in interactions {
                guard let otherUserId = interaction.participants.first(where: { $0 != userId }),
                      let timestamp = dateFormatter.date(from: interaction.started_at) else { continue }

                let lookups: [BLELookup] = (try? await client
                    .from("profiles")
                    .select("ble_device_uuid")
                    .eq("id", value: otherUserId.uuidString)
                    .limit(1)
                    .execute()
                    .value) ?? []

                guard let bleUUID = lookups.first?.ble_device_uuid,
                      let contact = ContactRepository.shared.find(byUUID: bleUUID) else { continue }

                if BoopInteractionRepository.shared.isDuplicate(
                    contactUUID: bleUUID,
                    timestamp: timestamp,
                    window: 12 * 3600
                ) { continue }

                let photos: [PhotoRow] = (try? await client
                    .from("photos")
                    .select("storage_path, uploaded_by")
                    .eq("interaction_id", value: interaction.id.uuidString)
                    .execute()
                    .value) ?? []

                var imageData: [Data] = []
                var metadata: [PhotoMeta] = []
                for photo in photos {
                    if let data = await downloadPhoto(storagePath: photo.storage_path) {
                        imageData.append(data)
                        metadata.append(PhotoMeta(storagePath: photo.storage_path, uploadedByUserID: photo.uploaded_by.uuidString))
                    }
                }

                if let localInteraction = BoopInteractionRepository.shared.create(
                    location: "",
                    timestamp: timestamp,
                    contact: contact
                ) {
                    localInteraction.imageData = imageData
                    localInteraction.photoMetadata = metadata
                    try? ModelContextProvider.shared.context?.save()
                }
                restoredCount += 1
            }
            print("[Supabase] restoreInteractions — restored \(restoredCount) interaction(s)")
        } catch {
            print("[Supabase] restoreInteractions — error: \(error)")
        }
    }

    private func restoreProfileFromRemote() async {
        guard let userId = session?.user.id else { return }

        struct RemoteProfileRow: Decodable {
            let display_name: String
            let birthday: String?
            let bio: String?
            let avatar_url: String?
            let gradient_colors: [String]?
        }

        do {
            let rows: [RemoteProfileRow] = try await client
                .from("profiles")
                .select("display_name, birthday, bio, avatar_url, gradient_colors")
                .eq("id", value: userId.uuidString)
                .limit(1)
                .execute()
                .value

            guard let row = rows.first else {
                print("[Supabase] restoreProfileFromRemote — no remote profile found")
                return
            }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            let birthday = row.birthday.flatMap { formatter.date(from: $0) }

            var avatarData: Data? = nil
            if let urlString = row.avatar_url, let url = URL(string: urlString) {
                avatarData = try? await URLSession.shared.data(from: url).0
            }

            let gradientColors = (row.gradient_colors ?? []).compactMap { Contact.stringToColor($0) }
            await ContactRepository.shared.saveOwnProfile(
                displayName: row.display_name,
                birthday: birthday,
                bio: row.bio,
                gradientColors: gradientColors,
                avatarData: avatarData
            )
            print("[Supabase] restoreProfileFromRemote — restored '\(row.display_name)'")
        } catch {
            print("[Supabase] restoreProfileFromRemote — error: \(error)")
        }
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
