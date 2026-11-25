---
"better-supabase": minor
---

`scheduling.bookWithReminder` with a reminder in minutes and the new `bookings.holdWithReminder` run as one database call. The `book_with_reminder` function books and confirms the slot and saves the reminder in one transaction, so a failed reminder now rolls the booking back. The TypeScript hooks of `bookings.hold` and `reminders.upsert` no longer fire inside it; the composite's own hook does. A reminder at an instant keeps the two-call path.
