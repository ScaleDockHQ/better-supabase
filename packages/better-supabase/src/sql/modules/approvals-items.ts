import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";
import type { ApprovalSqlKit } from "./approvals-steps.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { fail, SERVICE_CALLER, serviceGrant, userGrant } from "../shared.ts";
import { lockModuleTable } from "./over-app.ts";

/** The most items one request carries. */
const MAX_ITEMS = 200;

/** The `approval_items` table: what a request asks to approve, one row each. */
export const ITEM_TABLES = {
  items: {
    name: "approval_items",
    app: { writes: false },
    lifecycle: { tenant: "tenant", user: "decidedBy", export: true },
    columns: {
      id: "id",
      request: "request_id",
      tenant: "tenant_id",
      key: "key",
      label: "label",
      payload: "payload",
      permission: "permission",
      dependsOn: "depends_on",
      status: "status",
      createdType: "created_type",
      createdId: "created_id",
      decidedBy: "decided_by",
      decidedAt: "decided_at",
      createdAt: "created_at",
    },
  },
} as const;

/** The item functions the module exposes. */
export function approvalItemsContract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "request_approval_items",
      args: [
        "{id}",
        "text",
        "text",
        "text",
        "jsonb",
        "text",
        "jsonb",
        "text",
        "jsonb",
        "uuid",
      ],
      returns: "jsonb",
    },
    {
      name: "decide_approval_items",
      args: ["uuid", "jsonb", "uuid"],
      returns: "jsonb",
    },
    {
      name: "record_approval_created",
      args: ["uuid", "text", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "settle_approval",
      args: ["uuid", "text", "text"],
      returns: "jsonb",
    },
  ];
}

/** What the item functions need from the rest of the approvals module. */
export interface ApprovalItemsSql {
  readonly tenantless: boolean;
  /** A SQL boolean: whether `row` is a request another module decides. */
  readonly linked: (subjectType: string) => string;
  readonly read: string;
  readonly manage: string;
}

/** The item as the SQL functions return it. */
function itemJson(ctx: BlockSqlContext, row: string): string {
  const i = (column: string): string => `${row}.${ctx.col("items", column)}`;

  return `jsonb_build_object('id', ${i("id")}, 'key', ${i("key")}, 'label', ${i("label")}, 'payload', ${i("payload")}, 'permission', ${i("permission")}, 'dependsOn', to_jsonb(${i("dependsOn")}), 'status', ${i("status")}, 'createdType', ${i("createdType")}, 'createdId', ${i("createdId")}, 'decidedBy', ${i("decidedBy")}, 'decidedAt', ${i("decidedAt")}, 'createdAt', ${i("createdAt")})`;
}

/** The request's items as a jsonb array, in the order they were filed. */
export function itemsOf(ctx: BlockSqlContext, requestId: string): string {
  const items = ctx.table("items");

  return `coalesce((
      select jsonb_agg(${itemJson(ctx, "x")} order by x.${ctx.col("items", "createdAt")}, x.${ctx.col("items", "key")})
      from ${items} x where x.${ctx.col("items", "request")} = ${requestId}
    ), '[]'::jsonb)`;
}

/** The `approval_items` table with its read policy. */
export function itemsTableSql(
  ctx: BlockSqlContext,
  k: ApprovalSqlKit,
  sql: ApprovalItemsSql,
): string {
  const items = ctx.table("items");
  const i = (column: string): string => ctx.col("items", column);

  return `create table if not exists ${items} (
  ${i("id")} uuid primary key default gen_random_uuid(),
  ${i("request")} uuid not null references ${k.requests} (${k.c("id")}) on delete cascade,
  ${i("tenant")} ${ctx.idType}${sql.tenantless ? "" : " not null"},
  ${i("key")} text not null check (length(${i("key")}) between 1 and 200),
  ${i("label")} text check (${i("label")} is null or length(${i("label")}) <= 500),
  ${i("payload")} jsonb not null default '{}'::jsonb,
  ${i("permission")} text,
  ${i("dependsOn")} text[] not null default '{}',
  ${i("status")} text not null default 'pending' check (${i("status")} in ('pending', 'approved', 'rejected')),
  ${i("createdType")} text,
  ${i("createdId")} text,
  ${i("decidedBy")} uuid,
  ${i("decidedAt")} timestamptz,
  ${i("createdAt")} timestamptz not null default now(),
  unique (${i("request")}, ${i("key")}),
  check ((${i("createdType")} is null) = (${i("createdId")} is null))
);
create index if not exists ${sqlIdent(`${ctx.tableName("items").name}_tenant_idx`)} on ${items} (${i("tenant")}, ${i("status")});
${lockModuleTable(ctx, "items", { read: true })}
${renderPolicy(makePolicy({ table: items, name: ctx.naming.rename("approval_items_read"), command: "select", roles: ["authenticated"], using: ctx.scope.check(i("tenant"), sql.read) }), { target: items })}
`;
}

