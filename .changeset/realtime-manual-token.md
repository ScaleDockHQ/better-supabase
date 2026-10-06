---
"better-supabase": patch
---

`topic.subscribe`, `topic.send`, live counts and the React topic hooks no longer reset a Realtime token the app set with `supabase.realtime.setAuth(token)`. They refresh the token from the session only when realtime-js reports it isn't a manual one.
