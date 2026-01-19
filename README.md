# MedVibe

**MedVibe** is a production-grade iOS application for managing health-related reminders with a reliable daily history system.

Unlike standard reminder apps, MedVibe focuses on **accountability and traceability** — users can always see what was completed, skipped, missed, or paused on any given day.

---

## ✨ Why MedVibe

Health reminders (medications, treatments, routines) require more than simple notifications.

MedVibe solves key real-world problems:
- Users forget whether something was done or missed
- Notifications are acted on outside the app
- Apps break when data is accessed asynchronously
- History is lost if the app isn’t opened daily

MedVibe is built to handle all of these **safely and deterministically**.

---

## 🚀 Core Features

### Reminders
- One-time reminders
- Weekly repeating reminders (weekday-based)
- Pause / resume semantics (without deleting data)
- Skip for today (does not break future schedule)

### Today Dashboard
- Shows only relevant reminders for today
- Quick actions: Complete, Skip, Snooze, Pause
- Completion progress indicator

### Daily History
- Automatic logging of:
  - ✅ Completed
  - ⏭ Skipped
  - ⏸ Paused
  - ❌ Missed
- Works even if the app was not opened
- 30-day rolling retention with automatic cleanup
- Grouped by day with completion statistics

### Notifications
- Local notifications with actions:
  - Complete
  - Snooze (10 minutes)
  - Skip
- Correct lifecycle handling (works when app is killed)
- Schedule preservation for repeating reminders

---

## 🧠 Architecture Highlights (Key Part)

MedVibe is built with a **crash-safe SwiftData architecture**.

### SwiftData Safety
- UI never holds SwiftData model references
- All views operate on **primitive view models** (`TodayRow`, `ReminderRow`)
- Actions re-fetch models using stable identifiers
- Prevents *detached backing data* crashes

### Deterministic State Model
- `isEnabled` — controls whether a reminder is active
- `completedOn` — tracks daily completion
- `skippedOn` — hides repeating reminders for today only
- These states are **fully independent**

### History Integrity
- Priority-based history updates:
  - Completed > Skipped > Paused > Missed
- User actions can override automatic logs
- Automatic backfill for missed reminders
- No duplicate entries (one per reminder per day)

---

## 🛠 Tech Stack

- **SwiftUI**
- **SwiftData**
- **UserNotifications**
- Feature-based folder structure
- Value-type view models
- Safe re-fetch pattern with `PersistentIdentifier`

---

## 📁 Project Structure
```
MedVibe/
├── App/
│ ├── MedVibeApp.swift
│ ├── RootTabView.swift
│ └── AppState.swift
├── Core/
│ ├── Models/
│ ├── Services/
│ └── Storage/
├── Features/
│ ├── Home/
│ ├── Reminders/
│ ├── History/
│ ├── Scan/
│ └── Library/
└── UI/
└── Components/
```
---

## 📌 Status

Core reminder, history, and notification systems are **production-ready**.

Next planned features:
- Document scanning (VisionKit)
- Medical record storage
- Reminder-to-document linking

---

## 👤 Author

**Vladimir Khegai**  
iOS / SwiftUI Developer  
Actively seeking software engineering internships
