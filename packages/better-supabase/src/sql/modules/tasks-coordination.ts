import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";
import type { StageRef } from "./tasks-coordination-shared.ts";
import type { TaskNames } from "./tasks-functions.ts";
import type { HoldApproval } from "./tasks-hold-approvals.ts";

import { sqlString } from "../../core/template.ts";
import { fail, userGrant } from "../shared.ts";
import { lockModuleTable } from "./over-app.ts";
import {
  claimsSql,
  holdSql,
  outcomesSql,
} from "./tasks-coordination-claims.ts";
import { liveSql, orderSql } from "./tasks-coordination-order.ts";
import { actorPayload, load, taskRecord } from "./tasks-coordination-shared.ts";
import {
  holdApprovalOf,
  holdKindsOf,
  holdApprovalOn,
  settleHoldSql,
} from "./tasks-hold-approvals.ts";

export { actorPayload, taskRecord };

const STAGE_KEY = /^[a-z][a-z0-9_-]{0,62}$/;
const CATEGORY_KEY = /^[a-z][a-z0-9_]{0,62}$/;
const DEFAULT_LEASE = 900;
const MAX_PLAN = 100;

/** A session kind `claims.agents` can name. */
export type AgentKind = "agent" | "oauth-client" | "api-key";

const AGENT_KINDS: readonly AgentKind[] = ["agent", "oauth-client", "api-key"];

function isAgentKind(value: unknown): value is AgentKind {
  return AGENT_KINDS.some((kind) => kind === value);
}

/** Reads `claims.agents`: `agent` always counts, the list adds kinds to it. */
function agentKindsOf(value: unknown, at: string): readonly AgentKind[] {
  if (value === undefined) {
    return ["agent"];
  }

  if (
    !Array.isArray(value) ||
    value.length === 0 ||
    !value.every(isAgentKind) ||
    new Set(value).size !== value.length
  ) {
    throw new TypeError(
      `${at} must be a list of distinct session kinds: "agent", "oauth-client" or "api-key"`,
    );
  }

  return AGENT_KINDS.filter((kind) => kind === "agent" || value.includes(kind));
}

/** What `blocks.tasks.options` `needs`, `claims` and `hold` resolve to. */
export interface Coordination {
  /** The prerequisite rules, or null when the app keeps no `waiting_on`. */
  readonly needs: { readonly refuse: "claims" | "started" | "none" } | null;
  readonly lease: number;
  readonly maxLease: number;
  /**
   * What `claim_next_task` picks from: the caller's own tasks, or any ready
   * one.
   */
  readonly next: "assigned" | "any";
  /** The session kinds the claim rules treat as agents. Always holds `agent`. */
  readonly agents: readonly AgentKind[];
  readonly startStage: StageRef | null;
  readonly expiredStage: StageRef | null;
  /** The stage key a hold moves a task to, or null for a flag-only hold. */
  readonly holdStage: StageRef | null;
  /** Whether a hold opens an approval, and what a rejection does. */
  readonly holdApproval: HoldApproval | null;
  /** The hold kinds a hold accepts, or null for any short lowercase word. */
  readonly holdKinds: readonly string[] | null;
  /** The permission key a claim checks, as a SQL literal. */
  readonly claim: string;
}

function record(value: unknown, at: string): Record<string, unknown> {
  if (value === undefined) {
    return {};
  }

  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new TypeError(`${at} must be an object`);
  }

  return Object.fromEntries(Object.entries(value));
}

function only(
  value: Record<string, unknown>,
  at: string,
  keys: readonly string[],
): void {
  for (const key of Object.keys(value)) {
    if (!keys.includes(key)) {
      throw new TypeError(`${at} has no key "${key}"`);
    }
  }
}

