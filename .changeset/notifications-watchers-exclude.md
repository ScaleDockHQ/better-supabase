---
"better-supabase": minor
---

`notifications.send` takes `watchers` and `exclude`. `watchers: false` (`'watchers': false` in `notify`) leaves the subject's watchers out, so a mention or an assignment reaches only the named recipients while a subscriptions table is mapped; members who ignore the subject stay out either way. `exclude` removes users after the watchers and the `notification_audience` hook are added, for a note that skips the members a mention already reached.
