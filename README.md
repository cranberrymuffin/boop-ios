# Boop iOS

An offline social iOS app that enables users to discover, connect, and interact with nearby friends using Ultra-Wideband (UWB) and Bluetooth Low Energy (BLE) technology. When users come within touching distance, they can "boop" each other to create connections and track interactions with location-aware path recording.

## Overview

Boop is a peer-to-peer proximity app that operates entirely offline. It uses BLE for device discovery and communication, combined with UWB for precise distance measurement (down to centimeter-level accuracy). The app enables spontaneous social interactions through physical proximity rather than traditional networking. Each interaction records the path the user traveled during the BLE session, displayed as a map polyline in the timeline.

## Architecture

### Key Services

#### 1. **BoopManager** (`BoopManager.swift`)
The core orchestration layer that manages the entire boop interaction flow, persistence, and location enrichment.

- **Responsibilities:**
  - Subscribes to UWB distance updates and automatically triggers boops when devices enter touching range
  - Manages per-peer cooldown to prevent duplicate boops
  - Delegates all persistence to repository singletons (`ContactRepository`, `BoopInteractionRepository`)
  - Tracks BLE sessions (connect/disconnect) and enriches interactions with path coordinates from `LocationManager`
  - Auto-creates interactions for sessions lasting >= 60 seconds even without a proximity boop
  - Coordinates between BluetoothManager, LocationManager, and UI layer
  - Implements `BoopDelegate` protocol to receive boop events

- **Key Properties:**
  - `latestBoopEvent: BoopEvent?` — most recently completed boop event (triggers UI)
  - `deviceSessionStart: [UUID: Date]` — tracks when each BLE session began
  - `peripheralToSenderUUID: [UUID: UUID]` — maps peripheral UUIDs to sender UUIDs

- **Location:** `/boop-ios/BoopManager.swift`

#### 2. **BluetoothManager** (`BluetoothManager.swift`)
Manages dual-mode BLE operations (peripheral + central) and coordinates UWB ranging.

- **Responsibilities:**
  - Simultaneous BLE advertising (peripheral) and scanning (central)
  - Automatic connection management for discovered devices
  - UWB token exchange between devices
  - Distance categorization (InRange, ApproxTouching, OutOfRange)
  - Device lifecycle management (discovery, connection, disconnection)

- **Key Properties:**
  - `nearbyDevices`: Dictionary of discovered devices with their distance categories
  - `connectedPeripherals`: Active BLE peripheral connections
  - `localDeviceUUID`: Persistent unique identifier for this device

- **Integration:**
  - Delegates to `BluetoothManagerServiceImpl` for BLE operations
  - Coordinates with `UWBManager` for distance measurements
  - Implements `BluetoothServiceDelegate` and `UWBManagerDelegate`

- **Location:** `/boop-ios/Bluetooth/BluetoothManager.swift:8`

#### 3. **BluetoothManagerServiceImpl** (`BluetoothManagerService.swift`)
Low-level BLE service handling both peripheral and central roles.

- **Responsibilities:**
  - Manages `CBCentralManager` (scanning for peripherals)
  - Manages `CBPeripheralManager` (advertising as a peripheral)
  - Handles GATT service/characteristic discovery and operations
  - Processes incoming BLE messages via binary protocol
  - Exchanges UWB tokens between devices

- **BLE Configuration:**
  - Service UUID: `D3A42A7C-DA0E-4D2C-AAB1-88C77E018A5F`
  - Message Characteristic UUID: `D3A42A7D-DA0E-4D2C-AAB1-88C77E018A5F`
  - UWB Token Characteristic UUID: `D3A42A7E-DA0E-4D2C-AAB1-88C77E018A5F`

- **Location:** `/boop-ios/Bluetooth/BluetoothManagerService.swift:42`

#### 4. **UWBManager** (`UWBManager.swift`)
Handles Ultra-Wideband ranging for precise distance measurement.

