# Data Model

```mermaid
erDiagram
    Contact {
        UUID uuid
        String displayName
        Date birthday
        String bio
        Data avatarData
        String[] gradientColorsData
    }

    BoopInteraction {
        UUID id
        String location
        Date timestamp
        Date endTimestamp
        Data[] imageData
        Data pathCoordinatesData
        String notes
    }

    UserProfile {
        String name
        Date createdAt
        Date birthday
        String bio
        Data avatarData
        String[] gradientColorsData
    }

    NotificationIntent {
        UUID id
        String typeIdentifier
        UUID entityUUID
        String title
        String body
        Bool isActive
        Date createdAt
        Date updatedAt
        String triggerKind
        Int triggerWeekday
        Int triggerHour
        Int triggerMinute
    }

    Contact ||--o{ BoopInteraction : "cascade delete"
```

`UserProfile` and `NotificationIntent` are standalone with no SwiftData relationships.
`NotificationIntent.entityUUID` is a loose UUID reference to a `Contact` (not a SwiftData `@Relationship`), used for contact reminder notifications.
