# 1070: A per-user usage rollup on ai-chat (lane Y6, EX-306)

- Status: accepted
- Date: 2026-11-15
- Amends: 0999

## Context

`ai_runs` carries the tokens and the gateway's cost of every generation, and
its only select policy lets the owner read their own rows. The example's usage
page therefore totals the caller's own runs by model and by day (EX-318,
EX-306) and can't show what each member of an organization spends. An
organization owner who wants that has no read: `runs.list` without a chat
returns the caller's runs, and the service role sees every organization.

## Decision

`ai-chat` gets one SQL function and one client method:

- `ai_usage_by_user(tenant, since, until, size)` is a `security definer`
  function that groups the runs of the tenant's chats by owner and returns
  `user_id`, `runs`, `failed`, the three token counts, `cost_micro_usd` and
  `last_run_at`, most expensive first. `since` is inclusive and `until` is
  exclusive, on `started_at`. `size` defaults to 50 and is at most 500.
- The caller needs `ai_chat.manage` in the tenant (the same key that sets tool
  policies and deletes any chat), or is the service role. Anyone else gets
  `AI_CHAT_FORBIDDEN`. The tenant comes from the chat, not from the run, so a
  run in a chat of another organization never counts.
- `runs.usageByUser({ organizationId, since?, until?, limit? })` returns
  `AiUserUsage` rows. A usage key that is not a number counts as zero, and a
  run without a cost counts as 0 micro-dollars.

The rollup is a read and records no event. It does not change the owner-only
policy on `ai_runs`: a manager reads totals, never another member's runs or
their chats.

## Consequences

- The example's usage page shows a "Per member" card to callers with
  `ai_chat.manage`.
- The migration `20270119000060_y6_ai_usage_by_user.sql` adds the function;
  apps run `better-supabase upgrade` and apply the migration it generates.
- The grouping scans the tenant's runs in the range. The existing
  `ai_runs_chat_idx` serves the join; a range that spans millions of runs
  needs a rollup table, which no app has asked for.
