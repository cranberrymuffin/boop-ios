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

`NotificationIntent` is standalone with no SwiftData relationships.
`NotificationIntent.entityUUID` is a loose UUID reference to a `Contact` (not a SwiftData `@Relationship`), used for contact reminder notifications.
