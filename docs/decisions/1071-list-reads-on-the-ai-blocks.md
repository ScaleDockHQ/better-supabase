# 1071: List reads on the service-role AI blocks (lane Y6, EX-300)

- Status: accepted
- Date: 2026-11-15
- Amends: 0999

## Context

`prompts`, `ai-evals` and `ai-guardrails` run as the service role, and the
caller reaches them through `access` (ADR 0999). None of them could list what
an organization owns. The example's pages derived the names to show from the
assistant and the agents, then read versions, datasets and policies one name at
a time. A prompt, dataset or policy saved under a name no agent owns never
appeared, and a page of N subjects made N reads.

## Decision

Each block gets one keyset page read for its main entity. All three return the
`ListPage` shape (`items`, `hasMore`, `nextCursor`) and take `organizationId`,
`limit` (default 50, at most 200) and `after` (the previous `nextCursor`):

- `prompts.list` calls `list_prompts(tenant, after, max_rows)`. It returns the
  name, the latest version, the version count, the labels with the version each
  points at and the save time of the latest version, in name order. It reads no
  template.
- `datasets.list` calls `list_eval_datasets(tenant, after, max_rows)`. It
  returns the dataset with its item count, run count and the start of its latest
  run, in name order.
- `policies.list` calls `list_guardrail_policies(tenant, agent, after_agent,
  after_stage, max_rows)`. It returns the policies the tenant saved, enabled or
  not, ordered by agent and stage, and does not apply the fallback `get` does.

The functions run as `security invoker` and only the service role may call
them, as `get_eval_dataset` does, so the security-definer ceiling in
`tests/sql/practices-baseline.json` does not move. Without `organizationId` a
call lists the system rows; with `access` set, the existing check refuses a call
that does not name the caller's organization, so a caller never lists system
rows or another organization's.

The keyset is the key the tenant already has a unique index on, so each page is
an index range scan and no `offset` is used. The reads do not take `q`, sorts,
filters or counts: the full list contract of the repository blocks is larger
than these overview pages need, and a block can add them later without changing
the cursor.

## Consequences

- The example's prompt registry reads the saved names with `prompts.list`
  instead of one `versions` call per subject, and shows saved names that no
  agent owns.
- The migration `20270119140100_y6_ai_list_reads.sql` adds the three functions;
  apps run `better-supabase upgrade` and apply the migration it generates.
- `Prompts`, `AiEvals.datasets` and `AiGuardrails.policies` gain a method, so a
  hand-written implementation of these interfaces (a test double) needs it.
