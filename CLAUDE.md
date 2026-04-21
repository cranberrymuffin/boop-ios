# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Boop is an offline social iOS app that uses Bluetooth Low Energy (BLE) and Ultra-Wideband (UWB) technology for peer-to-peer proximity-based social interactions. Users can "boop" nearby friends within touching distance, creating a chronological timeline of real-world interactions.

**Key Technologies:**
- **BLE:** Device discovery and messaging (simultaneous peripheral + central mode)
- **UWB:** Precise distance measurement (±5cm accuracy) via Nearby Interaction framework
- **CoreLocation:** Continuous location tracking with path recording during BLE sessions
- **SwiftData:** Local persistence for contacts, interaction history, and user profiles
- **Swift 6:** Latest language features with strict concurrency checking

## Build & Run

### Building from Command Line

**Important:** The Xcode project is located in the parent directory (`boop-ios.xcodeproj`), not in the source folder. All `xcodebuild` commands must run from the directory containing the `.xcodeproj`.

**Recommended build command (simulator, avoids code signing):**

```bash
# From the project root (parent of boop-ios/ source dir):
# 1. Find an available simulator UUID
xcrun simctl list devices available | grep iPhone

# 2. Build using the simulator UUID (replace with actual UUID from step 1)
xcodebuild -scheme boop-ios \
  -destination 'platform=iOS Simulator,id=<SIMULATOR-UUID>' \
  -configuration Debug build
```

**Why use a simulator UUID?** Destination by name (e.g. `name=iPhone 15`) fails if that exact simulator isn't installed. UUIDs from `xcrun simctl list` always work. Code signing is also skipped for simulator builds, avoiding provisioning profile errors.

```bash
# Other useful commands (all from project root):

# Build for device (requires code signing)
xcodebuild -scheme boop-ios -destination 'generic/platform=iOS' build

# Clean build folder
xcodebuild -scheme boop-ios clean

# Build and run tests
xcrun simctl list devices available | grep iPhone  # find a UUID first
xcodebuild -scheme boop-ios \
  -destination 'platform=iOS Simulator,id=<SIMULATOR-UUID>' \
  test
```

**Common Build Issues:**
- **"Unable to find a device matching the provided destination specifier":** The simulator name doesn't match any installed simulator. Use `xcrun simctl list devices available` to find exact names or UUIDs, and prefer UUIDs.
- **Code signing / provisioning profile errors:** These only affect device builds, not simulator builds. For device builds, ensure Team ID (P3PR8G7GB9) is configured and use `-allowProvisioningUpdates`. Note: `-allowProvisioningUpdates` still requires a valid Apple Developer account configured in Xcode.
- **"No such project" error:** Make sure you're in the directory containing `boop-ios.xcodeproj`, not in the `boop-ios/` source folder.

### Running from Xcode

1. Open `boop-ios.xcodeproj` in Xcode (not the source folder)
2. Select a target device:
   - **Simulator:** For UI development (BLE/UWB features limited)
   - **Physical Device:** Required for full BLE advertising and UWB ranging
3. Ensure automatic code signing is enabled (Team: P3PR8G7GB9)
4. Press Cmd+R to build and run

**Testing Boop Functionality:**
- Requires **two physical devices** with UWB support (iPhone 11+)
- Both devices must have the app installed and open
- Open `BoopRangingView` on both devices to initiate discovery

## Git Workflow

### Branch Naming Convention

Use descriptive, ALL-CAPS prefixes for feature branches:

```
FIX-<issue-description>          # Bug fixes
ADD-<feature-name>                # New features
UPDATE-<component-name>           # Updates to existing features
REFACTOR-<component-name>         # Code refactoring
```

**Examples:**
- `FIX-TIMELINE-HEADER-ERROR`
- `ADD-PHOTO-SHARING`
- `UPDATE-BLUETOOTH-PROTOCOL`
- `REFACTOR-DATA-LAYER`

### Workflow Steps

**1. Create Feature Branch**
```bash
git checkout main
git pull
git checkout -b FIX-YOUR-FEATURE-NAME
```

**2. Make Changes & Commit**
```bash
# Stage specific files (avoid staging .claude settings)
git add boop-ios/BoopTimelineView.swift boop-ios/model/Contact.swift

# Commit with detailed message
git commit -m "$(cat <<'EOF'
Brief summary of change (50 chars or less)

Detailed explanation of what changed and why. Include:
- What problem this solves
- What changes were made
- Any technical details worth noting

Changes:
- Bullet point list of specific changes
- File-level changes if relevant

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
)"
```

