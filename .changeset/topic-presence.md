---
"better-supabase": minor
---

`defineTopic` presence: `presence` takes a Standard Schema (or `true`), and subscriptions to such a topic get `track(state)`, `untrack()`, `members()` and an `onPresence` option with everyone's validated states after each sync. Presence runs on the topic's shared channel, so one client has one tracked state per topic, and it leaves with the subscription that tracked it. States that fail the schema skip `onPresence` and reach `onInvalid` as a `presence` message.
