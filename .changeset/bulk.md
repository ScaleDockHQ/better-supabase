---
"better-supabase": minor
---

Add bulk actions (`better-supabase/blocks/bulk` and the `bulk` SQL module). `bulk.run` applies `tags.set`, `stateMachine.transition`, `relations.link` or an app's own action to up to 500 rows in one call with a result per row, and `bulk.start` puts larger sets on the jobs queue `bulk`, where each step runs as the user who started the run and broadcasts its progress on a Realtime topic.
