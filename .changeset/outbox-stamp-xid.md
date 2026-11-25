---
"better-supabase": patch
---

The outbox sets an event's `xid` to the writing transaction's id on every insert and keeps it on an update, so an app that lets clients insert events can't have one plant an `xid` that stalls or skips every consumer. Run `better-supabase upgrade` to regenerate the outbox module.
