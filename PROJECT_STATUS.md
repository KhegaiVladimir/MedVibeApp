# MedVibe - Current Project Status

## Project Overview
MedVibe is a production-grade iOS health reminder application built with SwiftUI + SwiftData. The app helps users manage health-related routines (medications, treatments, therapy exercises, medical checkups) with reliable local notifications.

**Tech Stack:**
- Swift
- SwiftUI
- SwiftData (NOT CoreData directly)
- UNUserNotificationCenter for local notifications
- iOS 17+

---

## ✅ Completed Features

### 1. Data Models (SwiftData)

#### Reminder Model
- `title: String` - Reminder title
- `note: String?` - Optional note
- `date: Date` - Next occurrence date (for repeating) or reminder date (for one-time)
- `isEnabled: Bool` - Active/inactive state (NOT completion status)
- `source: String` - Source identifier
- `notificationId: String` - Unique ID for UNUserNotificationCenter
- `completedOn: Date?` - Daily completion tracking (nil = not completed today)
- `schedule: ReminderSchedule?` - Optional relationship for repeating reminders

**Key Methods:**
- `isRepeating: Bool` - Checks if reminder has active schedule
- `computeNextOccurrence() -> Date?` - Computes next occurrence from current date
- `isDoneToday(now:) -> Bool` - Checks if completed today
- `setDoneToday(_:now:)` - Sets completion status for today
- `resetDoneStatusIfNeeded(now:)` - Resets completion if new day

#### ReminderSchedule Model
- `hour: Int` - Hour (0-23)
- `minute: Int` - Minute (0-59)
- `weekdays: [Int]` - Selected weekdays (1=Sunday, 7=Saturday)
- `isEnabled: Bool` - Schedule active state
- `endDate: Date?` - Optional end date (nil = never ends)

**Key Methods:**
- `nextOccurrence(from:) -> Date?` - Computes next occurrence from reference date
- `isActive(relativeTo:) -> Bool` - Checks if schedule is still active

### 2. Notification System

#### NotificationService
Fully implemented service for managing local notifications:

**Permission Management:**
- `requestAuthorization() async -> Bool` - Requests notification permissions
- `checkAuthorizationStatus() async -> UNAuthorizationStatus` - Checks current status

**Scheduling:**
- `scheduleNotification(for:) async` - Schedules notification for reminder
- `scheduleAllNotifications(for:) async` - Schedules all active reminders
- `cancelNotification(for:)` - Cancels notification (removes pending + delivered)
- `cancelAllNotifications()` - Cancels all notifications

**Notification Actions:**
- **Complete**: Marks reminder as completed today, advances next occurrence for repeating reminders
- **Snooze**: Clears completion, reschedules for +10 minutes (preserves schedule for repeating)

**Features:**
- Handles past dates by computing next occurrence
- Respects end dates for repeating reminders
- Removes both pending and delivered notifications on cancel
- No static badge numbers (badge not set)

### 3. UI Components

#### RemindersView
- Lists all reminders sorted by date
- Card-based design with visual completion status
- Swipe actions: Edit (left swipe) and Delete (right swipe)
- Toggle buttons:
  - Completion toggle (checkmark) - marks done/not done for today
  - Active/inactive toggle (bell icon) - enables/disables reminder
- Empty state when no reminders
- Shows schedule info: "Every Mo We Fr at 08:30", "Next: Jan 14"
- Displays end date only if set

#### AddReminderView
- Form-based UI for creating/editing reminders
- Supports both one-time and repeating reminders
- For one-time: Date & Time picker
- For repeating:
  - Start date picker
  - Time picker
  - Weekday selection (7 chips: Su Mo Tu We Th Fr Sa)
  - Optional end date
- Clear labels: "Repeats every week", "Repeats indefinitely"
- Edit mode: Pre-fills all fields from existing reminder
- Computes first occurrence automatically for repeating reminders

### 4. Core Logic

#### Daily Completion System
- **Default state**: All new reminders are NOT completed (`completedOn = nil`)
- **Completion**: Stored in `completedOn: Date?` (separate from `isEnabled`)
- **Daily reset**: Automatically resets completion status on new day
- **Reset logic**: Called on app launch in `RootTabView.task`
- **Works offline**: Uses date comparison, doesn't require app to be opened daily

