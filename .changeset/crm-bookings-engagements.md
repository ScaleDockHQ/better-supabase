---
"better-supabase": minor
---

Add `blocks.engagements.options.bookings`. With the bookings block installed and the option on, every confirmed booking becomes a `meeting` engagement with the external ref `booking:<id>`: rescheduling moves it, and cancelling completes it with the outcome `cancelled: <reason>`. With parties installed, the meeting sits on the person whose user or email matches the booker's, and on their company. A trigger on the bookings table does this, so bookings made through the public link or by a direct write are logged too.