function stageKey(value: unknown, at: string): StageRef | null {
  if (value === undefined) {
    return null;
  }

  if (typeof value === "string" && STAGE_KEY.test(value)) {
    return value;
  }

  if (typeof value === "object" && value !== null && !Array.isArray(value)) {
    const keys = Object.keys(value);

    const category: unknown = Object.entries(value).find(
      ([key]) => key === "category",
    )?.[1];

    if (
      keys.length === 1 &&
      typeof category === "string" &&
      CATEGORY_KEY.test(category)
    ) {
      return { category };
    }
  }

  throw new TypeError(`${at} must be a stage key or { category }`);
}

/** Reads and checks the coordination options. */
export function coordinationOf(
  ctx: BlockSqlContext,
  claim: string,
  manageKey: string,
): Coordination {
  const at = "blocks.tasks.options";
  const needs = ctx.option("needs");
  const claims = record(ctx.option("claims"), `${at}.claims`);
  const hold = record(ctx.option("hold"), `${at}.hold`);

  only(claims, `${at}.claims`, [
    "lease",
    "maxLease",
    "next",
    "agents",
    "startStage",
    "expiredStage",
  ]);
  only(hold, `${at}.hold`, ["stage", "kinds", "approval"]);

  const lease = claims["lease"] ?? DEFAULT_LEASE;
  const maxLease = claims["maxLease"] ?? Math.max(DEFAULT_LEASE, Number(lease));

  if (
    typeof lease !== "number" ||
    typeof maxLease !== "number" ||
    !Number.isInteger(lease) ||
    !Number.isInteger(maxLease) ||
    lease < 1 ||
    maxLease < lease
  ) {
    throw new TypeError(
      `${at}.claims.lease and maxLease must be whole seconds, with lease at least 1 and at most maxLease`,
    );
  }

  const next = claims["next"] ?? "assigned";

  if (next !== "assigned" && next !== "any") {
    throw new TypeError(`${at}.claims.next must be "assigned" or "any"`);
  }

  const holdKinds = holdKindsOf(hold["kinds"], `${at}.hold.kinds`);

  let resolved: Coordination["needs"] = null;

  if (needs !== undefined && needs !== false) {
    const rules = record(needs, `${at}.needs`);

    only(rules, `${at}.needs`, ["kind", "refuse"]);
    const refuse = rules["refuse"] ?? "claims";

    if (rules["kind"] !== "blocks") {
      throw new TypeError(`${at}.needs.kind must be "blocks"`);
    }

    if (refuse !== "claims" && refuse !== "started" && refuse !== "none") {
      throw new TypeError(
        `${at}.needs.refuse must be "claims", "started" or "none"`,
      );
    }

    if (!ctx.installed("relations")) {
      throw new TypeError(`${at}.needs needs the relations block`);
    }

    if (!ctx.has("items", "waitingOn")) {
      throw new TypeError(
        `${at}.needs needs the waiting_on column: add it to your tasks table, or run better-supabase codemod owned-columns`,
      );
    }

    resolved = { refuse };
  }

  return {
    needs: resolved,
    lease,
    maxLease,
    next,
    agents: agentKindsOf(claims["agents"], `${at}.claims.agents`),
    startStage: stageKey(claims["startStage"], `${at}.claims.startStage`),
    expiredStage: stageKey(claims["expiredStage"], `${at}.claims.expiredStage`),
    holdStage: stageKey(hold["stage"], `${at}.hold.stage`),
    holdApproval: holdApprovalOf(ctx, hold["approval"], manageKey, holdKinds),
    holdKinds,
    claim,
  };
}