/**
 * Request_approval_items, decide_approval_items, record_approval_created and
 * settle_approval: a request that asks for several things, each decided on its
 * own, and the service role closing a request itself.
 */
export function itemsSql(
  ctx: BlockSqlContext,
  k: ApprovalSqlKit,
  sql: ApprovalItemsSql,
): string {
  const { requests, decisions, c, d, has, fn, stepOf, policyOf } = k;
  const { record, json, decided, notFound, also, alsoValue } = k;
  const items = ctx.table("items");
  const i = (column: string): string => ctx.col("items", column);

  const can = (tenant: string, permission: string): string =>
    sql.tenantless
      ? `case when ${tenant} is null then ${ctx.staff(permission)} else ${ctx.can("tenant", tenant, permission)} end`
      : ctx.can("tenant", tenant, permission);

  const unsupported = fail(
    "APPROVAL_ITEMS_UNSUPPORTED",
    "the module that filed this request decides it, so it takes no items",
    "22023",
  );

  const withItems = (row: string): string =>
    `${json(row)} || jsonb_build_object('items', ${itemsOf(ctx, `${row}.${c("id")}`)})`;

  return `-- Files a request that asks for several things. Each item carries its own
-- permission and may depend on items filed before it. request_approval
-- checks the caller, the policy and the record, so an item request is filed
-- under the same rules as any other, and the items are written in the same
-- transaction.
create or replace function ${fn("request_approval_items")}(tenant ${ctx.idType}, subject_type text, subject_id text, action text, items jsonb, reason text default null, payload jsonb default '{}'::jsonb, fingerprint text default null, policy jsonb default null, requested_by uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_result jsonb;
  v_item jsonb;
  v_key text;
  v_seen text[] := '{}';
  v_after text[];
  v_depends text[];
begin
  if jsonb_typeof(request_approval_items.items) is distinct from 'array' or jsonb_array_length(request_approval_items.items) = 0 then
    ${fail("APPROVAL_ITEMS_INVALID", "items must be a non-empty array", "22023")}
  end if;
  if jsonb_array_length(request_approval_items.items) > ${MAX_ITEMS} then
    ${fail("APPROVAL_ITEMS_INVALID", `a request takes at most ${MAX_ITEMS} items`, "22023")}
  end if;
  if ${sql.linked("request_approval_items.subject_type")} then
    ${unsupported}
  end if;
  for v_item in select e.value from jsonb_array_elements(request_approval_items.items) e loop
    if jsonb_typeof(v_item) is distinct from 'object' or jsonb_typeof(v_item -> 'key') is distinct from 'string' or length(btrim(v_item ->> 'key')) not between 1 and 200 then
      ${fail("APPROVAL_ITEMS_INVALID", "each item needs a key of 1 to 200 characters", "22023")}
    end if;
    v_key := v_item ->> 'key';
    if v_key = any(v_seen) then
      ${fail("APPROVAL_ITEMS_INVALID", "item keys must be unique", "22023")}
    end if;
    if v_item ? 'dependsOn' and jsonb_typeof(v_item -> 'dependsOn') is distinct from 'array' then
      ${fail("APPROVAL_ITEMS_INVALID", "dependsOn must be an array of item keys", "22023")}
    end if;
    v_depends := array(select jsonb_array_elements_text(coalesce(v_item -> 'dependsOn', '[]'::jsonb)));
    if exists (select 1 from unnest(v_depends) dep where dep <> all(v_seen)) then
      ${fail("APPROVAL_ITEMS_INVALID", "an item depends only on items listed before it", "22023")}
    end if;
    v_seen := v_seen || v_key;
  end loop;
  v_result := ${fn("request_approval")}(
    tenant => request_approval_items.tenant,
    subject_type => request_approval_items.subject_type,
    subject_id => request_approval_items.subject_id,
    action => request_approval_items.action,
    reason => request_approval_items.reason,
    payload => request_approval_items.payload,
    fingerprint => request_approval_items.fingerprint,
    policy => request_approval_items.policy,
    requested_by => request_approval_items.requested_by
  );
  insert into ${items} (${i("request")}, ${i("tenant")}, ${i("key")}, ${i("label")}, ${i("payload")}, ${i("permission")}, ${i("dependsOn")})
  select (v_result ->> 'id')::uuid, request_approval_items.tenant, e.value ->> 'key', e.value ->> 'label',
    case when jsonb_typeof(e.value -> 'payload') = 'object' then e.value -> 'payload' else '{}'::jsonb end,
    nullif(e.value ->> 'permission', ''),
    array(select jsonb_array_elements_text(coalesce(e.value -> 'dependsOn', '[]'::jsonb)))
  from jsonb_array_elements(request_approval_items.items) with ordinality e(value, position)
  order by e.position;
  return v_result || jsonb_build_object('items', ${itemsOf(ctx, "(v_result ->> 'id')::uuid")});
end;
$$;
${userGrant(`${fn("request_approval_items")}(${ctx.idType}, text, text, text, jsonb, text, jsonb, text, jsonb, uuid)`)}

-- Approves or rejects items of a pending request. An item with a permission
-- needs the caller to hold it; one without follows the step's approvers. An
-- item can't be approved while an item it depends on is pending or rejected,
-- and rejecting an item rejects the pending items that depend on it. The
-- request settles when no item is pending: approved when any item was
-- approved, rejected otherwise. The service role decides for the user in
-- decided_by, who is recorded on the items.
create or replace function ${fn("decide_approval_items")}(request_id uuid, decisions jsonb, decided_by uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_req ${requests}%rowtype;
  v_item ${items}%rowtype;
  v_each jsonb;
  v_decision text;
  v_service boolean := ${SERVICE_CALLER};
  v_actor uuid := coalesce(decide_approval_items.decided_by, auth.uid());
  v_pending integer;
  v_approved integer;
  v_outcome text;
begin
  if jsonb_typeof(decide_approval_items.decisions) is distinct from 'array' or jsonb_array_length(decide_approval_items.decisions) = 0 then
    ${fail("APPROVAL_DECISION_INVALID", "decisions must be a non-empty array", "22023")}
  end if;
  if decide_approval_items.decided_by is not null and not v_service and decide_approval_items.decided_by is distinct from auth.uid() then
    ${fail("APPROVAL_FORBIDDEN", "only the service role decides for another user")}
  end if;
  select * into v_req from ${requests} r where r.${c("id")} = decide_approval_items.request_id for update;
  if not found then
    ${notFound}
  end if;
  if v_req.${c("status")} <> 'pending' then
    ${fail("APPROVAL_CLOSED", "this request is no longer pending", "22023")}
  end if;${
    has("expiresAt")
      ? `
  if v_req.${c("expiresAt")} is not null and v_req.${c("expiresAt")} <= now() then
    ${fail("APPROVAL_EXPIRED", "this request has expired", "22023")}
  end if;`
      : ""
  }
  if not exists (select 1 from ${items} x where x.${i("request")} = v_req.${c("id")}) then
    ${fail("APPROVAL_ITEMS_NONE", "this request has no items; use decide_approval", "22023")}
  end if;
  if v_actor is not null and v_actor = v_req.${c("requestedBy")} and coalesce(${policyOf("v_req")} ->> 'mode', 'authorize') <> 'confirm'
    and not coalesce((${policyOf("v_req")} ->> 'selfApproval')::boolean, false) then
    ${fail("APPROVAL_FORBIDDEN", "the requester can't decide their own request")}
  end if;
  for v_each in select e.value from jsonb_array_elements(decide_approval_items.decisions) e loop
    v_decision := v_each ->> 'decision';
    if v_decision is null or v_decision not in ('approved', 'rejected') or jsonb_typeof(v_each -> 'key') is distinct from 'string' then
      ${fail("APPROVAL_DECISION_INVALID", "each decision needs a key and a decision of approved or rejected", "22023")}
    end if;
    select * into v_item from ${items} x
    where x.${i("request")} = v_req.${c("id")} and x.${i("key")} = v_each ->> 'key' for update;
    if not found then
      ${fail("APPROVAL_ITEM_NOT_FOUND", "this request has no such item", "P0002")}
    end if;
    if v_item.${i("status")} <> 'pending' then
      ${fail("APPROVAL_ITEM_CLOSED", "this item is no longer pending", "22023")}
    end if;
    if not v_service then
      if v_item.${i("permission")} is not null then
        if not (${can(`v_req.${c("tenant")}`, `v_item.${i("permission")}`)}) then
          ${fail("APPROVAL_FORBIDDEN", "not an approver for this item")}
        end if;
      elsif not ${fn("approval_eligible")}(v_req.${c("id")}) then
        ${fail("APPROVAL_FORBIDDEN", "not an approver for this item")}
      end if;
    end if;
    if v_decision = 'approved' and exists (
      select 1 from ${items} dep
      where dep.${i("request")} = v_req.${c("id")} and dep.${i("key")} = any(v_item.${i("dependsOn")}) and dep.${i("status")} <> 'approved'
    ) then
      ${fail("APPROVAL_ITEM_BLOCKED", "an item this one depends on is not approved", "22023")}
    end if;
    ${ctx.hook("before_approval_decide", [
      ["uuid", `v_req.${c("id")}`],
      ["text", "v_decision"],
    ])}
    update ${items} x set ${i("status")} = v_decision, ${i("decidedBy")} = v_actor, ${i("decidedAt")} = now()
    where x.${i("id")} = v_item.${i("id")};
    if v_decision = 'rejected' then
      with recursive blocked(key) as (
        select y.${i("key")} from ${items} y
        where y.${i("request")} = v_req.${c("id")} and v_item.${i("key")} = any(y.${i("dependsOn")})
        union
        select y.${i("key")} from ${items} y join blocked b on b.key = any(y.${i("dependsOn")})
        where y.${i("request")} = v_req.${c("id")}
      )
      update ${items} x set ${i("status")} = 'rejected', ${i("decidedBy")} = v_actor, ${i("decidedAt")} = now()
      where x.${i("request")} = v_req.${c("id")} and x.${i("status")} = 'pending' and x.${i("key")} in (select key from blocked);
    end if;
  end loop;
  select count(*) filter (where x.${i("status")} = 'pending'), count(*) filter (where x.${i("status")} = 'approved')
    into v_pending, v_approved
  from ${items} x where x.${i("request")} = v_req.${c("id")};
  if v_pending = 0 then
    v_outcome := case when v_approved > 0 then 'approved' else 'rejected' end;
    insert into ${decisions} (${d("request")}, ${d("tenant")}, ${d("step")}, ${d("approver")}, ${d("decision")})
    values (v_req.${c("id")}, v_req.${c("tenant")}, ${stepOf("v_req")}, v_actor, ${ctx.cast("decisions", "decision", "v_outcome")})
    on conflict do nothing;
    update ${requests} r set ${c("status")} = ${ctx.cast("requests", "status", "v_outcome")}${decided}
      where r.${c("id")} = v_req.${c("id")} returning * into v_req;
    if v_outcome = 'approved' then
      perform ${fn("approval_finalize")}(v_req.${c("id")});
    else
      ${record("approval.rejected", "v_req", true)}
      perform ${fn("approval_notify")}(v_req.${c("id")}, 'rejected');
    end if;
  end if;
  ${ctx.hook("after_approval_decide", [
    ["uuid", `v_req.${c("id")}`],
    ["text", `v_req.${c("status")}`],
  ])}
  return ${withItems("v_req")};
end;
$$;
${userGrant(`${fn("decide_approval_items")}(uuid, jsonb, uuid)`)}

-- Notes the record an approved item created, so a retry of the run that
-- creates it finds the record instead of creating another. The requester, a
-- manager or the service role records it, once per item.
create or replace function ${fn("record_approval_created")}(request_id uuid, item_key text, created_type text, created_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_req ${requests}%rowtype;
  v_item ${items}%rowtype;
begin
  select * into v_req from ${requests} r where r.${c("id")} = record_approval_created.request_id;
  if not found then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or coalesce(v_req.${c("requestedBy")} = auth.uid(), false) or ${can(`v_req.${c("tenant")}`, sql.manage)}) then
    ${fail("APPROVAL_FORBIDDEN", "only the requester or a manager records what an item created")}
  end if;
  if nullif(btrim(record_approval_created.created_type), '') is null or nullif(btrim(record_approval_created.created_id), '') is null then
    ${fail("APPROVAL_ITEMS_INVALID", "created_type and created_id are required", "22023")}
  end if;
  select * into v_item from ${items} x
  where x.${i("request")} = v_req.${c("id")} and x.${i("key")} = record_approval_created.item_key for update;
  if not found then
    ${fail("APPROVAL_ITEM_NOT_FOUND", "this request has no such item", "P0002")}
  end if;
  if v_item.${i("status")} <> 'approved' then
    ${fail("APPROVAL_ITEM_CLOSED", "only an approved item records what it created", "22023")}
  end if;
  if v_item.${i("createdType")} is not null then
    ${fail("APPROVAL_ITEM_RECORDED", "this item already recorded what it created", "23505")}
  end if;
  update ${items} x set ${i("createdType")} = record_approval_created.created_type, ${i("createdId")} = record_approval_created.created_id
  where x.${i("id")} = v_item.${i("id")} returning * into v_item;
  return ${itemJson(ctx, "v_item")};
end;
$$;
${userGrant(`${fn("record_approval_created")}(uuid, text, text, text)`)}

-- Closes a pending request on the system's behalf, such as a run that
-- finished or gave up. It writes a decision without an approver, settles the
-- items still pending to the outcome, and records the same events and runs the
-- same final approval as a person's decision, so waiters wake.
create or replace function ${fn("settle_approval")}(request_id uuid, outcome text, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_req ${requests}%rowtype;
begin
  if settle_approval.outcome not in ('approved', 'rejected') then
    ${fail("APPROVAL_DECISION_INVALID", "outcome must be approved or rejected", "22023")}
  end if;
  select * into v_req from ${requests} r where r.${c("id")} = settle_approval.request_id for update;
  if not found then
    ${notFound}
  end if;
  if v_req.${c("status")} <> 'pending' then
    ${fail("APPROVAL_CLOSED", "this request is no longer pending", "22023")}
  end if;
  ${ctx.hook("before_approval_decide", [
    ["uuid", `v_req.${c("id")}`],
    ["text", "settle_approval.outcome"],
  ])}
  update ${items} x set ${i("status")} = settle_approval.outcome, ${i("decidedAt")} = now()
  where x.${i("request")} = v_req.${c("id")} and x.${i("status")} = 'pending';
  insert into ${decisions} (${d("request")}, ${d("tenant")}, ${d("step")}, ${d("approver")}, ${d("decision")}${also("decisions", "comment")})
  values (v_req.${c("id")}, v_req.${c("tenant")}, ${stepOf("v_req")}, null, ${ctx.cast("decisions", "decision", "settle_approval.outcome")}${alsoValue("decisions", "comment", "left('system' || coalesce(': ' || settle_approval.reason, ''), 2000)")});
  update ${requests} r set ${c("status")} = ${ctx.cast("requests", "status", "settle_approval.outcome")}${decided}
    where r.${c("id")} = v_req.${c("id")} returning * into v_req;
  if settle_approval.outcome = 'approved' then
    perform ${fn("approval_finalize")}(v_req.${c("id")});
  else
    ${record("approval.rejected", "v_req", true)}
    perform ${fn("approval_notify")}(v_req.${c("id")}, 'rejected');
  end if;
  ${ctx.hook("after_approval_decide", [
    ["uuid", `v_req.${c("id")}`],
    ["text", `v_req.${c("status")}`],
  ])}
  return ${withItems("v_req")};
end;
$$;
${serviceGrant(`${fn("settle_approval")}(uuid, text, text)`)}`;
}
