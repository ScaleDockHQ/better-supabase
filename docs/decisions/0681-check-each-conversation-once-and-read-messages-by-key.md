# 0681: Check each conversation once and read messages by key

- Status: accepted
- Date: 2026-11-11
- Amends: 0675

## Context

An adopter measured `list_comments` for one task with one comment at 1.8 to
2.7 s for a user who reads about 150 conversations across 11 tenants. ADR 0675
read the comment's conversation by key, but `messaging_messages_json` still
read the messages under the caller's policies. The messages policy has an
`exists` on `conversations`, and the planner turned it into a hashed subplan
over every conversation the caller can read, running `can_subject` for each.
On the fixture the same shape showed as one conversation check per message:
a 50-comment thread cost 252 `can_subject` calls.

## Decision

The checks run once per conversation, then the rows are read by key:

- `messaging_message_rows(ids)` (`security definer`) checks the distinct
  conversations of `ids` once with the conversation read rule and returns the
  messages, sent ones to the conversation's readers and unsent ones to their
  author, with the inbox note rule. `messaging_messages_json` reads them from
  it, then reads those few conversations again under the caller's policies,
  so the record's own row policies (an ended session, say) still decide.
  Its author, file and reaction CTEs are materialized: inlined into the final
  cross join, `message_authors` ran once per message.
- `list_comments` reads the record's conversation under the caller's
  policies, which is the one subject check, and takes its page of ids from
  `comment_page` (`security definer`, the same check again). `comment_counts`
  reads the records' conversations under the caller's policies and counts
  their comments with `comment_count_rows`.
- `list_record_mentions` builds the JSON of its page in one
  `messaging_messages_json` call instead of one per mention.
- `list_comments_unchecked` and `messaging_messages_json_unchecked` return
  the same rows with no check, granted to `service_role` only, for an app's
  own `security definer` payload after its own check.

The table policies stay as they are. A policy can't see which ids a query
asked for, and a per-row form would slow down the bulk reads where the hashed
plan wins. The other policies with an `exists` on a protected parent
(`conversation_members`, `message_edits`, `message_record_mentions`,
`thread_summaries`, `comment_tasks`, `attachments`) were measured on the scale
fixture: none plans the parent over every visible conversation; each costs at
most one check per row it returns.

`scale_comments_many_tenants` (50 tenants, 150 record conversations, one
thread of 50) counts `can_subject` calls:

| Read                                | Before      | After      |
| ----------------------------------- | ----------- | ---------- |
| `list_comments`, one comment        | 5 (6 ms)    | 6 (6 ms)   |
| `list_comments`, 50 comments        | 252 (54 ms) | 6 (13 ms)  |
| `messaging_messages_json`, 50 ids   | 250 (51 ms) | 3 (10 ms)  |
| `comment_counts`, three records     | 55 (8 ms)   | 6 (2 ms)   |
| `list_record_mentions`, 58 mentions | 139 (65 ms) | 88 (26 ms) |

## Alternatives considered

One check inside a `security definer` body, as first proposed. Inside a
definer function the record's row policies don't apply, so `can_subject`
answers "the row exists" for a type without a read key, and an ended session
would still read the comments. The caller-side read of the conversation keeps
that rule for one extra check.

## Consequences

The `security-definer-functions` practice count grows by the five helpers.
Every read of messages now costs a fixed number of checks per conversation,
whatever the caller can see elsewhere. A direct `select` on `messages` over
the Data API still plans the policy as before.