/** The columns the coordination features add to the items table. */
export function coordinationColumns(ctx: BlockSqlContext): string {
  const w = (column: string): string => ctx.col("items", column);

  const add = (logical: string, definition: string | (() => string)): string =>
    ctx.has("items", logical)
      ? `\nalter table ${ctx.table("items")} add column if not exists ${w(logical)} ${typeof definition === "string" ? definition : definition()};`
      : "";

  const reason = ctx.has("items", "closeReason")
    ? `
alter table ${ctx.table("items")} drop constraint if exists ${ctx.tableName("items").name}_${ctx.colName("items", "closeReason")}_check;
alter table ${ctx.table("items")} add constraint ${ctx.tableName("items").name}_${ctx.colName("items", "closeReason")}_check check (${w("closeReason")} in ('completed', 'not_planned', 'duplicate', 'failed'));`
    : "";

  return `${add("waitingOn", () => `integer not null default 0 check (${w("waitingOn")} >= 0)`)}${add("heldAt", "timestamptz")}${add("holdKind", "text")}${add("holdReturnStage", "uuid")}${add("delegateProfile", "jsonb")}${add("closeNote", "text")}${reason}`;
}

/** The claims table, its lock and the ready index. */
export function coordinationTables(ctx: BlockSqlContext, n: TaskNames): string {
  const w = (column: string): string => n.c("items", column);
  const k = (column: string): string => n.c("claims", column);
  const tableName = ctx.tableName("items").name;

  const ready = ctx.has("items", "waitingOn")
    ? `\ncreate index if not exists ${tableName}_ready_idx on ${n.t("items")} (${w("tenant")}, ${w("number")}) where ${w("waitingOn")} = 0 and ${w("closedAt")} is null;`
    : "";

  const claims = ctx.hasTable("claims")
    ? `
create table if not exists ${n.t("claims")} (
  ${k("task")} uuid not null references ${n.t("items")} (${w("id")}) on delete cascade,
  ${k("tenant")} ${ctx.idType} not null,
  ${k("token")} uuid not null default gen_random_uuid(),
  ${k("epoch")} bigint not null default 1,
  ${k("holder")} uuid,
  ${k("profile")} jsonb,
  ${k("claimedAt")} timestamptz not null default now(),
  ${k("expiresAt")} timestamptz not null,
  ${k("expiredAt")} timestamptz
);
create unique index if not exists ${ctx.tableName("claims").name}_unique_idx on ${n.t("claims")} (${k("task")});
create index if not exists ${ctx.tableName("claims").name}_expires_idx on ${n.t("claims")} (${k("expiresAt")});
create index if not exists ${ctx.tableName("claims").name}_tenant_idx on ${n.t("claims")} (${k("tenant")}, ${k("holder")});
-- The token is a secret, so the table has no read policy: the functions read it.
${lockModuleTable(ctx, "claims")}`
    : "";

  return `${coordinationColumns(ctx)}${ready}${claims}`;
}

/**
 * `task_claim`: the public part of a task's live claim. The task row JSON calls
 * it, so it renders before any function that uses `row()`.
 */
export function claimReadSql(ctx: BlockSqlContext, n: TaskNames): string {
  if (!ctx.hasTable("claims")) {
    return "";
  }

  const { fn, t } = n;
  const k = (column: string): string => n.c("claims", column);

  return `
-- The public part of a task's live claim: who holds it and until when. The
-- token stays out.
create or replace function ${fn("task_claim")}(task uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('epoch', c.${k("epoch")}, 'holderId', c.${k("holder")}, 'profile', c.${k("profile")}, 'claimedAt', c.${k("claimedAt")}, 'expiresAt', c.${k("expiresAt")})
  from ${t("claims")} c
  where c.${k("task")} = task_claim.task and c.${k("expiresAt")} > now()
    and (${n.service} or ${ctx.scope.can(`c.${k("tenant")}`, n.read)})
$$;
${userGrant(`${fn("task_claim")}(uuid)`)}
`;
}

/** The functions every coordination feature needs, then the features. */
export function coordinationSql(
  ctx: BlockSqlContext,
  n: TaskNames,
  h: { readonly row: (alias: string) => string },
): string {
  return [
    actorSql(n),
    needsSql(ctx, n, h),
    claimsSql(ctx, n, h),
    `${holdSql(ctx, n, h)}${settleHoldSql(ctx, n)}`,
    outcomesSql(ctx, n, h),
    orderSql(ctx, n, h),
    liveSql(ctx, n),
  ].join("\n");
}

