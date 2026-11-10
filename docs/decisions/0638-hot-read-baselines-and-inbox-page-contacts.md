# 0638: Record the hot read baselines and join the inbox page's contacts in one pass

- Status: accepted
- Date: 2026-11-10
- Amends: 0598

## Context

The performance audit named five reads that every example page runs: the inbox list, the notification
counts, the task board, the customer list and the islands bootstrap. Only the notification reads had a
scale test. `list_inbox_conversations` called `inbox_conversation_json` once per row, and that
function calls `inbox_contact_json` (which asks `can()` through `inbox_conversation_allowed`) and
`inbox_contact_read_at` (which asks `can()` again). A search called `inbox_contact_json` twice more for
every conversation of the tenant, not only for the page.

## Baselines

`supabase/tests/scale/scale_hot_reads.test.sql` seeds 20,000 conversations, 2,000 contacts, 20,000
notification recipients, customers and tasks on the native stack and prints `SCALE_MS` for each read.
Timings are from one local run each, in milliseconds, and move by tens of percent between runs.

| Read                                       | Before              | After |
| ------------------------------------------ | ------------------- | ----- |
| `list_inbox_conversations`, 50 rows        | 246 to 2,716        | 28    |
| `list_inbox_conversations`, next page (20) | 160                 | 13    |
| `list_inbox_conversations`, search         | 177,000 to 316,000  | 35    |
| customers, page by name                    | 13 (6.2 in EXPLAIN) | 1     |
| `island_counts`                            | 36                  | 6     |
| `notification_counts`                      | 21                  | 1     |
| tasks, first page by rank                  | 12                  | 1     |
| customers, newest page                     | 16                  | 1     |

The last two rows and `notification_counts` run code this PR does not change, so their gap is the
cold first call after a reset against a warm one, not a fix. The first run was cold and the later
ones warm; read them as baselines.

The EXPLAIN baselines, taken on the same data before the change, are:

- Tasks: `Index Scan using tasks_organization_id_rank_idx`, 26 ms with the first RLS evaluation, no sort.
- Customers by created date: `Index Scan using customers_active_idx`, 0.3 ms, no sort.
- Customers by name, before: `Seq Scan` over 20,002 rows then `Sort (top-N heapsort)`, 6.2 ms.
  After: `Index Scan using customers_organization_id_name_idx`, 1.6 ms, no sort.
- `notification_counts` and `island_counts` are single `Result` nodes; the counts inside are the cost
  (33 ms and 30 ms before the cap).

## Decision

**The inbox page joins its contacts once.** `list_inbox_conversations` cuts the page first, then joins
the inbox and the caller's read time with lateral joins and the contacts through one new function,
`inbox_contacts_json(ids, tenant, term)`. That function runs as its owner, like `inbox_contact_json`,
and asks the staff permission once per tenant of the ids, not once per row. The output is unchanged: a
conversation still carries `contact`, `inbox`, `last_read_at`, `contact_read_at` and `unread`.

**A search asks once.** With `term`, the same function returns the conversations whose contact name or
email contains it, for staff of the tenant or the contact's own account. The list filters on that
set, so a search no longer calls the per-row contact function.

**Read functions stay stable.** `list_inbox_conversations`, `inbox_counts` and `notification_counts`
are `stable`, and the scale test asserts it. `bootstrap_islands` stays volatile: the wrapper calls an
app function the library does not own, and a `stable` marker over a volatile app function would change
which snapshot it reads.

**The islands counts stop at 10,000.** The fixture's `public.island_counts` counts through a
`limit 10000` subquery, so a larger table reports 10,000 as a lower bound. This is the fixture's own
function, not a module.

**Customers get a name index.** `customers_organization_id_name_idx (organization_id, name)` replaces
the sort the default list plan showed in EXPLAIN. The other list orders already used an index, so no
other index was added.

## Consequences

The inbox module adds one `security definer` function, so the practices baseline for `inbox` rises from
246 to 252 (the count is over six renderings). The new function reads the same rows as
`inbox_contact_json` and `inbox_contact_read_at` and applies the same checks, so it opens no new access.
The old per-row functions stay, because the message and command paths use them.

A search term is matched with `ilike` over the tenant's people, one scan per call. It is cheap at the
sizes measured and has no trigram index; a tenant with millions of contacts would need one.

`inbox_counts` still counts every open conversation of the tenant (16 ms at 20,000). It is not
changed here; a capped form would be a separate decision.