**3. Push & Set Upstream**
```bash
# First push - set upstream tracking
git push -u origin FIX-YOUR-FEATURE-NAME

# Subsequent pushes
git push
```

**4. Create Pull Request**
- Use the GitHub URL printed after push
- Review changes in PR before merging
- Merge to main after approval

**5. Sync Main**
```bash
git checkout main
git pull
```

### Commit Best Practices

- **Atomic commits:** Each commit should represent a single logical change
- **Descriptive messages:** Explain the "why" not just the "what"
- **Co-authoring:** Always include Claude co-author line when AI assists
- **File selection:** Don't commit `.claude/settings.local.json` (local config only)
- **Build verification:** Ensure code builds before committing

### Common Commands

```bash
# Check current status
git status

# View recent commits
git log --oneline -5

# View changes before staging
git diff

# View staged changes
git diff --cached

# Unstage files
git restore --staged <file>

# Discard local changes
git restore <file>
```

## Date & Time Formatting

### Timeline Header Implementation

**File:** `Components/BoopInteractionTimelineBody.swift`

The timeline uses `RelativeDateTimeFormatter` for dynamic, user-friendly time displays:

```swift
private let relativeDateFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full  // "2 hours ago" vs "2 hr. ago"
    return formatter
}()

private func headerText(for date: Date) -> String {
    let text = getFormattedTimestamp(for: date)
    let sanitized = text.trimmingCharacters(in: .whitespaces).lowercased()
    let words = sanitized.components(separatedBy: .whitespaces)

    // Group minute-level timestamps under "Last Hour"
    if words.contains(where: { $0.contains("minute") }) {
        return "Last Hour"
    }
    // Group hour-level timestamps under "Today"
    if words.contains(where: { $0.contains("hour") }) {
        return "Today"
    }

    return text.capitalized
}
```

### Key Principles

**✅ DO:**
- Use `RelativeDateTimeFormatter` for relative time strings ("2 hours ago", "yesterday")
- Calculate headers **per-item** as you iterate through data
- Let the formatter choose appropriate units automatically
- Sanitize output to group fine-grained units if needed
- Show headers only when transitioning between different time periods
- Let SwiftUI re-renders handle updates (no manual timers needed)

**❌ DON'T:**
- Don't pre-group timestamps into fixed buckets/dictionaries (causes stale headers)
- Don't use `Date.RelativeFormatStyle` if you need granularity control (no `allowedUnits` property)
- Don't calculate bucketed timestamps (start-of-day, start-of-week, etc.)
- Don't use manual refresh timers unless absolutely necessary
- Don't use `DateComponentsFormatter` for relative time (it's for durations)

### Why Dynamic Calculation?

**Problem:** If you pre-group "12 minutes ago" and "25 minutes ago" into separate dictionary keys, they'll stay separate even as time passes, creating fragmented headers.

**Solution:** Calculate headers on every render:
1. Iterate through sorted items sequentially
2. Calculate header for current item
3. Compare with previous item's header
4. Show header only if different from previous

This ensures:
- Headers stay current as time passes
- "Just now" transitions to "5 minutes ago" to "Today" naturally
- No stale "17 hours ago" headers for recent items
- Proper grouping as time periods change

### Formatter Options

**`RelativeDateTimeFormatter`** (Recommended for timeline headers)
- **Pros:** Full control, localized, automatic unit selection
- **Cons:** No built-in granularity control (use string matching to group units)
- **Properties:** `unitsStyle`, `dateTimeStyle`, `formattingContext`

**`Date.RelativeFormatStyle`** (Simpler but less flexible)
- **Pros:** Modern Swift API, concise syntax
- **Cons:** No `allowedUnits` property, always shows largest unit only
- **Usage:** `date.formatted(.relative(presentation: .named))`

**`DateComponentsFormatter`** (For durations, not relative time)
- **Pros:** Good for intervals (e.g., "2h 30m")
- **Cons:** Not designed for "ago" formatting
- **Usage:** Countdown timers, elapsed time displays

## Architecture

### Directory Structure

Top-level workspace:
```
boop-ios.xcodeproj/            # Xcode project (open this, not the source folder)
boop-ios/                      # Main app source root (see below)
BoopLiveActivity/              # Live Activity widget extension
│   ├── BoopLiveActivityLiveActivity.swift
│   ├── BoopLiveActivityBundle.swift
│   └── Info.plist
Shared/                        # Code shared between app and widget targets
│   └── BoopLiveActivityAttributes.swift
design-tokens/                 # Figma design token JSON source files
```