/** `task_actor`: who is acting, as a label for events. Never an access check. */
function actorSql(n: TaskNames): string {
  const fn = n.fn("task_actor");

  return `
-- Who is acting, as { kind, name } for events and timelines. kind is the
-- profile's own (a short lowercase word), agent when the token's act claim says
-- so, service, system without a user, or user. It labels; no check reads it.
create or replace function ${fn}(profile jsonb default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'kind', case
      when task_actor.profile ->> 'kind' ~ '^[a-z][a-z_-]{0,31}$' then task_actor.profile ->> 'kind'
      when auth.jwt() -> 'act' ->> 'kind' = 'agent' then 'agent'
      when auth.role() = 'service_role' then 'service'
      when auth.uid() is null then 'system'
      else 'user' end,
    'name', left(coalesce(nullif(task_actor.profile ->> 'name', ''), auth.jwt() -> 'act' ->> 'name'), 120))
$$;
${userGrant(`${fn}(jsonb)`)}
`;
}

/**
 * Prerequisites: `waiting_on`, `set_task_needs`, `create_tasks` and
 * `task.unblocked`.
 */
function needsSql(
  ctx: BlockSqlContext,
  n: TaskNames,
  h: { readonly row: (alias: string) => string },
): string {
  const { fn, t } = n;
  const w = (column: string): string => n.c("items", column);
  const type = sqlString(n.type);

  if (!ctx.installed("relations")) {
    return planSql(ctx, n, h, false);
  }

  const r = ctx.of("relations");
  const rc = (column: string): string => r.col("relations", column);
  const rel = r.table("relations");

  const completed = (alias: string): string =>
    ctx.is("items", "state", `${alias}.${w("state")}`, ["completed"]);

  const counting = ctx.has("items", "waitingOn");

  const maintain = counting
    ? `
-- Recounts the open prerequisites of the tasks in ids and records task.unblocked
-- for each open task whose count reaches zero. Cancelled and failed
-- prerequisites keep their dependents waiting.
create or replace function ${fn("recount_task_needs")}(ids uuid[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("items")};
  v_next integer;
  v_was integer;
begin
  for v_row in select * from ${t("items")} x where x.${w("id")} = any (coalesce(recount_task_needs.ids, '{}')) order by x.${w("id")} for update loop
    select count(*)::integer into v_next
    from ${rel} r
    join ${t("items")} p on p.${w("id")}::text = r.${rc("sourceId")} and p.${w("tenant")} = v_row.${w("tenant")}
    where r.${rc("tenant")} = v_row.${w("tenant")} and r.${rc("kind")} = 'blocks'
      and r.${rc("sourceType")} = ${type} and r.${rc("targetType")} = ${type}
      and r.${rc("targetId")} = v_row.${w("id")}::text
      and not (${completed("p")});
    v_was := v_row.${w("waitingOn")};
    if v_next is distinct from v_was then
      update ${t("items")} x set ${w("waitingOn")} = v_next where x.${w("id")} = v_row.${w("id")} returning * into v_row;
      if v_next = 0 and v_row.${w("closedAt")} is null then
        ${taskRecord(ctx, n, "task.unblocked", "v_row", ", 'waitingOn', 0")}
      end if;
    end if;
  end loop;
end;
$$;
revoke execute on function ${fn("recount_task_needs")}(uuid[]) from public, anon, authenticated;

create or replace function ${fn("task_needs_changed")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and tg_table_name = ${sqlString(ctx.tableName("items").name)} then
    perform ${fn("recount_task_needs")}(array(
      select r.${rc("targetId")}::uuid from ${rel} r
      where r.${rc("tenant")} = old.${w("tenant")} and r.${rc("kind")} = 'blocks'
        and r.${rc("sourceType")} = ${type} and r.${rc("sourceId")} = old.${w("id")}::text and r.${rc("targetType")} = ${type}));
  elsif tg_table_name = ${sqlString(ctx.tableName("items").name)} then
    perform ${fn("recount_task_needs")}(array(
      select r.${rc("targetId")}::uuid from ${rel} r
      where r.${rc("tenant")} = new.${w("tenant")} and r.${rc("kind")} = 'blocks'
        and r.${rc("sourceType")} = ${type} and r.${rc("sourceId")} = new.${w("id")}::text and r.${rc("targetType")} = ${type}));
  elsif tg_op = 'DELETE' then
    if old.${rc("kind")} = 'blocks' and old.${rc("targetType")} = ${type} and old.${rc("sourceType")} = ${type} then
      perform ${fn("recount_task_needs")}(array[old.${rc("targetId")}::uuid]);
    end if;
  elsif new.${rc("kind")} = 'blocks' and new.${rc("targetType")} = ${type} and new.${rc("sourceType")} = ${type} then
    perform ${fn("recount_task_needs")}(array[new.${rc("targetId")}::uuid]);
  end if;
  return null;
end;
$$;
revoke execute on function ${fn("task_needs_changed")}() from public, anon, authenticated;
drop trigger if exists ${ctx.trigger("task_needs_state")} on ${t("items")};
create trigger ${ctx.trigger("task_needs_state")}
  after update of ${w("state")} or delete on ${t("items")}
  for each row execute function ${fn("task_needs_changed")}();
drop trigger if exists ${ctx.trigger("task_needs_relation")} on ${rel};
create trigger ${ctx.trigger("task_needs_relation")}
  after insert or delete on ${rel}
  for each row execute function ${fn("task_needs_changed")}();
`
    : "";

  const setNeeds = `
-- Replaces the prerequisites of a task: ids is a list of task ids. Each one is
-- a "blocks" relation from the prerequisite to this task, so the relations
-- block's permission and cycle checks apply. A prerequisite in another
-- organization is refused.
create or replace function ${fn("set_task_needs")}(task uuid, ids uuid[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("items")};
  v_ids uuid[] := array(select distinct x from unnest(coalesce(set_task_needs.ids, '{}')) x where x is not null);
  v_old uuid[];
  v_id uuid;
begin
  ${load(ctx, n, "set_task_needs", n.write, { lock: false })}
  if set_task_needs.task = any (v_ids) then
    ${fail("TASK_NEEDS_INVALID", "a task can't wait on itself", "22023")}
  end if;
  if exists (select 1 from unnest(v_ids) x where not exists (
    select 1 from ${t("items")} p where p.${w("id")} = x and p.${w("tenant")} = v_row.${w("tenant")})) then
    ${fail("TASK_NEEDS_INVALID", "a prerequisite doesn't exist in this organization", "22023")}
  end if;
  v_old := array(select r.${rc("sourceId")}::uuid from ${rel} r
    where r.${rc("tenant")} = v_row.${w("tenant")} and r.${rc("kind")} = 'blocks' and r.${rc("sourceType")} = ${type}
      and r.${rc("targetType")} = ${type} and r.${rc("targetId")} = v_row.${w("id")}::text);
  foreach v_id in array array(select x from unnest(v_old) x where not (x = any (v_ids))) loop
    perform ${r.fn("unlink")}(v_row.${w("tenant")}, 'blocks', ${type}, v_id::text, ${type}, v_row.${w("id")}::text);
  end loop;
  foreach v_id in array array(select x from unnest(v_ids) x where not (x = any (v_old))) loop
    perform ${r.fn("link")}(v_row.${w("tenant")}, 'blocks', ${type}, v_id::text, ${type}, v_row.${w("id")}::text, '{}'::jsonb);
  end loop;
  return (select ${h.row("x")} from ${t("items")} x where x.${w("id")} = v_row.${w("id")});
end;
$$;
${userGrant(`${fn("set_task_needs")}(uuid, uuid[])`)}
`;

  return `${maintain}${setNeeds}${planSql(ctx, n, h, true)}`;
}

