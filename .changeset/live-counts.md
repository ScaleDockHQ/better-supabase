---
'better-supabase': minor
---

Add live counts: `useLiveCount(spec | seed)` in `better-supabase/react`, `liveCount()` in `better-supabase/realtime` and `next.liveCount(spec)` for a server-rendered seed. They refetch only the count (a HEAD request) after changes. Live queries and live counts now also refetch once when their channel rejoins, because broadcasts sent while disconnected are lost.
