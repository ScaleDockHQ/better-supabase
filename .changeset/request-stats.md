---
"better-supabase": minor
---

Request stats now count the calls of a fill that runs through a session handle (`bsb.cached({ session })`, `kept.as(session)`, `getAccess` with a key) on the render that made the handle. Each `bsb.kept` and `bsb.remote` call adds an entry record (`{ id, kind, outcome, fillMs }`) to the stats route, and `x-bsb-db-calls` ends in `tagCalls;hits;misses;fillMs`. `bsb.statsFetch(fetch)` counts the requests of a Supabase client the app builds itself. See ADR 1221.
