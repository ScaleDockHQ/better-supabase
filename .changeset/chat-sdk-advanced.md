---
"better-supabase": minor
---

Chat SDK: `stateScheduler` and `scheduledAdapter` give any adapter `scheduleMessage`, holding the
messages in a Chat SDK state adapter until `publishDue` (or `maintain({ scheduled })`) posts them.
`inboxAdapter` gains `openDM` (with the new `dmInbox` option), `reply`, `fetchChannelInfo` and
`listThreads`, and keeps a posted card in `metadata.card`. `better-supabase/testing` adds
`testChatAdapter`, a conformance kit for Chat SDK adapters.
