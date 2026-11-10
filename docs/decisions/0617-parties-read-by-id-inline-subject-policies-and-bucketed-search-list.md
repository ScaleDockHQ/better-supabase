# 0617: Read parties by id, inline more subject policies and bucket the deferred search list

- Status: accepted
- Date: 2026-11-10
- Amends: 0606

## Context

Workstream E of the performance plan. Measured on the native stack (Postgres 17.11), 60,000
customers, one tenant, signed in as the Acme owner. Each SQL change below has a pgTAP file and a
scale test (`supabase/tests/scale`).

## Decisions

### Parties read by id

`get_company(id)` and `get_person(id)` return one active record as the caller (`stable`, security
invoker), and the contacts block exposes `getCompany` and `getPerson`. The example's `loadContact`
paged `list_companies` up to ten times of 200 rows and called a company beyond the 2,000th
missing. A read by id is one primary key lookup (1.5 ms through the function, against 2.0 ms for
each list page plus a round trip). The example change is left to the example app's owner.

### Inline subject read policies

`registryReadable` renders the ADR 0606 form (`case subject_type when ... exists (...)`, the tenant
permission as a set) over the registry's subjects, with `can_subject` for a type a later module's
table holds. `subjectReadable` takes a `team` option, so a type whose record team holds the read
action ors `is_subject_member` onto the permission, as `can_subject` does (without it the
observations suite shows a member off the team reading records). Applied to field history,
observations, SLA clocks, pipeline stage history, consents, medication orders and funding awards.

| Read (12,000 of 60,000 rows) | Before   | After |
| ---------------------------- | -------- | ----- |
| `field_changes`              | 3,611 ms | 44 ms |
| `observations`               | 3,455 ms | 31 ms |
| `sla_clocks`                 | 3,504 ms | 33 ms |

Before is the earlier policy form (field history and observations) or `can_subject` per row (SLA
clocks). Medication orders, funding awards, pipeline history and consents use the same expression
and pass their RLS pgTAP files; no scale number of their own was recorded.

Not done: care plans. A care plan is itself a subject, so the inline `exists` on its table reads its
own policy (`infinite recursion detected in policy for relation "care_plans"`, the failure ADR 0606
recorded for activities). Activities, care plans, deals (a contact is not a subject row), the
second medication policy (administrations read through their order) and the messaging, knowledge
and deadlines checks keep `can_subject`.

### Deferred search list

`search_enqueue` kept the noted keys in one transaction-local text setting and rewrote the whole
string on every note, which is quadratic: 2,000 notes took 30 ms, 10,000 took 595 ms and 30,000
took 5,451 ms. The keys now go to one of 256 settings by `hashtext(key) & 255`, a 256th of the
copy per note: 30,000 notes take 133 ms and the flush 291 ms. A temporary table was tried and
rejected: the registry tests refuse `create temp table` (plpgsql_check cannot see it) and a
`delete` without `where`.

## Measured away or not changed

- Statement-level broadcasts. `realtime.send` costs 11.5 microseconds per call (5,000 calls, 58 ms;
  one call with 5,000 ids, 4 ms), so a bulk write of 60,000 rows pays about 700 ms. The row
  triggers that qualify by topic (`broadcast_announcement`, the workflow run tenant topic) fire on
  administrator writes, and the message trigger sends one event per message on a topic per
  conversation, a payload contract clients read. Per-user topics stay per row (plan). Not changed.
- Typed key reads in the search trigger. `to_jsonb(new) ->> col` costs 1.3 microseconds per row on
  a wide row (77 ms per 60,000 rows, 3 ms typed). A per-table function for each subject also lands
  in the app tables file, the owner files and the rename pairing of `upgrade`; the saving is below a
  tenth of the 12 microsecond note cost, so it is not done. The sessions triggers were not found
  to read keys this way.
- UUID v7 defaults. The stack runs Postgres 17.11, which has no `uuidv7()`; the plan allows it only
  where the server has it. Not changed.
- Keyset list template and the `@bsb list` tag. See the pull request; this needs a design decision
  on offset callers before code.

## Consequences

`better-supabase upgrade` rewrites eight modules; the migration adds two functions and replaces
policies. Unrelated drift between `supabase/schemas` and the migration history on `main` (the
`audit`, `finish_import_run` and `usage_*` functions, the drive text watch trigger) is part of the
generated migration.
