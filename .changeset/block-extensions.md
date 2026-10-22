---
"better-supabase": minor
---

Extend three blocks. Each extension is behind a new option that is off by default, so existing installs render the same SQL.

- `engagements` with `recordings: true` stores call and meeting recordings as `ai-files` files, keeps transcript segments with speakers and timestamps, and attaches AI notes and a summary through the AI-neutral interfaces. New events: `engagement.recorded`, `engagement.transcribed` and `engagement.summarized`.
- `orders` with `kitchen: true` gives every order line a preparation state (`queued`, `preparing`, `ready`, `served`) and a station, published for Realtime, with the `kitchen-display` and `order-state-board` recipes. New events: `order.prepared` and `order.served`.
- `bookings` with `recurring: true` books a series from a recurrence rule (`bookSeries`, with `parseRecurrence` and `formatRecurrence` for the RRULE subset), moves one occurrence or every following one (`reschedule`) and cancels a series (`cancelSeries`). Every occurrence goes through the same exclusion constraint. New event: `booking.rescheduled`.
- `passes` with `credits: true` pays for classes with a pack of credits (`bookWithCredit`), keeps every credit in a ledger (`credits`), and refunds the credit when the booking is cancelled at least `creditRefundBefore` (default 12 hours) before it starts. New events: `pass.credit_used` and `pass.credit_refunded`.
