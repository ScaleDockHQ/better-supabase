---
"better-supabase": minor
---

Delivery fails closed on records under an authorization provider. Without `delivery.subscribers` or `delivery.audience`, webhooks, notifications and reminders deliver an event about a registered subject only to users and service principals who may read it, through the new `can_subject_for(user, type, id, action)` in the `subjects` module and `subjectReaders(transport)`. Webhooks check each delivery against its stored subject, and a share link never counts.

Breaking: realtime `fanOut` under a server with authorization hooks and no subscriber policy sends an event with a `subject` to no one and returns `forbidden` with the hint `REALTIME_SUBSCRIBER_POLICY_REQUIRED`; pass `policy: subjectReaders(transport)`.