- **Responsibilities:**
  - Manages `NISession` (Nearby Interaction framework)
  - Tracks nearby objects with distance and direction data
  - Provides distance-based proximity detection
  - Handles UWB discovery token exchange

- **Distance Thresholds:**
  - `touchingDistance`: 7cm (0.07m) - for "boop" interactions
  - `maxDistance`: 100cm (1.0m) - maximum proximity range

- **Key Methods:**
  - `isNearby(deviceID:)`: Checks if device is within 50cm
  - `isApproximatelyTouching(deviceID:)`: Checks if device is within 5cm
  - `startRanging(to:peerToken:)`: Initiates UWB ranging session
  - `stopRanging(to:)`: Terminates ranging session

- **Location:** `/boop-ios/Bluetooth/UWBManager.swift:47`

#### 5. **UserDataStore** (`DataStore/UserDataStore.swift`)
Actor-based UserDefaults wrapper. Its only remaining role is persisting the local device UUID for BLE identity.

- **Responsibilities:**
  - Persists the local device UUID (`com.boop.localDeviceUUID`)
  - Thread-safe data access via Swift actor

- **Note:** All profile data (name, birthday, bio, avatar, gradient colors) is stored exclusively in SwiftData via repository singletons.

- **Location:** `/boop-ios/DataStore/UserDataStore.swift`

#### 6. **Model Repositories** (`Model/ModelRepository/`)
`@MainActor` singleton classes providing a clean data access API for all SwiftData operations. All repositories share a single `ModelContext` owned by `ModelContextProvider.shared`, and auto-save after every mutation. No code outside the repositories should use `FetchDescriptor` or `modelContext` directly.

- **`ModelContextProvider.shared`** — owns the single shared `ModelContext`, initialized with the `ModelContainer` at app startup
- **`ContactRepository.shared`** — find, upsert, delete contacts
- **`BoopInteractionRepository.shared`** — create interactions, check duplicates, find latest, enrich with session data
- **`UserProfileRepository.shared`** — get current profile, save profile

- **Initialized in:** `boop_iosApp.swift` via `ModelContextProvider.shared.setModelContainer(container)`

#### 7. **LocationManager** (`LocationManager.swift`)
CoreLocation-based continuous location tracker with path recording.

- **Responsibilities:**
  - Maintains a rolling buffer of up to 3,500 timestamped coordinates
  - Filters GPS noise (minimum 1.0m between recorded points)
  - Provides time-windowed path retrieval for BLE session enrichment
  - Periodically reverse-geocodes current location

- **Key Methods:**
  - `requestPermissionIfNeeded()`: Requests when-in-use authorization
  - `startTracking()` / `stopTracking()`: Controls location updates
  - `getLocations(from:to:)`: Returns coordinates within a time window
  - `snapshotPath()`: Returns full buffer as coordinate array
  - `reverseGeocodeCurrentLocation()`: Human-readable location name

- **Location:** `/boop-ios/LocationManager.swift`

#### 8. **StorageCoordinator** (`StorageCoordinator.swift`)
Async storage initialization coordinator to prevent race conditions.

- **Responsibilities:**
  - Ensures storage directories exist before database access
  - Coordinates async initialization with continuation-based waiting
  - Prevents race conditions between directory creation and SwiftData access

- **Location:** `/boop-ios/StorageCoordinator.swift:5`

### Data Storage & Persistence

#### **SwiftData** (Primary Database)

The app uses Apple's SwiftData framework for local persistence. All `@Model` classes live in `Model/PersistentModel/`.

**Models:**

