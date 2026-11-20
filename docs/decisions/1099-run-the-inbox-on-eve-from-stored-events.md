# 1099. Run the inbox on eve from stored events

Status: accepted

## Context

`routeInbox` needs a static Chat SDK channel per platform, so a tenant that connects its own channel at runtime has no path to eve. Replies went back only through the Chat SDK bridge.

## Decision

A connection's webhook resolves the connection from the path and verifies with its own credential, then stores the event in `inbound_events`. A handoff job records the message and sends bot-mode conversations to an eve channel, keyed by message id. The principal is the contact in the conversation, with the conversation id as principal id, because the session sync sees only the id and type of the principal. Replies leave through a `reply` handler of the session sync, keyed by turn, as a bot message (the inbox's deliveries send it) or as an `ai` draft.

## Consequences

The reply handler runs inside a sync pass, so a failure retries the pass and the key dedupes the send. A draft is deduplicated by a metadata key among open drafts only. `routeInbox` stays for Chat SDK apps and keeps the contact id as principal id.
