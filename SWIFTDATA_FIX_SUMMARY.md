# SwiftData Invalidation Crash Fix - Summary

## Problem
Fatal error: "This model instance was invalidated because its backing data could no longer be found the store" occurring in `Reminder.uuid.getter` and other SwiftData model property accessors.

## Root Cause
SwiftUI views, computed properties, closures, and async tasks were directly accessing SwiftData `@Model` instances (`Reminder`, `ReminderSchedule`, `DailyLogEntry`). When the store was reset, modified, or models were deleted, these references became invalidated, causing fatal crashes.

## Solution
Complete refactoring to eliminate ALL direct SwiftData model access in UI and async boundaries:

1. **Stable Identity**: Replaced UUID-based identity with `PersistentIdentifier` (SwiftData's native stable ID)
2. **View Models**: Created pure value type rows (`TodayRow`, `ReminderRow`) containing only primitive data
3. **Safe Re-fetch Pattern**: All actions capture only stable IDs, then re-fetch models on `@MainActor`
4. **Store Reset Handling**: Added `AppState` with `storeGeneration` token to force view rebuilds

## Files Changed

### Core Models
- **`MedVibe/Core/Models/Reminder.swift`**
  - Added `stableId: String` property (fallback stable identifier)
  - Added `fetchReminder(id: PersistentIdentifier, in:)` helper (preferred)
  - Added `fetchReminder(stableId: String, in:)` helper (fallback)
  - Kept legacy `fetchReminder(uuid: UUID, in:)` for backward compatibility

### View Models
- **`MedVibe/Features/Home/HomeView.swift`**
  - Updated `TodayRow` to use `PersistentIdentifier` instead of `UUID`
  - Updated `todayRows` computed property to snapshot `persistentModelID` early
  - Updated all actions (complete, snooze, skip, pause) to use `PersistentIdentifier` and safe re-fetch
  - Added `AppState` dependency for store reset handling

- **`MedVibe/Features/Reminders/RemindersView.swift`**
  - Updated `ReminderRow` to use `PersistentIdentifier` instead of `UUID`
  - Updated `reminderRows` computed property to snapshot `persistentModelID` early
  - Updated all actions (complete, pause, edit, delete) to use `PersistentIdentifier` and safe re-fetch
  - Added `AppState` dependency for store reset handling

### Services
- **`MedVibe/Core/Services/HistoryService.swift`**
  - Updated `backfillMissingLogs` to use `PersistentIdentifier` instead of `UUID`
  - Two-pass approach: extract IDs first, then re-fetch each reminder by ID
  - Updated `upsertLogEntry` and `removeLogForToday` to use `PersistentIdentifier`
  - Added concurrency protection (`isBackfilling` flag)

- **`MedVibe/Core/Services/NotificationService.swift`**
  - Updated `handleSnooze` to accept `PersistentIdentifier` instead of `UUID`
  - Updated `scheduleAllNotifications` to capture IDs first, then re-fetch each reminder
  - All handlers now use stable IDs and safe re-fetch pattern

### App Infrastructure
- **`MedVibe/App/AppState.swift`** (NEW)
  - Created `AppState` class with `storeGeneration` published property
  - `incrementStoreGeneration()` method for store reset handling

- **`MedVibe/App/MedVibeApp.swift`**
  - Added `AppState` as `@StateObject` and `@EnvironmentObject`
  - Updated store reset handling to increment `storeGeneration` and force app relaunch in DEBUG

- **`MedVibe/App/RootTabView.swift`**
  - Updated `performDailyMaintenance` to capture IDs first, then re-fetch reminders
  - Added `AppState` dependency
  - All reminder modifications now use safe re-fetch pattern

## Key Patterns Implemented

### 1. Row Snapshot Pattern
```swift
// In computed property (synchronous, on MainActor)
private var todayRows: [TodayRow] {
    _ = storeGeneration // Trigger rebuild on store reset
    var rows: [TodayRow] = []
    for reminder in allReminders {
        // CRITICAL: Capture PersistentIdentifier FIRST
        let persistentId = reminder.persistentModelID
        let stableId = reminder.stableId
        // ... capture all other properties ...
        rows.append(TodayRow(id: persistentId, stableId: stableId, ...))
    }
    return rows
}
```

### 2. Safe Re-fetch Pattern
```swift
// In action handler
let reminderId = row.id
let reminderStableId = row.stableId

Task { @MainActor in
    guard let r = fetchReminder(id: reminderId, in: modelContext) 
          ?? fetchReminder(stableId: reminderStableId, in: modelContext) else {
        #if DEBUG
        print("⚠️ Model missing (likely reset/deleted) — ignoring action")
        #endif
        return
    }
    // ... perform action with re-fetched model ...
}
```

### 3. Two-Pass Fetch Pattern (for batch operations)
```swift
// First pass: Extract IDs only
var reminderIds: [PersistentIdentifier] = []
for reminder in allReminders {
    reminderIds.append(reminder.persistentModelID)
}

// Second pass: Re-fetch each by ID
for id in reminderIds {
    guard let reminder = fetchReminder(id: id, in: modelContext) else {
        continue // Skip invalidated models
    }
    // ... process reminder ...
}
```

## Testing Checklist

### Manual Tests Required:

1. **Rapid Actions on Repeating Reminders**
   - Create repeating reminder (multiple weekdays)
   - Rapidly complete → uncomplete → skip → pause → resume
   - Verify no crashes

2. **Rapid Actions on One-Time Reminders**
   - Create one-time reminder
   - Rapidly complete → uncomplete
   - Verify no crashes

3. **Delete While Viewing**
   - Open Today screen
   - Delete a reminder from Reminders list (different tab)
   - Verify Today screen doesn't crash

4. **Store Reset (DEBUG)**
   - Trigger store reset (modify schema or delete store file)
   - Verify app handles reset gracefully
   - In DEBUG: app should fatalError with "Store reset, please rerun"
   - After rerun: verify no stale model references

5. **Notification Actions**
   - Kill app
   - Receive notification
   - Tap notification / snooze / complete actions
   - Verify no crashes

6. **Concurrent Operations**
   - Perform multiple actions rapidly
   - Verify no race conditions or crashes

## Debug Logging

All actions now log when models are missing:
```
⚠️ Model missing (likely reset/deleted) — ignoring [action name]
```

This helps identify when store resets occur or models are deleted.

## Migration Notes

- Existing reminders will have `stableId` auto-generated on next access (via default init parameter)
- `uuid` property remains for backward compatibility but is no longer used in runtime paths
- All new code should use `PersistentIdentifier` via `persistentModelID`

## Remaining UUID References

The only remaining `.uuid` references are:
- In `Reminder.swift` model definition (stored property - safe)
- In legacy `fetchReminder(uuid:in:)` helper (kept for compatibility, not used in new code)

All runtime property access now uses `PersistentIdentifier` or `stableId`.