Main app source (`boop-ios/`):
```
boop-ios/                              # Source root
├── boop_iosApp.swift                  # App entry point, ModelContainer setup
├── BoopManager.swift                  # Orchestration layer (boop + persistence + location)
├── LocationManager.swift              # CoreLocation tracking with path buffer
├── StorageCoordinator.swift           # Async storage init
├── Views/
│   ├── RootView.swift                 # Root navigation wrapper
│   ├── MainTabView.swift              # 4-tab navigation
│   ├── BoopTimelineView.swift         # Timeline feed
│   ├── BoopRangingView.swift          # Proximity-based auto-boop UI
│   ├── BoopInteractionListView.swift  # Demo/preview list view
│   ├── ContactsView.swift             # Contacts list
│   ├── ContactDetailView.swift        # Contact detail (navigation push)
│   ├── ProfileView.swift              # Profile display/edit (uses ModelContext)
│   ├── ProfileSetupView.swift         # Onboarding flow (with PhotosPicker)
│   ├── AddManualBoopView.swift        # Manual boop entry sheet
│   └── LiveActivityManager.swift      # Live Activity management
├── Bluetooth/
│   ├── BluetoothManager.swift         # BLE coordinator
│   ├── BluetoothManagerService.swift  # Central + Peripheral implementation
│   ├── UWBManager.swift               # UWB ranging (per-device NISession)
│   └── UWBService.swift               # Distance threshold logic
├── Model/
│   ├── PersistentModel/               # SwiftData @Model classes
│   │   ├── Contact.swift              # @Model — contact profiles
│   │   ├── UserProfile.swift          # @Model — user's own profile
│   │   ├── BoopInteraction.swift      # @Model — interactions with path data
│   │   └── NotificationIntent.swift   # @Model — scheduled notifications
│   ├── Boop.swift                     # Value types: Boop struct + BoopEvent
│   ├── BluetoothMessage.swift         # Binary BLE protocol
│   ├── NearbyDevice.swift
│   ├── ConnectionRequest.swift
│   └── ConnectionResponse.swift
├── DataStore/
│   ├── UserDataStore.swift            # UserDefaults actor (local device UUID storage)
│   └── UserDefaults/
│       ├── UserDefaultsKeys.swift
│       └── UserDefaultsUtility.swift
├── Notifications/
│   ├── NotificationManager.swift      # Authorization handling
│   ├── NotificationScheduler.swift    # Schedule creation/sync
│   ├── NotificationBuilder.swift      # Content construction
│   ├── NotificationTrigger.swift      # Trigger type definitions
│   └── NotificationType.swift         # Notification type enum
├── Components/
│   ├── BoopInteractionCard.swift      # Timeline card (with map support)
│   ├── BoopInteractionTimelineBody.swift  # Reusable timeline body + detail view with map
│   ├── ContactInteractionCard.swift   # Contact list card
│   ├── ProfileDisplayCard.swift       # Profile card with avatar display
│   └── Gradient/
│       ├── AnimatedMeshGradient.swift  # 3x3 MeshGradient animation
│       ├── StyledTextField.swift
│       ├── DatePickerField.swift
│       └── DisplayColorPickerSheet.swift
├── DesignSystem/
│   ├── Colors+DesignSystem.swift
│   ├── Typography+DesignSystem.swift
│   ├── Spacing+DesignSystem.swift
│   ├── Sizes+DesignSystem.swift       # Includes MapSize tokens
│   ├── Radius+DesignSystem.swift
│   └── ViewModifiers+DesignSystem.swift
├── Utilities/
│   └── StringSanitization.swift
└── Widgets/                           # Reserved, currently empty
```

### Persisted Data Store

The app uses **SwiftData as its primary persistence layer** for all user data (profiles, contacts, interactions, notifications). `UserDataStore` / UserDefaults is only used to persist the local device UUID for BLE identity.

#### SwiftData Models

**`Contact`** (`Model/PersistentModel/Contact.swift`)
- `uuid: UUID` — remote device's UUID
- `displayName: String`, `birthday: Date?`, `bio: String?`
- `gradientColorsData: [String]` — colors stored as strings, converted via `colorToString()`/`stringToColor()`
- `@Relationship(deleteRule: .cascade, inverse: \BoopInteraction.contact) var interactions: [BoopInteraction]` — one-to-many, cascade delete

