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

    /// Fetches all boop connections from Supabase and restores the corresponding Contact records locally.
    /// Call on login to recover contacts after reinstall or on a new device.
    func restoreContacts() async {
        guard let userId = session?.user.id else { return }

        struct ConnectionRow: Decodable {
            let participants: [UUID]
        }
        struct RemoteContact: Decodable {
            let ble_device_uuid: UUID?
            let name: String
            let birthday: String?
            let bio: String?
            let avatar_url: String?
        }

        do {
            let connections: [ConnectionRow] = try await client
                .from("boop_connections")
                .select("participants")
                .filter("participants", operator: "cs", value: "{\(userId.uuidString.lowercased())}")
                .execute()
                .value

            var restoredCount = 0
            for connection in connections {
                guard let otherUserId = connection.participants.first(where: { $0 != userId }) else { continue }

                let profiles: [RemoteContact] = try await client
                    .from("profiles")
                    .select("ble_device_uuid, name, birthday, bio, avatar_url")
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
                    displayName: profile.name,
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
              let participants = await participantsForContact(contactBLEUUID) else { return nil }

        struct PhotoRow: Encodable {
            let participants: [UUID]
            let interaction_date: String
            let uploaded_by: UUID
            let storage_path: String
        }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        let path = "\(myID.uuidString.lowercased())/interactions/\(UUID().uuidString.lowercased()).jpg"

        do {
            _ = try await client.storage
                .from("interaction-photos")
                .upload(path: path, file: data, options: FileOptions(contentType: "image/jpeg", upsert: false))
            try await client.from("interaction_photos")
                .insert(PhotoRow(
                    participants: participants,
                    interaction_date: dateFormatter.string(from: interactionDate),
                    uploaded_by: myID,
                    storage_path: path
                ))
                .execute()
            print("[Supabase] uploadInteractionPhoto — uploaded \(path)")
            return path
        } catch {
            print("[Supabase] uploadInteractionPhoto — error: \(error)")
            return nil
        }
    }

    func fetchInteractionPhotoRows(contactBLEUUID: UUID, interactionDate: Date) async -> [InteractionPhotoRow] {
        guard let participants = await participantsForContact(contactBLEUUID) else { return [] }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        let participantsLiteral = "{\(participants.map { $0.uuidString.lowercased() }.joined(separator: ","))}"

        do {
            return try await client
                .from("interaction_photos")
                .select("id, storage_path, uploaded_by")
                .filter("participants", operator: "eq", value: participantsLiteral)
                .eq("interaction_date", value: dateFormatter.string(from: interactionDate))
                .execute()
                .value
        } catch {
            print("[Supabase] fetchInteractionPhotoRows — error: \(error)")
            return []
        }
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
            try await client.from("interaction_photos")
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
    }

    /// Restores interactions from the interaction_photos table.
    /// Groups photos by (participants + date) to reconstruct each unique interaction.
    func restoreInteractions() async {
        guard let userId = session?.user.id else { return }

        struct PhotoRow: Decodable {
            let participants: [UUID]
            let interaction_date: String
            let storage_path: String
            let uploaded_by: UUID
        }
        struct BLELookup: Decodable { let ble_device_uuid: UUID? }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]

        do {
            let photos: [PhotoRow] = try await client
                .from("interaction_photos")
                .select("participants, interaction_date, storage_path, uploaded_by")
                .filter("participants", operator: "cs", value: "{\(userId.uuidString.lowercased())}")
                .execute()
                .value

            let grouped = Dictionary(grouping: photos) {
                let sorted = $0.participants.map { $0.uuidString.lowercased() }.sorted().joined()
                return "\(sorted)-\($0.interaction_date)"
            }.mapValues { rows in
                // Deduplicate: keep only one photo per uploader (guards against double-upload bugs)
                Array(Dictionary(grouping: rows) { $0.uploaded_by }.values.compactMap { $0.first })
            }

            var restoredCount = 0
            for (_, photoGroup) in grouped {
                guard let first = photoGroup.first,
                      let timestamp = dateFormatter.date(from: first.interaction_date),
                      let otherUserId = first.participants.first(where: { $0 != userId }) else { continue }

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

                var imageData: [Data] = []
                var metadata: [PhotoMeta] = []
                for photo in photoGroup {
                    if let data = await downloadPhoto(storagePath: photo.storage_path) {
                        imageData.append(data)
                        metadata.append(PhotoMeta(storagePath: photo.storage_path, uploadedByUserID: photo.uploaded_by.uuidString))
                    }
                }

                if let interaction = BoopInteractionRepository.shared.create(
                    location: "",
                    timestamp: timestamp,
                    contact: contact
                ) {
                    interaction.imageData = imageData
                    interaction.photoMetadata = metadata
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
            let name: String
            let birthday: String?
            let bio: String?
            let avatar_url: String?
        }

        do {
            let rows: [RemoteProfileRow] = try await client
                .from("profiles")
                .select("name, birthday, bio, avatar_url")
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

            ContactRepository.shared.saveOwnProfile(
                displayName: row.name,
                birthday: birthday,
                bio: row.bio,
                gradientColors: [],
                avatarData: avatarData
            )
            print("[Supabase] restoreProfileFromRemote — restored '\(row.name)'")
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
