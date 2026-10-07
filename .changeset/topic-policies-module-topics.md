---
"better-supabase": patch
---

`realtime.policies` no longer writes a second receive policy for a topic that a SQL module in `sql.modules` already covers: the `notifications` topic while its `realtime` option is `broadcast`, the `announcements` topic, and `bs:t:` topics of `realtime-tables`. `sql sync` leaves those topics out of the file and names the module in a comment at its top. Topics that also send or use presence keep their policies.