**`BoopInteraction`** (`Model/PersistentModel/BoopInteraction.swift`)
- `id: UUID`, `title: String`, `location: String` (reverse-geocoded), `timestamp: Date`
- `endTimestamp: Date?` — end of the BLE session (defaults to +2 hours for manual boops)
- `imageData: [Data]` — photo attachments
- `pathCoordinatesData: Data?` — JSON-encoded `[PathCoordinate]` for the path traveled during the interaction
- `pathCoordinates: [CLLocationCoordinate2D]` — computed property that encodes/decodes the path data
- `contact: Contact?` — inverse relationship back to Contact

**`UserProfile`** (`Model/PersistentModel/UserProfile.swift`)
- `name: String`, `createdAt: Date`, `avatarData: Data?`, `birthday: Date?`, `bio: String?`
- `gradientColorsData: [String]` — same color storage pattern as Contact

**`NotificationIntent`** (`Model/PersistentModel/NotificationIntent.swift`)
- `id: UUID`, `typeIdentifier: NotificationTypeIdentifier`, `entityUUID: UUID?`
- `title: String`, `body: String`, `isActive: Bool`
- Trigger config: `triggerKind`, `triggerInterval`, `triggerWeekday`, `triggerHour`, `triggerMinute`
- Types: `.contactReminder`, `.weeklyPlanning`

**Critical rule:** All `@Model` stored properties must be `var` (not `let`) for Swift 6 compatibility.

#### ModelContainer Setup (`boop_iosApp.swift`)

```
Schema: [Contact, UserProfile, BoopInteraction, NotificationIntent]
```

The app entry point creates the `ModelContainer` asynchronously after `StorageCoordinator` finishes directory setup. A loading screen shows until the container is ready, then `RootView` receives it via `.modelContainer()`.

**Profile management uses ModelContext directly:** `ProfileView` fetches the user profile via `modelContext.fetch(FetchDescriptor<UserProfile>)` and inserts new/updated profiles via `modelContext.insert()`. Profile data is not stored in UserDefaults.

#### UserDataStore Actor (`DataStore/UserDataStore.swift`)

A Swift `actor` that wraps UserDefaults access. Its only remaining role is persisting the local device UUID (`com.boop.localDeviceUUID`) used for BLE identity. All profile data (name, birthday, bio, avatar, gradient colors) is stored exclusively in SwiftData.

#### StorageCoordinator (`StorageCoordinator.swift`)

An `actor` that coordinates async initialization of the SwiftData directory. Uses checked continuations to block ModelContainer creation until the storage directory exists, preventing race conditions.

### Bluetooth

#### BluetoothManager (`Bluetooth/BluetoothManager.swift`, `@MainActor`)

Top-level BLE coordinator. Owns the `BluetoothManagerServiceImpl` (central + peripheral) and `UWBManager`.

- `start()` / `stop()` — starts/stops BLE advertising, scanning, and UWB
- `getNearbyDevices()` → `[UUID: DevicePositionCategory]`
- `sendMessage(_:to:)` / `disconnect(from:)` — sends BLE messages to or disconnects specific devices
- `localDeviceUUID` — persisted in UserDefaults, stable across sessions
- Publishes `nearbyDevices` from UWBManager's Combine publisher

#### BluetoothManagerService (`Bluetooth/BluetoothManagerService.swift`)

Implements **dual-mode BLE** — the device acts as both peripheral (advertising) and central (scanning) simultaneously.

**Service UUIDs:**
```
Service:     D3A42A7C-DA0E-4D2C-AAB1-88C77E018A5F
Message:     D3A42A7D-... (.write, .notify)
UWB Token:   D3A42A7E-... (.read, .write)
Token ACK:   D3A42A7F-... (.notify)
```

**Binary Protocol (`BluetoothMessage`):**
```
[UUID: 16 bytes][MessageType: 1 byte][DisplayNameLength: 1 byte]
[DisplayName: variable][PayloadLength: 2 bytes][Payload: variable]
```

**Message Types:**
- `0x01` connectionRequest, `0x02` accept, `0x03` reject, `0x05` disconnect
- `0x06` boop (automatic proximity-triggered boop)
- `0x07` boopRequest (manual boop request, reserved)
- `0x08` presence (name/profile announcement)
- `0x09` stoppedRanging (UWB session ended)

**Delegates:**
- `BluetoothServiceDelegate` — connection events, UWB token exchange
- `BoopDelegate` — boop/request/presence received callbacks

#### UWBManager (`Bluetooth/UWBManager.swift`, `@MainActor`)

**Per-device NISession architecture** — each connected peer gets its own `NISession` instance.

**Distance Thresholds** (defined in `UWBService.swift`):
- ≤ 7cm (0.07m) → `ApproxTouching` (boop range)
- ≤ 100cm (1.0m) → `InRange` (nearby)
- \> 100cm → `OutOfRange`