1. **Contact** (`Model/PersistentModel/Contact.swift`)
   - `uuid: UUID` - Unique identifier for the contact (matches sender's device UUID)
   - `displayName: String` - User's display name
   - `birthday: Date?`, `bio: String?` - Profile fields received via BLE
   - `gradientColorsData: [String]` - Gradient colors stored as strings
   - `interactions: [BoopInteraction]` - Array of boop interactions (cascade delete)

2. **UserProfile** (`Model/PersistentModel/UserProfile.swift`)
   - `name: String` - User's display name
   - `createdAt: Date` - Profile creation timestamp
   - `avatarData: Data?` - Profile photo (selected via PhotosPicker)
   - `birthday: Date?`, `bio: String?` - Optional profile fields
   - `gradientColorsData: [String]` - Gradient colors stored as strings

3. **BoopInteraction** (`Model/PersistentModel/BoopInteraction.swift`)
   - `id: UUID` - Unique interaction identifier
   - `title: String` - Interaction title (contact's name)
   - `location: String` - Reverse-geocoded location name
   - `timestamp: Date` - When the boop occurred
   - `endTimestamp: Date?` - When the BLE session ended
   - `imageData: [Data]` - Optional photos from the interaction
   - `pathCoordinatesData: Data?` - JSON-encoded path traveled during interaction
   - `pathCoordinates: [CLLocationCoordinate2D]` - Computed property for encode/decode
   - `contact: Contact?` - Inverse relationship

4. **NotificationIntent** (`Model/PersistentModel/NotificationIntent.swift`)
   - `id: UUID` - Unique notification identifier
   - `typeIdentifier: NotificationTypeIdentifier` - `.contactReminder` or `.weeklyPlanning`
   - Trigger config: kind, interval, weekday, hour, minute
   - `isActive: Bool` - Whether the notification schedule is enabled

**Configuration:**
- Container setup: `/boop-ios/boop_iosApp.swift`
- Schema: `[Contact.self, UserProfile.self, BoopInteraction.self, NotificationIntent.self]`
- Storage: Persistent (not in-memory)
- Directory initialization: Handled by `StorageCoordinator`

#### **UserDefaults** (Device Identity Only)

UserDefaults is used only for the local device UUID. All profile data is stored in SwiftData.

**Keys** (`UserDefaults/UserDefaultsKeys.swift`):
- `com.boop.localDeviceUUID`: Persistent device UUID for BLE identity

**Access Pattern:**
- Accessed through `UserDataStore` actor for thread safety

#### **Data Transfer Models**

**Non-persisted models for runtime state:**

1. **BluetoothMessage** (`model/BluetoothMessage.swift`)
   - Binary protocol for BLE communication
   - Message types: connectionRequest, connectionAccept, connectionReject, disconnect, boop, boopRequest, presence
   - Includes sender UUID, message type, display name, and payload
   - Max display name: 50 bytes (UTF-8)

2. **NearbyDevice** (`model/NearbyDevice.swift`)
   - UI representation of discovered devices
   - Contains: id, displayName, distance category, selection state

3. **Boop** (`model/Boop.swift`)
   - Represents a completed boop event
   - Contains: senderUUID, displayName

4. **ConnectionRequest/Response** (`model/ConnectionRequest.swift`, `model/ConnectionResponse.swift`)
   - Connection handshake state models

### Views & Navigation

#### **Entry Point**

**boop_iosApp** (`boop_iosApp.swift`)
- App entry point decorated with `@main`
- Initializes SwiftData schema and model container (Contact, UserProfile, BoopInteraction, NotificationIntent)
- Sets up `StorageCoordinator`
- Creates global `BoopManager` and `LocationManager` as environment objects
- Injects `ModelContainer` and `LocationManager` into `BoopManager`
- Requests location and notification permissions
- Schedules weekly planning notification
- Handles deep links (`boop://timeline` or `boop://timeline/{interactionID}`)
- Shows loading screen while container initializes
- Navigates to `RootView` once ready

#### **Root Navigation**

**RootView** (`Views/RootView.swift`)
- Simple wrapper that passes tab selection bindings to `MainTabView`
- No longer checks for profile existence (profile check moved to ProfileView)

#### **Main Interface**

**MainTabView** (`MainTabView.swift`)
- Root tab container for authenticated users
- **Tabs:**
  1. **Timeline** (`BoopTimelineView`) - Tab icon: `clock.fill`
  2. **Boop** (`BoopRangingView`) - Tab icon: `hand.tap.fill`
  3. **Contacts** (`ContactsView`) - Tab icon: `person.2`
  4. **You** (`ProfileView`) - Tab icon: `person.crop.circle`

#### **Primary Views**

1. **BoopTimelineView** (`BoopTimelineView.swift:11`)
   - **Purpose:** Chronological timeline of all boop interactions
   - **Features:**
     - Dynamic time-based section headers ("Today", "Yesterday", "2 hours ago", etc.)
     - Auto-updating relative timestamps using `RelativeDateTimeFormatter`
     - Grouped interactions with headers that recalculate on every render
     - Animated boop overlay when new interactions occur
     - Navigation to detailed interaction view
   - **Data Source:** SwiftData `@Query` for `BoopInteraction` models (sorted by timestamp, newest first)
   - **Technical Details:**
     - Uses `RelativeDateTimeFormatter` with `.full` units style
     - Groups minute/hour-level timestamps under "Today" to reduce header granularity
     - Headers display only when transitioning between different time periods
     - Real-time event broadcasting from `BoopManager.latestBoopEvent`

2. **ContactsView** (`ContactsView.swift`)
   - **Purpose:** Display list of saved contacts
   - **Features:**
     - Scrollable list of contact cards
     - Swipe-to-delete functionality
   - **Navigation:**
     - `NavigationLink` push → `ContactDetailView` (when contact tapped)
   - **Data Source:** SwiftData `@Query` for `Contact` models

3. **BoopRangingView** (`Views/BoopRangingView.swift`)
   - **Purpose:** Automatic proximity-based boop detection
   - **Features:**
     - `ProgressView` shown while scanning for nearby devices
     - Fully automatic boop: no manual selection required
     - When a peer enters UWB touching range (≤7cm), a `.boop` BLE message is sent automatically
     - Animated boop success overlay showing display name
     - Debug controls for simulating device connections and sessions
   - **Data Source:**
     - `BoopManager.latestBoopEvent` for boop event UI overlay
   - **Note:** Persistence is handled entirely by `BoopManager`, not by this view

4. **ProfileSetupView** (`Views/ProfileSetupView.swift`)
   - **Purpose:** User profile creation and editing
   - **Modes:**
     - Setup mode (first launch): Requires name, birthday, and bio
     - Edit mode (from ProfileView): Only requires name
   - **Features:**
     - `PhotosPicker` for profile photo selection (stored as `Data` in `UserProfile.avatarData`)
     - Circular avatar preview with "+" overlay for editing
     - Name, birthday (DatePickerField), bio (StyledTextField)
     - Gradient color picker via `DisplayColorPickerSheet`
     - AnimatedMeshGradient background
   - **Data:** Creates `UserProfile` model and passes to `onSave` callback. Profile is saved to SwiftData via `ModelContext` in the parent view.

5. **ProfileView** (`Views/ProfileView.swift`)
   - **Purpose:** Display and edit the user's profile
   - **States:** `loadingProfile`, `editingProfile`, `noProfile`, `displayProfile`
   - **Features:**
     - Fetches profile from SwiftData via `modelContext.fetch(FetchDescriptor<UserProfile>)`
     - Display mode: AnimatedMeshGradient background + ProfileDisplayCard with avatar
     - Edit mode: Embeds ProfileSetupView with current profile data
     - Saves updated profile via `UserProfileRepository.shared.save()`

6. **ContactDetailView / BoopHistoryView** (in `Views/ContactDetailView.swift`)
   - **Purpose:** Display a contact's info and interaction history with them
   - **Features:**
     - Contact profile header
     - Chronological list of all boop interactions with this contact
     - Shows timestamp, location, and path map for each interaction
   - **Data Source:** `Contact.interactions` array via `BoopInteractionTimelineBody`

#### **Reusable Components**

Located in `boop-ios/Components/`:

- **BoopInteractionCard**: Displays individual boop interaction details with title, location, relative time, and thumbnails
- **BoopInteractionTimelineBody**: Reusable timeline body (section headers + cards); shared by `BoopTimelineView` and `ContactDetailView`. Also contains `BoopInteractionDetailView` with map display for path coordinates.
- **ContactInteractionCard**: Displays contact summary with recent interaction info
- **ProfileDisplayCard**: Profile info card with avatar thumbnail, display name, birthday, and bio

Located in `boop-ios/Components/Gradient/`:

- **StyledTextField**: Consistent text field styling
- **AnimatedMeshGradient**: Animated 3x3 MeshGradient background for profiles
- **DatePickerField**: Two-step date+time picker component
- **DisplayColorPickerSheet**: Gradient color selection sheet

#### **Design System**

Located in `/boop-ios/DesignSystem/`:

- **Colors+DesignSystem**: Centralized color palette
- **Typography+DesignSystem**: Text style definitions
- **Spacing+DesignSystem**: Consistent spacing values
- **Sizes+DesignSystem**: Standard size constants
- **Radius+DesignSystem**: Border radius values
- **ViewModifiers+DesignSystem**: Reusable view modifiers (card style, page background, etc.)

## Interaction Flow

### Boop Sequence

1. **Discovery:**
   - User A and User B open `BoopRangingView`
   - `BluetoothManager` advertises and scans simultaneously
   - Both devices discover each other via BLE

2. **Connection:**
   - Devices automatically connect when discovered
   - Exchange UWB tokens via BLE characteristics
   - `UWBManager` starts ranging session

3. **Proximity Detection:**
   - UWB provides real-time distance measurements
   - Devices categorized: InRange (≤100cm), ApproxTouching (≤7cm)
   - Both devices see each other via Combine-published `nearbyDevices`

4. **Automatic Boop:**
   - When `BoopManager` detects a peer entering `ApproxTouching` state (≤7cm)
   - Automatically sends a `.boop` BLE message (no user action needed)
   - Receiving side's `BoopManager.didReceiveBoop(from:displayName:)` fires
   - `ContactRepository.findOrCreate()` upserts the contact, `BoopInteractionRepository.create()` inserts the interaction (both auto-save)
   - Sets `latestBoopEvent`, triggering UI overlay in `BoopRangingView`

5. **Session End & Location Enrichment:**
   - When BLE device disconnects, `BoopManager.handleSessionEnd()` fires
   - Retrieves path coordinates from `LocationManager.getLocations(from:to:)` for the session time window
   - `BoopInteractionRepository.enrichWithSessionData()` updates the interaction with `endTimestamp`, `pathCoordinates`, and location (auto-saves)
   - If no boop occurred but session lasted >= 60 seconds, `BoopInteractionRepository.create()` auto-creates an interaction

6. **Timeline Display:**
   - `@Query` automatically picks up new/updated interactions
   - `BoopInteractionCard` displays interaction with location and relative time
   - `BoopInteractionDetailView` shows path on a `Map` with start/end pins and polyline

## Technical Details

### BLE Protocol

**Service Architecture:**
- One primary service: Boop Service (`D3A42A7C-DA0E-4D2C-AAB1-88C77E018A5F`)
- Two characteristics:
  1. Message Characteristic (write): For sending boop messages, connection requests, etc.
  2. UWB Token Characteristic (read/write): For exchanging UWB discovery tokens

**Message Format:**
```
[UUID: 16 bytes][MessageType: 1 byte][DisplayNameLength: 1 byte][DisplayName: variable][PayloadLength: 2 bytes][Payload: variable]
```

**Message Types:**
- `0x01`: connectionRequest
- `0x02`: connectionAccept
- `0x03`: connectionReject
- `0x05`: disconnect
- `0x06`: boop (automatic proximity-triggered boop)
- `0x07`: boopRequest (manual boop request, reserved)
- `0x08`: presence (announce display name when connecting)
- `0x09`: stoppedRanging (UWB session ended)

### UWB Integration

**Framework:** Apple's Nearby Interaction (NearbyInteraction framework)

**Capabilities:**
- Precise distance measurement (±5cm accuracy)
- Direction measurement (when supported)
- Peer-to-peer ranging via discovery tokens

**Token Exchange:**
1. Device A connects to Device B via BLE
2. Device A reads Device B's UWB token characteristic
3. Device A writes its own UWB token to Device B
4. Both devices call `NISession.run()` with peer token
5. `NISessionDelegate` callbacks provide distance updates

### Date & Time Formatting

**Timeline Headers** (`BoopTimelineView.swift:23-43`)

The app uses `RelativeDateTimeFormatter` for dynamic, human-readable time displays:

```swift
let formatter = RelativeDateTimeFormatter()
formatter.unitsStyle = .full  // "2 hours ago" vs "2 hr. ago"
let text = formatter.localizedString(for: date, relativeTo: Date())
```

**Key Implementation Details:**
- **Dynamic Recalculation:** Headers recalculate on every view render to stay current
- **Granularity Control:** Minutes/hours are grouped under "Today" to prevent excessive header fragmentation
- **Sequential Display:** Headers appear only when transitioning between time periods
- **No Pre-grouping:** Avoid bucketing timestamps into fixed intervals (prevents stale headers)

**Best Practices:**
- Use `RelativeDateTimeFormatter` instead of `Date.RelativeFormatStyle` when you need more control
- For timeline/feed UIs, calculate headers per-item rather than pre-grouping into dictionaries
- Sanitize formatter output to group fine-grained units (e.g., "12 minutes ago" → "Today")
- Let SwiftUI re-render handle updates rather than manual refresh timers

**Alternative Formatters:**
- `Date.RelativeFormatStyle`: Simpler API but no granularity control
- `DateComponentsFormatter`: Good for durations/intervals, not relative times
- `Date.FormatStyle`: For absolute date/time displays

### Thread Safety

- `BoopManager`: `@MainActor` - all UI updates and persistence on main thread
- `BluetoothManager`: `@MainActor` - Bluetooth state changes on main thread
- `LocationManager`: `@MainActor` - location updates forwarded via `Task { @MainActor in ... }`
- `UserDataStore`: Swift actor - automatic thread-safe data access
- `StorageCoordinator`: Swift actor - safe async initialization

### Performance Optimizations

1. **SwiftData Queries:** `@Query` provides efficient, reactive data access
2. **Async Storage Init:** StorageCoordinator prevents blocking UI during setup
3. **Lazy Loading:** UI components use `LazyVStack` for large lists
4. **Combine Publishers:** Reactive updates for device discovery and distance changes
5. **Stale Device Removal:** Automatic cleanup of disconnected devices
6. **Location Buffer:** Rolling buffer with distance filter prevents GPS noise accumulation

## Build & Run

### Requirements

- Xcode 15.0+
- iOS 18.2+
- Physical device with UWB support (iPhone 11 or later)
- Bluetooth and UWB permissions

### Build Commands

```bash
# Build for debug
xcodebuild -scheme boop-ios -configuration Debug build

# Build for simulator
xcodebuild -scheme boop-ios -destination 'platform=iOS Simulator,name=iPhone 15' build

# Build for device
xcodebuild -scheme boop-ios -destination 'generic/platform=iOS' build

# Clean
xcodebuild -scheme boop-ios clean
```

### Running

1. Open `boop-ios.xcodeproj` in Xcode
2. Select a physical device (UWB requires real hardware)
3. Ensure code signing is configured (Team: P3PR8G7GB9)
4. Run with Cmd+R

### Permissions

Declared in `Info.plist`:
- `NSBluetoothAlwaysUsageDescription`: Required for BLE advertising and scanning
- `NSBluetoothPeripheralUsageDescription`: Required for acting as BLE peripheral
- `NSLocationWhenInUseUsageDescription`: Required for path recording during interactions
- Local notification permissions requested at app startup

## Project Structure

```
boop-ios.xcodeproj/
boop-ios/
├── boop_iosApp.swift              # App entry point + deep linking
├── BoopManager.swift              # Core boop coordinator + persistence + location
├── LocationManager.swift          # CoreLocation tracking with path buffer
├── StorageCoordinator.swift       # Async storage init
│
├── Views/                         # All view files
│   ├── RootView.swift             # Root navigation wrapper
│   ├── MainTabView.swift          # Main tab container (4 tabs)
│   ├── BoopTimelineView.swift     # Timeline feed
│   ├── BoopRangingView.swift      # Proximity-based auto-boop
│   ├── BoopInteractionListView.swift  # Demo/preview list view
│   ├── ContactsView.swift         # Contacts list
│   ├── ContactDetailView.swift    # Contact detail + boop history
│   ├── ProfileView.swift          # Profile display/edit (uses ModelContext)
│   ├── ProfileSetupView.swift     # Onboarding flow (with PhotosPicker)
│   ├── AddManualBoopView.swift    # Manual boop entry sheet
│   └── LiveActivityManager.swift  # Live Activity management
│
├── Bluetooth/                     # BLE & UWB services
│   ├── BluetoothManager.swift
│   ├── BluetoothManagerService.swift
│   ├── UWBManager.swift
│   └── UWBService.swift
│
├── Model/                         # Data models
│   ├── PersistentModel/           # SwiftData @Model classes
│   │   ├── Contact.swift
│   │   ├── UserProfile.swift
│   │   ├── BoopInteraction.swift  # Includes path coordinate storage
│   │   └── NotificationIntent.swift
│   ├── ModelRepository/           # Singleton data access layer
│   │   ├── ModelContextProvider.swift  # Shared ModelContext owner
│   │   ├── ContactRepository.swift
│   │   ├── BoopInteractionRepository.swift
│   │   └── UserProfileRepository.swift
│   ├── Boop.swift                 # Boop + BoopEvent value types
│   ├── BluetoothMessage.swift     # Binary BLE protocol
│   ├── NearbyDevice.swift         # UI model
│   ├── ConnectionRequest.swift
│   └── ConnectionResponse.swift
│
├── DataStore/                     # Data access layer
│   ├── UserDataStore.swift        # UserDefaults actor (local device UUID)
│   └── UserDefaults/
│       ├── UserDefaultsKeys.swift
│       └── UserDefaultsUtility.swift
│
├── Notifications/                 # Local notification infrastructure
│   ├── NotificationManager.swift
│   ├── NotificationScheduler.swift
│   ├── NotificationBuilder.swift
│   ├── NotificationTrigger.swift
│   └── NotificationType.swift
│
├── Components/                    # Reusable UI components
│   ├── BoopInteractionCard.swift  # Card with map support
│   ├── BoopInteractionTimelineBody.swift  # Timeline body + detail view with map
│   ├── ContactInteractionCard.swift
│   ├── ProfileDisplayCard.swift   # Profile card with avatar display
│   └── Gradient/
│       ├── AnimatedMeshGradient.swift
│       ├── StyledTextField.swift
│       ├── DatePickerField.swift
│       └── DisplayColorPickerSheet.swift
│
├── DesignSystem/                  # Design tokens & styles
│   ├── Colors+DesignSystem.swift
│   ├── Typography+DesignSystem.swift
│   ├── Spacing+DesignSystem.swift
│   ├── Sizes+DesignSystem.swift   # Includes MapSize tokens
│   ├── Radius+DesignSystem.swift
│   └── ViewModifiers+DesignSystem.swift
│
├── Utilities/
│   └── StringSanitization.swift
│
└── Widgets/                       # Reserved, currently empty

BoopLiveActivity/                  # Live Activity widget extension
├── BoopLiveActivityLiveActivity.swift
├── BoopLiveActivityBundle.swift
└── Info.plist

Shared/                            # Code shared between app and widget
└── BoopLiveActivityAttributes.swift

design-tokens/                     # Figma design token JSON files
├── colors.json
├── typography.json
├── spacing.json
├── radius.json
└── text.json
```

## Future Enhancements

- Photo sharing during boop interactions
- Group boop functionality
- Privacy controls and blocking
- Export/backup contact data
- Analytics for boop frequency and patterns