#### Repeating Reminders Logic
- **Semantics**: "Repeats every week" means indefinitely (not "this week only")
- **Next occurrence**: Computed from current date, not stored date
- **Schedule preservation**: Snooze doesn't break weekly schedule
- **End date**: Optional, when set, reminders stop after that date
- **Date updates**: Automatically updates `reminder.date` to next occurrence

#### Notification Logic
- **One notification per reminder**: Uses `notificationId` as identifier
- **Scheduling**: Always schedules for `reminder.date` (next occurrence)
- **Past dates**: Automatically computes next occurrence before scheduling
- **Complete action**: For repeating, advances to next occurrence and reschedules
- **Snooze action**: Temporary +10 min delay, then continues normal schedule

### 5. Data Persistence

#### SwiftData Store
- Location: `Application Support/MedVibe/default.store`
- Migration handling: In DEBUG mode, automatically resets store on migration failure
- Cascade deletion: Deleting reminder automatically deletes schedule
- Store files cleanup: Removes .store, .wal, and .shm files on reset

### 6. Design System

#### DesignSystem.swift
- Color palette: Primary, accent, status colors
- Typography: Rounded system fonts with consistent weights
- Spacing: Standardized spacing values (xs, sm, md, lg, xl, xxl)
- Corner radius: Consistent border radius values
- Shadows: Predefined shadow styles
- View modifiers: `.cardStyle()`, `.primaryButtonStyle()`, `.secondaryButtonStyle()`

---

## 🎯 Key Design Decisions

### Separation of Concerns
- **isEnabled**: Only controls if reminder is active (can receive notifications)
- **completedOn**: Only tracks daily completion status
- **These are completely independent**

### Repeating Reminders
- Always compute next occurrence from current date (not stored date)
- Preserve schedule even after Snooze
- "Repeats every week" = indefinitely, not "this week only"

### Notification Management
- One notification per reminder (identified by `notificationId`)
- Always schedule for next occurrence
- Cancel both pending and delivered notifications

### Daily Reset
- Deterministic: Uses date comparison (`isDate(_:inSameDayAs:)`)
- Works even if app wasn't opened for days
- Called on app launch, not on background/foreground

---

## 📋 Current Architecture

```
MedVibe/
├── App/
│   ├── MedVibeApp.swift          # App entry, ModelContainer setup
│   ├── RootTabView.swift         # Tab navigation, daily reset logic
│   └── ContentView.swift         # Root view
├── Core/
│   ├── Models/
│   │   ├── Reminder.swift        # Main reminder model
│   │   └── ReminderSchedule.swift # Weekly schedule model
│   └── Services/
│       └── NotificationService.swift # Notification management
├── Features/
│   └── Reminders/
│       ├── RemindersView.swift   # List view with cards
│       └── AddReminderView.swift # Create/edit form
└── UI/
    └── Components/
        └── DesignSystem.swift    # Design tokens
```

---

## ✅ Acceptance Tests Status

- ✅ Create one-time reminder: Defaults to not completed, schedules notification
- ✅ Create repeating reminder: Computes next occurrence correctly
- ✅ Mark complete: Advances to next occurrence for repeating, disables for one-time
- ✅ Snooze: Reschedules +10 min, preserves schedule
- ✅ Daily reset: Completion resets on new day
- ✅ Store migration: Auto-resets in DEBUG mode

---

## 🚀 What's Working

1. **CRUD Operations**: Create, Read, Update, Delete reminders
2. **Repeating Logic**: Weekly repeating with weekday selection
3. **Notifications**: Full notification system with actions
4. **Completion Tracking**: Daily completion with automatic reset
5. **UI/UX**: Clean, modern design with clear semantics
6. **Data Persistence**: Reliable SwiftData storage with migration handling

---

## 📝 Notes for Future Development

- All core functionality is implemented and tested
- Code follows SwiftUI + SwiftData best practices
- Architecture is clean and maintainable
- Ready for additional features (Home dashboard, statistics, etc.)
- App Store preparation can begin (privacy policy, descriptions, etc.)

---

**Last Updated**: Current session
**Status**: Core functionality complete, ready for testing and polish