**Flow:** Discovery tokens are exchanged via BLE characteristics. Once both peers have each other's token, ranging begins via `NINearbyPeerConfiguration`. Distance updates publish to `nearbyDevices: [UUID: DevicePositionCategory]` via Combine.

### LocationManager (`LocationManager.swift`, `@MainActor`)

Tracks device location continuously for path recording during BLE sessions.

**Rolling Buffer:**
- Maintains up to 3,500 coordinate entries with timestamps
- Minimum distance filter: 1.0m between points (prevents GPS noise)
- Accuracy filter: rejects points with horizontalAccuracy <= 0.1

**Public API:**
- `requestPermissionIfNeeded()` — requests when-in-use authorization
- `startTracking()` / `stopTracking()` — manages `CLLocationManager` updates
- `snapshotPath()` → `[CLLocationCoordinate2D]` — full buffer snapshot
- `getLocations(from:to:)` → `[CLLocationCoordinate2D]` — coordinates within a time window (used by BoopManager on session end)
- `currentCoordinate()` → `CLLocationCoordinate2D?` — latest single coordinate
- `reverseGeocodeCurrentLocation()` → `String` — human-readable location name

**Reverse Geocoding:** Periodically (every ~20 new points) reverse-geocodes the latest coordinate and publishes it as `currentLocationName`. Format: "Neighborhood, City" or "Street, City".

### Notifications (`Notifications/`)

Local notification infrastructure for scheduling recurring reminders.

- **`NotificationManager`** — singleton handling `UNUserNotificationCenter` authorization
- **`NotificationScheduler`** — creates/syncs `UNCalendarNotificationTrigger` schedules from `NotificationIntent` models
- **`NotificationBuilder`** — constructs `UNNotificationContent`
- **`NotificationTrigger`** / **`NotificationType`** — trigger kind and cadence definitions

**Weekly Planning Notification:** Scheduled at app startup for Sundays at 5pm (`weekday: 1, hour: 17, minute: 0`).

### BoopManager — Orchestration (`BoopManager.swift`, `@MainActor`)

Central orchestrator tying BLE + UWB + location + persistence together. Injected as `@StateObject` at the app root and passed via `@EnvironmentObject`. Owns its own `ModelContext` for all boop persistence.

**Key Published State:**
- `latestBoopEvent: BoopEvent?` — triggers proximity overlay animation on new boops

**Dependencies (injected at app startup):**
- `setModelContainer(_ container:)` — creates a private `ModelContext` for persistence
- `setLocationManager(_ manager:)` — provides location data for path recording

**Automatic Boop Flow:**
1. `BoopManager` subscribes to `bluetoothManager.nearbyDevices` via Combine
2. `processNearbyDevicesUpdate(_:)` detects a device entering `.ApproxTouching` state
3. If not in cooldown for that peer, sends a `.boop` BLE message automatically
4. `didReceiveBoop(from:displayName:)` creates `Contact` + `BoopInteraction` in SwiftData, sets `latestBoopEvent`
5. `BoopRangingView.onChange(of: latestBoopEvent)` shows the boop overlay animation

**BLE Session Tracking:**
- `didDeviceConnect(peripheralUUID:)` — records session start time
- `didDeviceDisconnect(peripheralUUID:)` — triggers `handleSessionEnd()` which:
  1. Retrieves path coordinates from `LocationManager.getLocations(from:to:)` for the session window
  2. If an existing `BoopInteraction` was created during the session (from a proximity boop), enriches it with `endTimestamp` and `pathCoordinates`
  3. If no boop happened but session lasted >= 60 seconds, auto-creates a `BoopInteraction` with path data
  4. Reverse-geocodes the current location for the `location` field if empty

**Observer Pattern:** Subscribes to `bluetoothManager.nearbyDevices` publisher via Combine. When a device enters touching range, triggers an automatic boop. On disconnect, enriches or creates interactions with location data.

### View + Model Pattern

#### Navigation Structure

```
boop_iosApp (ModelContainer + BoopManager + LocationManager)
  └─ RootView
       └─ MainTabView
            ├─ Tab 1: BoopTimelineView (clock.fill)
            │    ├─ Toolbar: "+" → AddManualBoopView (sheet)
            │    ├─ @Query BoopInteraction (sorted by timestamp desc)
            │    └─ NavigationLink → BoopInteractionDetailView (with map)
            ├─ Tab 2: BoopRangingView (hand.tap.fill)
            │    └─ Proximity-based auto-boop UI (ProgressView + display name overlay)
            ├─ Tab 3: ContactsView (person.2)
            │    ├─ @Query Contact
            │    └─ NavigationLink → ContactDetailView (navigation push)
            └─ Tab 4: ProfileView (person.crop.circle)
                 ├─ Display mode (gradient bg + profile card with avatar)
                 └─ Edit mode (ProfileSetupView with PhotosPicker, requireAllFields=false)
```

