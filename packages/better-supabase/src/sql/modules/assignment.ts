import type { AssignmentEvents } from "../../blocks/assignment/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import {
  activeMembership,
  fail,
  lockTable,
  pageSize,
  schemaPreamble,
  SERVICE_CALLER,
  userGrant,
} from "../shared.ts";
import { moduleOperations } from "./access-model.ts";

const EVENTS: BlockSqlEvents<AssignmentEvents> = {
  "subject.assigned": {
    subject: "assignment-queues",
    payload: [
      "organizationId",
      "queueId",
      "subjectType",
      "subjectId",
      "userId",
      "strategy",
    ],
    retries: true,
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    assignment_queue: {
      table: "queues",
      singular: "assignment_queue",
      primary: true,
    },
  },
  events: EVENTS,
  options: [],
  tables: {
    queues: {
      name: "assignment_queues",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        name: "name",
        subjectType: "subject_type",
        strategy: "strategy",
        conditions: "conditions",
        rank: "rank",
        enabled: "enabled",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    members: {
      name: "assignment_queue_members",
      lifecycle: { tenant: "tenant", user: "user", export: true },
      columns: {
        queue: "queue_id",
        tenant: "tenant_id",
        user: "user_id",
        weight: "weight",
        active: "active",
        credit: "credit",
        assignedCount: "assigned_count",
        lastAssignedAt: "last_assigned_at",
      },
    },
    log: {
      name: "assignments",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        queue: "queue_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        user: "user_id",
        assignedAt: "assigned_at",
      },
    },
  },
};

interface AssignmentNames {
  readonly fn: (name: string) => string;
  readonly t: (table: string) => string;
  readonly q: (column: string) => string;
  readonly u: (column: string) => string;
  readonly g: (column: string) => string;
  readonly read: string;
  readonly manage: string;
  readonly assign: string;
}

function names(ctx: BlockSqlContext): AssignmentNames {
  const keys = moduleOperations("assignment");

  return {
    fn: (name) => ctx.fn(name),
    t: (table) => ctx.table(table),
    q: (column) => ctx.col("queues", column),
    u: (column) => ctx.col("members", column),
    g: (column) => ctx.col("log", column),
    read: ctx.permission("read", keys.read),
    manage: ctx.permission("manage", keys.manage),
    assign: ctx.permission("assign", keys.assign),
  };
}

function tables(ctx: BlockSqlContext, n: AssignmentNames): string {
  const { t, q, u, g } = n;
  const policy = (table: string): string => `${ctx.tableName(table).name}_read`;

  return `create table if not exists ${t("queues")} (
  ${q("id")} uuid primary key default gen_random_uuid(),
  ${q("tenant")} ${ctx.idType} not null,
  ${q("name")} text not null check (length(${q("name")}) between 1 and 200),
  ${q("subjectType")} text not null check (${q("subjectType")} ~ '^[a-z][a-z0-9_]{0,62}$'),
  ${q("strategy")} text not null default 'round_robin' check (${q("strategy")} in ('round_robin', 'weighted')),
  ${q("conditions")} jsonb check (${q("conditions")} is null or jsonb_typeof(${q("conditions")}) = 'object'),
  ${q("rank")} integer not null default 0,
  ${q("enabled")} boolean not null default true,
  ${q("createdAt")} timestamptz not null default now(),
  ${q("updatedAt")} timestamptz not null default now(),
  unique (${q("tenant")}, ${q("name")})
);
create index if not exists ${ctx.naming.rename("assignment_queues_order_idx")} on ${t("queues")} (${q("tenant")}, ${q("subjectType")}, ${q("rank")}) where ${q("enabled")};
${lockTable(t("queues"), { read: true })}
create table if not exists ${t("members")} (
  ${u("queue")} uuid not null references ${t("queues")} (${q("id")}) on delete cascade,
  ${u("tenant")} ${ctx.idType} not null,
  ${u("user")} uuid not null references auth.users (id) on delete cascade,
  ${u("weight")} integer not null default 1 check (${u("weight")} between 1 and 100),
  ${u("active")} boolean not null default true,
  ${u("credit")} bigint not null default 0,
  ${u("assignedCount")} integer not null default 0,
  ${u("lastAssignedAt")} timestamptz,
  primary key (${u("queue")}, ${u("user")})
);
create index if not exists ${ctx.naming.rename("assignment_queue_members_user_idx")} on ${t("members")} (${u("user")});
${lockTable(t("members"), { read: true })}
create table if not exists ${t("log")} (
  ${g("id")} uuid primary key default gen_random_uuid(),
  ${g("tenant")} ${ctx.idType} not null,
  ${g("queue")} uuid references ${t("queues")} (${q("id")}) on delete set null,
  ${g("subjectType")} text not null,
  ${g("subjectId")} text not null,
  ${g("user")} uuid references auth.users (id) on delete set null,
  ${g("assignedAt")} timestamptz not null default now()
);
create index if not exists ${ctx.naming.rename("assignments_subject_idx")} on ${t("log")} (${g("tenant")}, ${g("subjectType")}, ${g("subjectId")}, ${g("assignedAt")} desc);
create index if not exists ${ctx.naming.rename("assignments_queue_idx")} on ${t("log")} (${g("queue")}) where ${g("queue")} is not null;
create index if not exists ${ctx.naming.rename("assignments_user_idx")} on ${t("log")} (${g("user")}) where ${g("user")} is not null;
${lockTable(t("log"), { read: true })}
drop policy if exists ${policy("queues")} on ${t("queues")};
create policy ${policy("queues")} on ${t("queues")} for select to authenticated
using (${ctx.scope.check(q("tenant"), n.read)});
drop policy if exists ${policy("members")} on ${t("members")};
create policy ${policy("members")} on ${t("members")} for select to authenticated
using (${ctx.scope.check(u("tenant"), n.read)});
drop policy if exists ${policy("log")} on ${t("log")};
create policy ${policy("log")} on ${t("log")} for select to authenticated
using (${ctx.scope.check(g("tenant"), n.read)});
`;
}