/**
 * `create_tasks`: a plan of tasks in one transaction. Every item is checked
 * before the first write, so a plan either lands whole or not at all.
 */
function planSql(
  ctx: BlockSqlContext,
  n: TaskNames,
  h: { readonly row: (alias: string) => string },
  withNeeds: boolean,
): string {
  const { fn, t } = n;
  const w = (column: string): string => n.c("items", column);
  const e = n.e;

  const allowed = [
    "key",
    "title",
    "body",
    "parentId",
    "teamId",
    e("projectId"),
    e("iterationId"),
    "priority",
    "estimate",
    "progress",
    "startAt",
    "endAt",
    "dueAt",
    "pipelineId",
    "stageId",
    "fields",
    "assignees",
    "needs",
  ];

  return `
-- Creates a plan of tasks in one transaction. items is a list of attrs for
-- create_task, each with an optional key, assignees and needs. parentId and
-- each needs entry are a task id or { "key": ... } naming another item of the
-- plan. At most ${String(MAX_PLAN)} items. Returns { tasks, keys }.
create or replace function ${fn("create_tasks")}(tenant ${ctx.idType}, items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item jsonb;
  v_pos integer := 0;
  v_keys jsonb := '{}';
  v_ids uuid[] := '{}';
  v_key text;
  v_task jsonb;
  v_id uuid;
  v_ref jsonb;
  v_prereqs uuid[];
  v_known text[] := array[${allowed.map((key) => sqlString(key)).join(", ")}];
begin
  if jsonb_typeof(create_tasks.items) is distinct from 'array' then
    ${fail("TASK_PLAN_INVALID", "items must be a list of tasks", "22023")}
  end if;
  if jsonb_array_length(create_tasks.items) > ${String(MAX_PLAN)} then
    ${fail("TASK_PLAN_TOO_LARGE", `a plan holds at most ${String(MAX_PLAN)} tasks`, "54000")}
  end if;
  for v_item in select value from jsonb_array_elements(create_tasks.items) loop
    v_pos := v_pos + 1;
    if jsonb_typeof(v_item) is distinct from 'object' then
      ${fail("TASK_PLAN_INVALID", "each item must be an object", "22023")}
    end if;
    if exists (select 1 from jsonb_object_keys(v_item) k where not (k = any (v_known))) then
      ${fail("TASK_PLAN_INVALID", "an item has a property create can't write", "22023")}
    end if;
    v_key := v_item ->> 'key';
    if v_key is not null then
      if v_keys ? v_key then
        ${fail("TASK_PLAN_INVALID", "two items share a key", "22023")}
      end if;
      v_keys := v_keys || jsonb_build_object(v_key, v_pos);
    end if;
  end loop;
  for v_item in select value from jsonb_array_elements(create_tasks.items) loop
    for v_ref in select value from jsonb_array_elements(coalesce(v_item -> 'needs', '[]'::jsonb)) union all select v_item -> 'parentId' where v_item ? 'parentId' loop
      if jsonb_typeof(v_ref) = 'object' and not (v_keys ? (v_ref ->> 'key')) then
        ${fail("TASK_PLAN_INVALID", "an item refers to a key the plan doesn't have", "22023")}
      end if;
    end loop;${
      withNeeds
        ? ""
        : `
    if v_item ? 'needs' then
      ${fail("TASK_NEEDS_UNSUPPORTED", "needs takes the relations block", "22023")}
    end if;`
    }
  end loop;
  for v_item in select value from jsonb_array_elements(create_tasks.items) loop
    v_task := ${fn("create_task")}(
      create_tasks.tenant,
      (v_item - 'key' - 'needs' - 'assignees' - 'parentId'),
      coalesce(array(select x::uuid from jsonb_array_elements_text(coalesce(v_item -> 'assignees', '[]'::jsonb)) x), '{}'));
    v_ids := array_append(v_ids, (v_task ->> 'id')::uuid);
  end loop;
  v_pos := 0;
  for v_item in select value from jsonb_array_elements(create_tasks.items) loop
    v_pos := v_pos + 1;
    v_id := v_ids[v_pos];
    if v_item ? 'parentId' then
      v_ref := v_item -> 'parentId';
      update ${t("items")} x set ${w("parent")} = case when jsonb_typeof(v_ref) = 'object' then v_ids[(v_keys ->> (v_ref ->> 'key'))::integer] else (v_ref #>> '{}')::uuid end
      where x.${w("id")} = v_id;
    end if;${
      withNeeds
        ? `
    if jsonb_array_length(coalesce(v_item -> 'needs', '[]'::jsonb)) > 0 then
      v_prereqs := array(select case when jsonb_typeof(x) = 'object' then v_ids[(v_keys ->> (x ->> 'key'))::integer] else (x #>> '{}')::uuid end
        from jsonb_array_elements(v_item -> 'needs') x);
      perform ${fn("set_task_needs")}(v_id, v_prereqs);
    end if;`
        : ""
    }
  end loop;
  return jsonb_build_object(
    'tasks', coalesce((select jsonb_agg(${h.row("x")} order by array_position(v_ids, x.${w("id")})) from ${t("items")} x where x.${w("id")} = any (v_ids)), '[]'::jsonb),
    'keys', coalesce((select jsonb_object_agg(k.key, v_ids[(k.value #>> '{}')::integer]) from jsonb_each(v_keys) k), '{}'::jsonb));
end;
$$;
${userGrant(`${fn("create_tasks")}(${ctx.idType}, jsonb)`)}
`;
}

/** The coordination functions of the contract. */
export function coordinationContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  const relations = ctx.installed("relations");

  return [
    { name: "task_actor", args: ["jsonb"], returns: "jsonb" },
    { name: "create_tasks", args: ["{id}", "jsonb"], returns: "jsonb" },
    ...(relations
      ? [{ name: "set_task_needs", args: ["uuid", "uuid[]"], returns: "jsonb" }]
      : []),
    ...(ctx.hasTable("claims")
      ? [
          { name: "task_claim", args: ["uuid"], returns: "jsonb" },
          {
            name: "claim_task",
            args: ["uuid", "integer", "jsonb"],
            returns: "jsonb",
          },
          {
            name: "claim_next_task",
            args: ["{id}", "jsonb", "integer", "jsonb"],
            returns: "jsonb",
          },
          {
            name: "renew_task_claim",
            args: ["uuid", "uuid", "integer"],
            returns: "jsonb",
          },
          {
            name: "release_task_claim",
            args: ["uuid", "uuid", "text"],
            returns: "boolean",
          },
          {
            name: "delegate_task",
            args: ["uuid", "uuid", "jsonb", "text"],
            returns: "jsonb",
          },
          { name: "expire_task_claims", args: [], returns: "integer" },
        ]
      : []),
    {
      name: "hold_task",
      args: ["uuid", "text", "text", "uuid[]"],
      returns: "jsonb",
    },
    { name: "release_task_hold", args: ["uuid"], returns: "jsonb" },
    ...(holdApprovalOn(ctx)
      ? [{ name: "settle_task_hold", args: ["uuid", "text"], returns: "void" }]
      : []),
    {
      name: "close_task",
      args: ["uuid", "text", "text", "uuid"],
      returns: "jsonb",
    },
    ...(ctx.installed("rank")
      ? [
          {
            name: "move_task",
            args: ["uuid", "uuid", "uuid", "uuid"],
            returns: "jsonb",
          },
          { name: "move_tasks", args: ["jsonb"], returns: "jsonb" },
        ]
      : []),
    { name: "task_stage_times", args: ["uuid"], returns: "jsonb" },
  ];
}