#### State Management Patterns

- **`@Query`** — Views subscribe to SwiftData queries for automatic UI updates when models change
- **`@Environment(\.modelContext)`** — Used for inserts and deletes
- **`@EnvironmentObject`** — `BoopManager` and `LocationManager` injected at app root, available in all views
- **`@StateObject`** — `BoopManager` and `LocationManager` lifecycle owned by `boop_iosApp`
- **`@Published`** — Manager properties that drive UI (selections, display names, events)
- **`@State`** — Local UI state (sheet presentation, editing mode, form fields)

#### Data Flow: Boop → Timeline

1. UWB detects touching distance → `BoopManager` automatically sends `.boop` BLE message
2. `BoopManager.didReceiveBoop(from:displayName:)` finds/creates `Contact`, creates `BoopInteraction` with current location name, sets `latestBoopEvent`
3. `BoopRangingView.onChange(of: latestBoopEvent)` shows animated boop overlay
4. When BLE device disconnects → `BoopManager.handleSessionEnd()` enriches the existing interaction with `endTimestamp` and `pathCoordinates` from LocationManager
5. `@Query` automatically picks up the new/updated interaction → UI updates

#### Data Flow: Location → Interaction

1. `LocationManager` continuously tracks coordinates into a rolling buffer (up to 3,500 points)
2. On BLE connect, `BoopManager` records `deviceSessionStart[peripheralUUID] = Date()`
3. On BLE disconnect, `BoopManager` calls `locationManager.getLocations(from: sessionStart, to: now)` to get the path
4. Path coordinates are stored as JSON-encoded `[PathCoordinate]` in `BoopInteraction.pathCoordinatesData`
5. `BoopInteractionDetailView` renders the path on a `Map` with start/end pins and a polyline

#### Card Components

- **`BoopInteractionCard`** — timeline items with title, location, relative time, overlapping thumbnails. Uses `TimelineView(.periodic(from: .now, by: 60))` for auto-refreshing timestamps.
- **`BoopInteractionTimelineBody`** — reusable timeline body (section headers + cards) extracted from `BoopTimelineView`; used by both `BoopTimelineView` and `ContactDetailView`'s boop history section. Also contains `BoopInteractionDetailView` with map display for path coordinates.
- **`ContactInteractionCard`** — contact list items with name, boop count, last boop time
- **`ProfileDisplayCard`** — profile card with avatar thumbnail (from `avatarData`), display name, birthday, and bio
- **`AnimatedMeshGradient`** — 3x3 MeshGradient with configurable wave animation (vertical/horizontal), used for profile backgrounds

### Design System

All design tokens live in `DesignSystem/`. Never hardcode visual values — always use the token enums.

#### Colors — Asset Catalog Color Sets

Colors are defined as **Asset Catalog color sets** in `Assets.xcassets/`, with separate light and dark appearance variants. SwiftUI resolves the correct value automatically based on system appearance — no `@Environment(\.colorScheme)` branching needed.

**How color sets work:** Each `.colorset/Contents.json` has a `colors` array with two entries:
- **No `appearances` key** → default/fallback (serves as light mode)
- **`appearances: [{appearance: "luminosity", value: "dark"}]`** → dark mode override

iOS uses most-specific-match: it checks for an explicit dark match, and falls back to the default entry otherwise.

**Auto-generated accessors:** Xcode auto-generates `Color` extensions from asset catalog color sets. Do NOT manually define `static let` properties on `Color` with the same names — this causes "ambiguous use" build errors. The file `Colors+DesignSystem.swift` only contains the `init(hex:)` helper; color accessors come from the asset catalog.

| Token | Dark Mode | Light Mode | Usage |
|-------|-----------|------------|-------|
| `backgroundPrimary` | #130914 | #fff7fb | Page backgrounds |
| `backgroundSecondary` | #1d0f22 | #ffeaf5 | Card backgrounds |
| `formBackgroundInactive` | #342d39 | #f0e4ed | Form field backgrounds |
| `textPrimary` | #ffffff | #241023 | Primary text |
| `textSecondary` | #f4d9f2 | #6b4a6a | Card titles, subtitles |
| `textMuted` | #b28bb8 | #a184a5 | Section headers, captions |
| `textOnAccent` | #130914 | #ffffff | Text on accent buttons |
| `accentPrimary` | #ff7aa2 | #ff4f8b | Buttons, links, tint |
| `accentSecondary` | #3a1e3f | #ffd4e6 | Selected/highlighted state |
| `accentTertiary` | #4ec8f4 | #4ec8f4 | Secondary accent (same both modes) |
| `statusSuccess` | #30d97a | #2bbf6a | Success messages |
| `statusWarning` | #ffc94a | #ffb020 | Warning messages |
| `statusError` | #ff5c70 | #e5484d | Error messages |

