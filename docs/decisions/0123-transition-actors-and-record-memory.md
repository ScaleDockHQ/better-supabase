# 0123: Transitions record who made them; memory scopes to records and soft deletes

- Status: accepted
- Date: 2026-10-28

## Context

`status_history` kept the user id and a reason. A status change made by a
portal visitor who isn't an auth user, such as a customer accepting a quote,
had no actor, and apps that keep an audit trail per request also wanted the
IP address and user agent. Some apps already keep their own history table
with portal-only columns and want the block to check edges without writing
history at all.

Memory had user, agent, chat, project and organization scopes. Agents that
work on a deal or a ticket need facts about that record that every member
reads. Facts were deleted for good by `forget`, so a mistaken forget lost the
fact, and the store had no way to say how sure a fact was or when it stops
being true.

## Decision

`transition(subject, to, options)` takes `{ reason, actor }`. The actor is a
name, an email, an IP address and a user agent; the SQL function takes it as
a jsonb argument, checks the IP as `inet` (`STATE_ACTOR_INVALID`) and passes
it to the trigger through the transaction setting
`better_supabase.transition_actor`, next to the reason. `status_history` gains
`actor_name`, `actor_email`, `ip` and `user_agent`; an app history table maps
them with optional column keys. `history: "app"` writes no history and makes
`history()` fail with `STATE_HISTORY_APP`; the trigger still checks the edge
and records `status.changed`, and the settings stay readable for the app's
own trigger. The state-machine block moves to version 3.

Memory gains a `record` scope keyed by a `RecordRef`, shared like
`organization` memory (members read, admins change). Facts take a
`category`, a `confidence` that weighs search scores, and an `expires_at`
that hides them from lists and searches. `forget` sets `deleted_at`;
`memory_restore` undoes it and `purge_memories` (service role) removes
deleted and expired rows after a retention period. Searches count their hits
in `use_count` and `last_used_at`. The memory block moves to version 3.

## Alternatives considered

- A fifth positional argument for the actor. Rejected: `transition(a, b, undefined, actor)`
  reads poorly and the reason and actor travel together.
- A separate audit table for actor details. Rejected: the history row is
  already the record of who changed the status.
- A `record` scope stored in the existing `project_id` column. Rejected: a
  record has a type and an id of any type, so it needs the subject pair that
  other blocks use for a `RecordRef`.

## Consequences

`transition(subject, to, "reason")` breaks; the 0.35 codemod rewrites string
literal reasons and lists the rest. `memory.archival.forget` no longer frees
space until `purge` runs, so apps schedule it. Memory rows carry five more
columns, and searches write the use counters, which adds a write per search
hit.