function functions(ctx: BlockSqlContext, n: AssignmentNames): string {
  const { fn, t, q, u, g } = n;
  const rules = ctx.of("rules");
  const tenant = ctx.of("tenant");
  const ms = (column: string): string => tenant.col("memberships", column);

  const isMember = (user: string, tenantId: string, alias: string): string =>
    `exists (select 1 from ${tenant.table("memberships")} ${alias} where ${alias}.${ms("tenant")} = ${tenantId} and ${alias}.${ms("user")} = ${user}${activeMembership(ctx, alias)})`;

  const queueJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${q("id")}, 'organizationId', ${row}.${q("tenant")}, 'name', ${row}.${q("name")}, 'subjectType', ${row}.${q("subjectType")}, 'strategy', ${row}.${q("strategy")}, 'conditions', ${row}.${q("conditions")}, 'rank', ${row}.${q("rank")}, 'enabled', ${row}.${q("enabled")}, 'createdAt', ${row}.${q("createdAt")}, 'updatedAt', ${row}.${q("updatedAt")}, 'members', coalesce((
      select jsonb_agg(jsonb_build_object('userId', z.${u("user")}, 'weight', z.${u("weight")}, 'active', z.${u("active")}, 'assignedCount', z.${u("assignedCount")}, 'lastAssignedAt', z.${u("lastAssignedAt")}) order by z.${u("user")})
      from ${t("members")} z where z.${u("queue")} = ${row}.${q("id")}
    ), '[]'::jsonb))`;

  const assigned = ctx.record({
    type: "subject.assigned",
    payload: `jsonb_build_object('organizationId', v_queue.${q("tenant")}, 'queueId', v_queue.${q("id")}, 'subjectType', v_queue.${q("subjectType")}, 'subjectId', assign_subject.subject_id, 'userId', v_user, 'strategy', v_queue.${q("strategy")})`,
    subject: `'assignment-queues/' || v_queue.${q("id")}::text`,
    tenant: `v_queue.${q("tenant")}::text`,
    key: `'subject.assigned:' || v_log::text`,
    audit: false,
  });

  return `
