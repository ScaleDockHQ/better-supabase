---
"better-supabase": minor
---

`collaboration` gains `discuss`, which posts a comment on a record and attaches tags to it, and
`scheduling` gains `bookWithReminder`, which confirms a booking and sets the caller's reminder on
it. Each stops at the first failed step and returns that error.
