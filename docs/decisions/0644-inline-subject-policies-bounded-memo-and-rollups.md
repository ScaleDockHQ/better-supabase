# 0644: Inline the remaining subject read policies, bound the memo keys and roll up replies in place

- Status: accepted
- Date: 2026-11-10
- Amends: 0606, 0617, 0637

## Context

Workstream R of the performance plan. Measured on the native stack (Postgres 17.11), 60,000
customers and 12,000 rows of each family on them, one tenant, signed in as the Acme owner. Every
change has a scale file in `supabase/tests/scale`; the machine was busy with other agents, so read
the ratios, not the milliseconds.

## Decisions

### Inline subject read policies for deal contacts, subject knowledge and deadlines

`deal_contacts_read` and `knowledge_documents_read` render the ADR 0606 form through
`registryReadable` (the registry's subjects inline, a type a later module's table holds through
`can_subject`). `deadlines_read` renders the deadline subject list through `inlineSubjectReadable`
with `deadline_subject_readable` as the fallback, so the answer for an unlisted type is unchanged.
The columns are qualified with their table. The functions stay for the write paths.

| Read (12,000 of 60,000 rows) | Per row  | Inline |
| ---------------------------- | -------- | ------ |
| `deal_contacts`              | 3,894 ms | 30 ms  |
| `knowledge_documents`        | 4,007 ms | 17 ms  |
| `deadlines`                  | 6,702 ms | 85 ms  |

The recursion check of ADR 0606 for each family: the contacts policy reads `deals`, whose policy reads
no contact; knowledge documents and deadlines are not subjects of anything the inlined tables read.
The pgTAP suite passes unchanged on a reset stack.

### Not done: messaging conversations, care plans and activities

The `subject` branch of `conversations_read` keeps `can_subject`. A conversation and a message are
subjects themselves, so the inline form reads the conversations policy again for the `conversation`
type. Inlining it with those two types on the fallback worked for conversations alone (12,000 rows
in 188 ms against 14,260 ms per row), but it made every other inline policy expand the 40 branches
of the conversation policy through the `message` subject: planning the deadlines read went from 19
to 849 ms and the field history read from 8 to 736 ms, with executions of 2.7 to 3.2 s. The
conversations read stays at about 4 s per 12,000 rows until a subject list without messaging's own
types exists. Care plans and activities recurse as ADR 0617 and 0606 recorded and keep `can_subject`.

### Bounded memo keys

`memo_get` and `memo_set` keep a transaction-local setting per key, and a setting stays in the
session's table of placeholders after the transaction ends. `retention_for_memo` and `is_held_memo`
keyed on the statement timestamp, and `approval_fact` on the user and the fact, so a pooled
connection grew one setting per statement. `memo_slot_get` and `memo_slot_set` keep such a key in one
of 256 settings (`hashtext(key) & 255`) holding the key and its value; a second key in the slot
replaces the first, which costs a recompute and never returns another key's value. The retention and
hold memo, `approval_fact` and the audit tenant label use the slots. `memo_get` and `memo_set` stay
for `approvals.gen`, a counter that a replaced slot would reset. 5,000 keys now take at most 256
settings.

### Incremental thread rollups

`messaging_message_written` recounted every reply of the thread for each reply, so a reply costs the
length of its thread. A reply that is sent live and not deleted now adds to the root in place (count,
newest time, first three repliers); a delete, a restore or a reply that is not newer than the newest recounts
as before. With 20,000 replies stored, 200 replies sent one at a time take 189 ms in total against
880 ms for the recount alone. Many replies in one statement still update the root once each, and
Postgres follows the update chain of that one row, so a 12,000 row insert of replies stays
superlinear; a statement-level trigger needs transition tables, which Postgres refuses together with
the column list the trigger uses, so it is not done.

### Full index on `messages (conversation_id)`

`messaging_messages_conversation_idx` is partial (top-level messages and broadcasts), so the cascade
delete of a conversation and a read of every message of one scanned the table. `messaging_messages_conversation_all_idx` covers the column for all rows.

### Id tiebreaker on the tenant and created_at indexes

Fifteen `(tenant_id, created_at desc)` indexes end in `id desc` (activities, access requests,
AI batches and moderation events, commission plans, dispatch work orders, expense reports, dunning
runs, DSA statements and appeals, passes, posts, shipments, webhook deliveries and workflow runs), so
a list ordered by `created_at desc, id desc` pages without a sort and ties keep one order. The offset
lists are not moved to keyset (ADR 0637 keeps the offset option); that needs a decision per caller.

## Consequences

`better-supabase upgrade` rewrites the modules above; the migration replaces three policies and
fifteen indexes, adds the full messages index and the two memo functions, and replaces the rollup,
memo and audit functions. An existing install keeps the old index of the same name until the diff
replaces it. The prelude defines `memo_slot_get` and `memo_slot_set`.

The re-measured First Load JS baseline of 13 routes in `tests/next-build/baseline.json` rose by 7 to
47 bytes brotli (about 0.01 percent of a route, no raw baseline moved). Brotli moves with chunk
hashes; the numbers are taken from a fresh build of this branch after merging main. The guard in
`next-build.test.ts` is unchanged.