-- Creates or changes a queue: queue is { id?, name, subjectType, strategy?,
-- conditions?, rank?, enabled? }. conditions, the queue's territory, is a
-- FilterQuery over the subject type's rule fields; null matches every record.
create or replace function ${fn("save_assignment_queue")}(tenant ${ctx.idType}, queue jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_old ${t("queues")};
  v_row ${t("queues")};
  v_type text;
  v_conditions jsonb;
  v_fields jsonb;
begin
  if not ${ctx.scope.can("save_assignment_queue.tenant", n.manage)} then
    ${fail("ASSIGNMENT_FORBIDDEN", "You need assignment.manage to change assignment queues")}
  end if;
  if jsonb_typeof(queue) is distinct from 'object' then
    ${fail("ASSIGNMENT_INVALID", "queue must be an object", "22023")}
  end if;
  v_id := nullif(queue ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from ${t("queues")} x
    where x.${q("id")} = v_id and x.${q("tenant")} = save_assignment_queue.tenant for update;
    if v_old.${q("id")} is null then
      ${fail("ASSIGNMENT_NOT_FOUND", "No assignment queue in this organization has this id", "P0002")}
    end if;
  end if;
  v_type := coalesce(queue ->> 'subjectType', v_old.${q("subjectType")});
  if v_type is null or v_type !~ '^[a-z][a-z0-9_]{0,62}$' then
    ${fail("ASSIGNMENT_INVALID", "A queue needs a subject type", "22023")}
  end if;
  v_conditions := case when queue ? 'conditions' then nullif(queue -> 'conditions', 'null'::jsonb) else v_old.${q("conditions")} end;
  if v_conditions is not null then
    v_fields := ${rules.fn("rule_field_map")}(v_type);
    if v_fields = '{}'::jsonb then
      ${fail("ASSIGNMENT_FIELDS_MISSING", "No rule fields for this subject type; sync them first", "22023")}
    end if;
    perform ${rules.fn("rule_check")}(v_conditions, v_fields, 1);
  end if;
  if v_old.${q("id")} is null then
    insert into ${t("queues")} (${q("tenant")}, ${q("name")}, ${q("subjectType")}, ${q("strategy")}, ${q("conditions")}, ${q("rank")}, ${q("enabled")})
    values (save_assignment_queue.tenant, trim(queue ->> 'name'), v_type, coalesce(queue ->> 'strategy', 'round_robin'),
      v_conditions, coalesce((queue ->> 'rank')::integer, 0), coalesce((queue ->> 'enabled')::boolean, true))
    returning * into v_row;
  else
    update ${t("queues")} x set
      ${q("name")} = coalesce(trim(queue ->> 'name'), x.${q("name")}),
      ${q("subjectType")} = v_type,
      ${q("strategy")} = coalesce(queue ->> 'strategy', x.${q("strategy")}),
      ${q("conditions")} = v_conditions,
      ${q("rank")} = coalesce((queue ->> 'rank')::integer, x.${q("rank")}),
      ${q("enabled")} = coalesce((queue ->> 'enabled')::boolean, x.${q("enabled")}),
      ${q("updatedAt")} = now()
    where x.${q("id")} = v_old.${q("id")}
    returning * into v_row;
  end if;
  return ${queueJson("v_row")};
exception
  when unique_violation then
    ${fail("ASSIGNMENT_NAME_TAKEN", "Another assignment queue in this organization has this name", "23505")}
  when check_violation or not_null_violation then
    ${fail("ASSIGNMENT_INVALID", "A queue needs a name of at most 200 characters and a strategy of round_robin or weighted", "22023")}
end;
$$;
${userGrant(`${fn("save_assignment_queue")}(${ctx.idType}, jsonb)`)}

-- Replaces a queue's members: members is [{ userId, weight?, active? }], each
-- a member of the queue's organization. Members who stay keep their place in
-- the rotation.
create or replace function ${fn("set_assignment_members")}(queue uuid, members jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_queue ${t("queues")};
  v_item jsonb;
  v_users uuid[] := '{}';
  v_user uuid;
begin
  select * into v_queue from ${t("queues")} x where x.${q("id")} = set_assignment_members.queue for update;
  if v_queue.${q("id")} is null or not ${ctx.scope.can(`v_queue.${q("tenant")}`, n.manage)} then
    ${fail("ASSIGNMENT_NOT_FOUND", "No assignment queue you can manage has this id", "P0002")}
  end if;
  if jsonb_typeof(members) is distinct from 'array' or jsonb_array_length(members) > 200 then
    ${fail("ASSIGNMENT_INVALID", "members must be an array of at most 200 entries", "22023")}
  end if;
  for v_item in select x.value from jsonb_array_elements(members) x loop
    v_user := nullif(v_item ->> 'userId', '')::uuid;
    if v_user is null or not ${isMember("v_user", `v_queue.${q("tenant")}`, "mm")} then
      ${fail("ASSIGNMENT_MEMBER_INVALID", "Every member must be a member of the queue's organization", "22023")}
    end if;
    v_users := v_users || v_user;
    insert into ${t("members")} (${u("queue")}, ${u("tenant")}, ${u("user")}, ${u("weight")}, ${u("active")})
    values (v_queue.${q("id")}, v_queue.${q("tenant")}, v_user, coalesce((v_item ->> 'weight')::integer, 1), coalesce((v_item ->> 'active')::boolean, true))
    on conflict (${u("queue")}, ${u("user")}) do update set
      ${u("weight")} = excluded.${u("weight")},
      ${u("active")} = excluded.${u("active")};
  end loop;
  delete from ${t("members")} z where z.${u("queue")} = v_queue.${q("id")} and not (z.${u("user")} = any (v_users));
  return ${queueJson("v_queue")};
exception when check_violation then
  ${fail("ASSIGNMENT_INVALID", "A member's weight is between 1 and 100", "22023")}
end;
$$;
${userGrant(`${fn("set_assignment_members")}(uuid, jsonb)`)}

create or replace function ${fn("remove_assignment_queue")}(queue uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select x.${q("tenant")} into v_tenant from ${t("queues")} x where x.${q("id")} = remove_assignment_queue.queue;
  if v_tenant is null then
    return false;
  end if;
  if not ${ctx.scope.can("v_tenant", n.manage)} then
    ${fail("ASSIGNMENT_FORBIDDEN", "You need assignment.manage to remove an assignment queue")}
  end if;
  delete from ${t("queues")} x where x.${q("id")} = remove_assignment_queue.queue;
  return true;
end;
$$;
${userGrant(`${fn("remove_assignment_queue")}(uuid)`)}

-- The organization's queues, optionally of one subject type, in the order
-- assign tries them, with their members.
create or replace function ${fn("list_assignment_queues")}(tenant ${ctx.idType}, subject_type text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${ctx.scope.can("list_assignment_queues.tenant", n.read)} then
    ${fail("ASSIGNMENT_FORBIDDEN", "You need assignment.read to list assignment queues")}
  end if;
  return coalesce((
    select jsonb_agg(${queueJson("x")} order by x.${q("subjectType")}, x.${q("rank")}, x.${q("name")})
    from ${t("queues")} x
    where x.${q("tenant")} = list_assignment_queues.tenant
      and (list_assignment_queues.subject_type is null or x.${q("subjectType")} = list_assignment_queues.subject_type)
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_assignment_queues")}(${ctx.idType}, text)`)}

-- Picks an owner for a record: the first enabled queue of the subject type,
-- by rank, whose conditions match subject (the record's fields, keyed as the
-- rule fields' columns) and that has an active member. round_robin picks the
-- member assigned longest ago; weighted spreads records by weight (smooth
-- weighted round robin). Returns { queueId, userId, strategy }, or null when
-- no queue matches. The app writes the owner; this logs the pick.
create or replace function ${fn("assign_subject")}(tenant ${ctx.idType}, subject_type text, subject_id text, subject jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_queue ${t("queues")};
  v_fields jsonb;
  v_user uuid;
  v_total bigint;
  v_log uuid;
begin
  if not (${SERVICE_CALLER} or ${ctx.scope.can("assign_subject.tenant", n.assign)}) then
    ${fail("ASSIGNMENT_FORBIDDEN", "You need assignment.assign to assign records")}
  end if;
  if subject_id is null or length(subject_id) > 200 then
    ${fail("ASSIGNMENT_INVALID", "subject_id must be at most 200 characters", "22023")}
  end if;
  v_fields := ${rules.fn("rule_field_map")}(assign_subject.subject_type);
  for v_queue in
    select * from ${t("queues")} x
    where x.${q("tenant")} = assign_subject.tenant and x.${q("subjectType")} = assign_subject.subject_type and x.${q("enabled")}
    order by x.${q("rank")}, x.${q("name")}
  loop
    if v_queue.${q("conditions")} is not null
      and not ${rules.fn("rule_matches")}(v_queue.${q("conditions")}, coalesce(assign_subject.subject, '{}'::jsonb), v_fields, 'UTC', now()) then
      continue;
    end if;
    perform 1 from ${t("queues")} x where x.${q("id")} = v_queue.${q("id")} for update;
    if v_queue.${q("strategy")} = 'weighted' then
      select coalesce(sum(z.${u("weight")}), 0) into v_total from ${t("members")} z
      where z.${u("queue")} = v_queue.${q("id")} and z.${u("active")} and ${isMember(`z.${u("user")}`, `v_queue.${q("tenant")}`, "mw")};
      if v_total = 0 then
        continue;
      end if;
      update ${t("members")} z set ${u("credit")} = z.${u("credit")} + z.${u("weight")}
      where z.${u("queue")} = v_queue.${q("id")} and z.${u("active")} and ${isMember(`z.${u("user")}`, `v_queue.${q("tenant")}`, "mw")};
      select z.${u("user")} into v_user from ${t("members")} z
      where z.${u("queue")} = v_queue.${q("id")} and z.${u("active")} and ${isMember(`z.${u("user")}`, `v_queue.${q("tenant")}`, "mw")}
      order by z.${u("credit")} desc, z.${u("lastAssignedAt")} nulls first, z.${u("user")}
      limit 1;
      update ${t("members")} z set ${u("credit")} = z.${u("credit")} - v_total
      where z.${u("queue")} = v_queue.${q("id")} and z.${u("user")} = v_user;
    else
      select z.${u("user")} into v_user from ${t("members")} z
      where z.${u("queue")} = v_queue.${q("id")} and z.${u("active")} and ${isMember(`z.${u("user")}`, `v_queue.${q("tenant")}`, "mr")}
      order by z.${u("lastAssignedAt")} nulls first, z.${u("user")}
      limit 1;
      if v_user is null then
        continue;
      end if;
    end if;
    update ${t("members")} z set ${u("lastAssignedAt")} = clock_timestamp(), ${u("assignedCount")} = z.${u("assignedCount")} + 1
    where z.${u("queue")} = v_queue.${q("id")} and z.${u("user")} = v_user;
    insert into ${t("log")} (${g("tenant")}, ${g("queue")}, ${g("subjectType")}, ${g("subjectId")}, ${g("user")})
    values (v_queue.${q("tenant")}, v_queue.${q("id")}, v_queue.${q("subjectType")}, assign_subject.subject_id, v_user)
    returning ${g("id")} into v_log;
    ${assigned}
    return jsonb_build_object('queueId', v_queue.${q("id")}, 'userId', v_user, 'strategy', v_queue.${q("strategy")});
  end loop;
  return null;
end;
$$;
${userGrant(`${fn("assign_subject")}(${ctx.idType}, text, text, jsonb)`)}

-- The picks for a record, newest first: { queueId, userId, assignedAt }.
create or replace function ${fn("assignment_history")}(tenant ${ctx.idType}, subject_type text, subject_id text, max_count integer default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${ctx.scope.can("assignment_history.tenant", n.read)} then
    ${fail("ASSIGNMENT_FORBIDDEN", "You need assignment.read to read assignments")}
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('queueId', y.${g("queue")}, 'userId', y.${g("user")}, 'assignedAt', y.${g("assignedAt")}) order by y.${g("assignedAt")} desc, y.${g("id")})
    from (
      select x.* from ${t("log")} x
      where x.${g("tenant")} = assignment_history.tenant and x.${g("subjectType")} = assignment_history.subject_type
        and x.${g("subjectId")} = assignment_history.subject_id
      order by x.${g("assignedAt")} desc, x.${g("id")}
      limit ${pageSize("assignment_history.max_count", 20, 200)}
    ) y
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("assignment_history")}(${ctx.idType}, text, text, integer)`)}
`;
}

function build(ctx: BlockSqlContext): string {
  const n = names(ctx);

  return `${schemaPreamble(ctx)}
-- Assignment: queues of members that pick an owner for new records, by
-- round robin or weight, within a territory of rule conditions.
${tables(ctx, n)}${functions(ctx, n)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "save_assignment_queue",
      args: ["{id}", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "set_assignment_members",
      args: ["uuid", "jsonb"],
      returns: "jsonb",
    },
    { name: "remove_assignment_queue", args: ["uuid"], returns: "boolean" },
    {
      name: "list_assignment_queues",
      args: ["{id}", "text"],
      returns: "jsonb",
    },
    {
      name: "assign_subject",
      args: ["{id}", "text", "text", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "assignment_history",
      args: ["{id}", "text", "text", "integer"],
      returns: "jsonb",
    },
  ];
}

export const ASSIGNMENT: BlockSqlDefinition = {
  name: "assignment",
  scopes: ["tenant"],
  title: "Assignment",
  description:
    "Queues of members that pick an owner for new leads, deals or tickets: round robin or weighted, within a territory written as rule conditions, with a log of every pick.",
  requires: ["tenant", "access", "rules"],
  integrates: ["outbox", "data-lifecycle"],
  target: "schema",
  modes: ["managed"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