**Adding a new color:**
1. Create `Assets.xcassets/tokenName.colorset/Contents.json` with light (default) and dark entries
2. Use `Color.tokenName` or `.tokenName` in SwiftUI — the accessor is auto-generated
3. Do NOT add a manual `static let` to `Colors+DesignSystem.swift`

#### Typography (`Typography+DesignSystem.swift`)

| Font | Weight | Size | Line Height |
|------|--------|------|-------------|
| `.primary` | Bold | 32pt | 1.1 |
| `.heading1` | Semibold | 28pt | 1.13 |
| `.heading2` | Semibold | 24pt | 1.1 |
| `.heading3` | Medium | 20pt | 1.1 |
| `.subtitle` | Regular | 14pt | 1.1 |

#### Spacing, Radius, Sizes

See [Spacing Values](#spacing-values) above. Corner radii: `sm` 4pt, `md` 8pt, `lg` 12pt, `xl` 16pt.

#### View Modifiers (`ViewModifiers+DesignSystem.swift`)

**Typography:** `.primaryTextStyle()`, `.heading1Style()`, `.heading2Style()`, `.heading3Style()`, `.subtitleStyle()`, `.errorTextStyle()`, `.successTextStyle()`

**Containers:** `.cardStyle()` (backgroundSecondary + cornerRadius.md), `.pageBackground()` (backgroundPrimary), `.sectionContainer()` (standard padding)

**Interactive:** `.iconButtonStyle()` (44pt circle), `.primaryButtonStyle()` (full-width accent button)

## Swift 6 & Language Features

### Strict Concurrency

The project uses Swift 6 language mode with strict concurrency checking.

**Key Patterns:**
- `@MainActor` for UI-related classes (`BoopManager`, `BluetoothManager`, `LocationManager`)
- Swift `actor` for thread-safe data access (`UserDataStore`, `StorageCoordinator`)
- `@MainActor` closures for UI updates from background threads
- `nonisolated` delegate methods with `Task { @MainActor in ... }` for CoreLocation callbacks

### SwiftData with @Model Macro

**Critical Rule:** All stored properties in `@Model` classes must be `var`, never `let`.

**Why:** The `@Model` macro generates property wrappers for observation and persistence tracking, which requires mutable properties even if values never change at runtime.

**Common Error:**
```
Cannot expand accessor macro on variable declared with 'let';
this is an error in the Swift 6 language mode
```

**Fix:**
```swift
@Model
final class Contact {
    var uuid: UUID  // ✅ Use var, even though UUID won't change
    var displayName: String

    // NOT: let uuid: UUID  ❌
}
```

### Unused Parameter Warnings

When using `onChange(of:)` modifiers, replace unused parameters with `_`:

```swift
// ❌ Lint warning
.onChange(of: someValue) { oldValue, newValue in
    handleChange(newValue)
}

// ✅ No warning
.onChange(of: someValue) { _, newValue in
    handleChange(newValue)
}
```

## Design System Details

### Spacing Values

**File:** `DesignSystem/Spacing+DesignSystem.swift`

```swift
Spacing.none  // 0pt
Spacing.xs    // 4pt
Spacing.sm    // 8pt
Spacing.md    // 12pt
Spacing.lg    // 16pt
Spacing.xl    // 20pt
```

**Usage Guidelines:**
- Card padding: `Spacing.lg` (16pt)
- Vertical spacing between cards: `Spacing.md` (12pt)
- Section header padding: `.horizontal(Spacing.lg)` + `.vertical(Spacing.md)`
- Always use design system values, never hardcoded numbers

### View Modifiers

**File:** `DesignSystem/ViewModifiers+DesignSystem.swift`

```swift
.heading1Style()        // Large section headers
.heading2Style()        // Subsection headers
.heading3Style()        // Detail view subtitles
.primaryTextStyle()     // Main page titles
.cardStyle()            // Card backgrounds and styling
.pageBackground()       // Page-level background color
```

### Component Patterns

**Cards:**
- Use `BoopInteractionCard` for timeline items
- Use `ContactInteractionCard` for contact list items
- Always apply `.padding(.horizontal, Spacing.lg)` to cards in lists
- Add vertical spacing via `LazyVStack(spacing: Spacing.md)`

**Lists:**
- Use `LazyVStack` for large scrollable lists
- Set `spacing` parameter for vertical gaps
- Apply horizontal padding to individual items, not the stack

## Permissions

Declared in `Info.plist`:
- `NSBluetoothAlwaysUsageDescription`: Required for BLE advertising and scanning
- `NSBluetoothPeripheralUsageDescription`: Required for acting as BLE peripheral
- `NSLocationWhenInUseUsageDescription`: Required for path recording during interactions
- UWB permissions are automatically handled by Nearby Interaction framework
- Notification permissions are requested at app startup via `NotificationManager`

## Project Configuration

- **Deployment Target**: iOS 18.2
- **Swift Version**: Swift 6.0 (language mode)
- **Devices**: iPhone and iPad (universal)
- **Bundle ID**: `com.boop.boop-ios.aparna`
- **Team ID**: P3PR8G7GB9
- **Code Signing**: Automatic (requires Xcode configuration)

## Common Development Tasks

### Adding a New View

1. Create SwiftUI view file in appropriate location
2. Use design system spacing/colors (never hardcode values)
3. Add `@Query` for SwiftData models if needed
4. Apply standard view modifiers (`.pageBackground()`, etc.)
5. Add to navigation structure (tab, sheet, or NavigationLink)

### Working with SwiftData

1. Define models with `@Model` macro
2. Use `var` for all stored properties (even UUIDs)
3. Set up relationships with `@Relationship` attribute
4. Use `@Query` in views for automatic updates
5. Access `@Environment(\.modelContext)` for inserts/deletes

### Handling Boop Events

Persistence is handled entirely in `BoopManager` (not in views):
1. `BoopManager.didReceiveBoop()` finds/creates `Contact` and creates `BoopInteraction` via its own `ModelContext`
2. On BLE disconnect, `BoopManager.handleSessionEnd()` enriches the interaction with `endTimestamp` and `pathCoordinates`
3. If no boop happened during a session but it lasted >= 60 seconds, an interaction is auto-created
4. `BoopRangingView` observes `latestBoopEvent` only for overlay animation display
5. SwiftData automatically updates all `@Query` views (e.g. `BoopTimelineView`)

## Bug Tracking (Notion)

The project's bug tracker is a Notion database.

- **Database ID:** `31855bc6-997b-80f7-a3b5-d29f798adc90`
- **Data Source ID:** `31855bc6-997b-8143-978c-000ba690e1ae`

### Fetching a Bug by ID

Bugs use an auto-increment ID with the prefix `BUG-` (e.g., `BUG-1`, `BUG-12`). To look up a bug, search the database's data source using the numeric part of the ID:

```
Tool: mcp__notion__notion-search
query: "<bug title or keyword>"
data_source_url: "collection://31855bc6-997b-8143-978c-000ba690e1ae"
```

To fetch a specific bug by its `BUG-N` ID, first fetch the database, then find the entry whose `userDefined:ID` field matches the number N. You can also search by bug title keywords to find the relevant entry, then use `mcp__notion__notion-fetch` with the bug's page URL to get full details.

## Debugging Tips

### Build Errors

**"Cannot expand accessor macro":**
- Check all `@Model` classes for `let` declarations
- Change to `var` even if value is logically immutable

**"Ambiguous use of 'colorName'":**
- A manual `static let` on `Color` conflicts with the auto-generated accessor from the asset catalog color set
- Remove the manual definition — the asset catalog auto-generates `Color.tokenName` accessors

**"No such file or directory":**
- Ensure you're running `xcodebuild` from the directory containing `.xcodeproj`
- Use `cd ..` if you're in the `boop-ios/` source folder

**Code signing errors:**
- Check Team ID in Xcode project settings
- Ensure automatic signing is enabled
- Use `-allowProvisioningUpdates` flag for command-line builds

### Runtime Issues

**SwiftData not updating:**
- Verify `@Query` is used in view
- Check that models are inserted via `modelContext.insert()`
- Ensure container includes all model types in schema

**BLE not discovering:**
- Must use physical device (simulator has limited BLE)
- Check Bluetooth permissions in Settings
- Verify both devices are running the app
- Ensure `BluetoothManager` is properly initialized

**UWB ranging not working:**
- Requires two iPhone 11+ devices
- Devices must be connected via BLE first
- Check that UWB tokens are exchanged
- Verify `NISession` delegate is set
