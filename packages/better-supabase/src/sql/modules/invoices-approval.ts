import type { InvoicesEvents } from "../../blocks/invoices/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlTableSpec,
} from "../context.ts";
import type { CollectionHelpers } from "./invoices-collections.ts";
import type { InvoiceNames } from "./invoices-names.ts";
import type { BlockSqlOperations } from "./permissions-model.ts";

import { hasLegalEntityColumn } from "../numbering-sql.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { fail, serviceGrant, userGrant } from "../shared.ts";
import { lockModuleTable } from "./over-app.ts";

const INVOICE = [
  "organizationId",
  "invoiceId",
  "subjectType",
  "subjectId",
  "identifier",
] as const;

/** The event a purchase approval records. */
export const APPROVAL_EVENTS: BlockSqlEvents<InvoicesEvents> = {
  "invoice.approved": {
    subject: "invoices",
    payload: [...INVOICE, "level", "approvalStatus"],
  },
};

/** What approval adds to the invoice names. */
export interface ApprovalNames {
  /** `invoices.approve`: approves a purchase bill at its level. */
  readonly approve: string;
}

export function approvalNames(
  ctx: BlockSqlContext,
  keys: BlockSqlOperations<"invoices">,
): ApprovalNames {
  return { approve: ctx.permission("approve", keys.approve) };
}

/**
 * The `invoice_approval_levels` table: who approves a purchase bill of at least
 * an amount, per organization or per legal entity.
 */
export const APPROVAL_LEVELS_TABLE: BlockSqlTableSpec = {
  name: "invoice_approval_levels",
  app: {},
  optionalTable: true,
  lifecycle: { tenant: "tenant", export: true },
  columns: {
    id: "id",
    tenant: "tenant_id",
    legalEntity: "legal_entity_id",
    level: "level",
    minAmount: "min_amount",
    currency: "currency",
    approver: "approver_id",
    createdAt: "created_at",
  },
};

/** The `invoice_approvals` table: one approval of a bill at one level. */
export const APPROVALS_TABLE: BlockSqlTableSpec = {
  name: "invoice_approvals",
  app: {},
  optionalTable: true,
  lifecycle: { tenant: "tenant", export: true },
  columns: {
    id: "id",
    tenant: "tenant_id",
    invoice: "invoice_id",
    level: "level",
    approver: "approver_id",
    comment: "comment",
    decidedAt: "decided_at",
  },
};

/** Whether purchase bills can be approved on this invoices table. */
function hasApproval(ctx: BlockSqlContext): boolean {
  return (
    ctx.has("invoices", "direction") &&
    ctx.hasTable("approvalLevels") &&
    ctx.hasTable("approvals")
  );
}

/** The level and approval tables with their indexes and read policies. */
export function approvalTablesSql(
  ctx: BlockSqlContext,
  invoices: string,
  invoiceId: string,
  read: string,
): string {
  if (!hasApproval(ctx)) {
    return "";
  }

  const levels = ctx.table("approvalLevels");
  const approvals = ctx.table("approvals");
  const l = (column: string): string => ctx.col("approvalLevels", column);
  const a = (column: string): string => ctx.col("approvals", column);

  const readPolicy = (name: string, tenant: string, target: string): string =>
    renderPolicy(
      makePolicy({
        table: target,
        name: ctx.naming.rename(name),
        command: "select",
        roles: ["authenticated"],
        using: ctx.scope.check(tenant, read),
      }),
      { drop: true, target },
    );

  return `
create table if not exists ${levels} (
  ${l("id")} uuid primary key default gen_random_uuid(),
  ${l("tenant")} ${ctx.idType} not null,
  -- Null: the level counts for every legal entity without levels of its own.
  ${l("legalEntity")} uuid,
  ${l("level")} integer not null check (${l("level")} >= 1),
  ${l("minAmount")} bigint not null check (${l("minAmount")} >= 0),
  ${l("currency")} text check (${l("currency")} is null or ${l("currency")} ~ '^[A-Z]{3}$'),
  ${l("approver")} uuid not null,
  ${l("createdAt")} timestamptz not null default now()
);
create unique index if not exists ${ctx.naming.rename("invoice_approval_levels_level_key")} on ${levels} (${l("tenant")}, coalesce(${l("legalEntity")}, '00000000-0000-0000-0000-000000000000'::uuid), ${l("level")});
${lockModuleTable(ctx, "approvalLevels", { read: true })}
${readPolicy("invoice_approval_levels_read", l("tenant"), levels)}

create table if not exists ${approvals} (
  ${a("id")} uuid primary key default gen_random_uuid(),
  ${a("tenant")} ${ctx.idType} not null,
  ${a("invoice")} uuid not null references ${invoices} (${invoiceId}) on delete cascade,
  ${a("level")} integer not null check (${a("level")} >= 1),
  ${a("approver")} uuid not null,
  ${a("comment")} text check (${a("comment")} is null or length(${a("comment")}) <= 2000),
  ${a("decidedAt")} timestamptz not null default now(),
  unique (${a("invoice")}, ${a("level")})
);
create index if not exists ${ctx.naming.rename("invoice_approvals_tenant_idx")} on ${approvals} (${a("tenant")}, ${a("invoice")});
${lockModuleTable(ctx, "approvals", { read: true })}
${readPolicy("invoice_approvals_read", a("tenant"), approvals)}
`;
}

/**
 * The status of a bill's approval as a SQL expression for the row `alias`:
 * `not_required`, `pending` or `approved`, null for a sales invoice.
 */
export function approvalStatusSql(
  ctx: BlockSqlContext,
  n: InvoiceNames,
  alias: string,
): string {
  if (!hasApproval(ctx)) {
    return "null::text";
  }

  return `case when ${alias}.${ctx.col("invoices", "direction")} = 'purchase' then ${n.fn("invoice_approval_state")}(${alias}.${ctx.col("invoices", "id")}) ->> 'status' end`;
}

/**
 * Approval levels by amount and legal entity, `approve_purchase_invoice` and
 * the status a payment batch checks.
 */
export function approvalSql(
  ctx: BlockSqlContext,
  n: InvoiceNames,
  h: CollectionHelpers,
): string {
  if (!hasApproval(ctx)) {
    return "";
  }

  const { fn, t } = n;
  const { i } = h;
  const lv = (column: string): string => ctx.col("approvalLevels", column);
  const ap = (column: string): string => ctx.col("approvals", column);
  const levels = ctx.table("approvalLevels");
  const approvals = ctx.table("approvals");

  const entity = hasLegalEntityColumn(ctx, "invoices")
    ? "v_row.legal_entity_id"
    : "null::uuid";

  const allowed = (tenant: string, permission: string): string =>
    `(${n.service} or ${ctx.scope.can(tenant, permission)})`;

  return `
-- The approval a purchase bill needs: the levels of its legal entity (or the
-- organization's, when the entity has none) whose minimum amount the bill's
-- total reaches in the level's currency. Every such level needs its approver.
-- Returns { status, required, approved, pending }; status is not_required,
-- pending or approved. Internal: payment batches call it.
create or replace function ${fn("invoice_approval_state")}(invoice uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${t("invoices")};
  v_entity uuid;
  v_scoped boolean;
  v_required jsonb;
  v_approved jsonb;
  v_pending jsonb;
  v_status text;
begin
  select * into v_row from ${t("invoices")} x where x.${i("id")} = invoice_approval_state.invoice;
  if not found then
    return null;
  end if;
  if v_row.${i("direction")} <> 'purchase' or ${h.kd(`v_row.${i("kind")}`, ["invoice"], true)} then
    return jsonb_build_object('status', 'not_required', 'required', '[]'::jsonb, 'approved', '[]'::jsonb, 'pending', '[]'::jsonb);
  end if;
  v_entity := ${entity};
  v_scoped := v_entity is not null and exists (
    select 1 from ${levels} l where l.${lv("tenant")} = v_row.${i("tenant")} and l.${lv("legalEntity")} = v_entity
  );
  select coalesce(jsonb_agg(l.${lv("level")} order by l.${lv("level")}), '[]'::jsonb),
    coalesce(jsonb_agg(l.${lv("level")} order by l.${lv("level")}) filter (where a.${ap("id")} is not null), '[]'::jsonb),
    coalesce(jsonb_agg(jsonb_build_object('level', l.${lv("level")}, 'approverId', l.${lv("approver")}, 'minAmount', l.${lv("minAmount")}::text) order by l.${lv("level")}) filter (where a.${ap("id")} is null), '[]'::jsonb)
  into v_required, v_approved, v_pending
  from ${levels} l
  left join ${approvals} a on a.${ap("invoice")} = v_row.${i("id")} and a.${ap("level")} = l.${lv("level")}
  where l.${lv("tenant")} = v_row.${i("tenant")}
    and l.${lv("legalEntity")} is not distinct from (case when v_scoped then v_entity end)
    and l.${lv("minAmount")} <= v_row.${i("total")}
    and (l.${lv("currency")} is null or l.${lv("currency")} = v_row.${i("currency")}::text);
  v_status := case when jsonb_array_length(v_required) = 0 then 'not_required'
    when jsonb_array_length(v_pending) = 0 then 'approved' else 'pending' end;
  return jsonb_build_object('status', v_status, 'required', v_required, 'approved', v_approved, 'pending', v_pending);
end;
$$;
${serviceGrant(`${fn("invoice_approval_state")}(uuid)`)}
revoke execute on function ${fn("invoice_approval_state")}(uuid) from public, anon, authenticated;

-- Replaces the approval levels of an organization, or of one legal entity.
-- levels: [{ minAmount, currency?, approverId }]; they are numbered from 1 in
-- order of minAmount. A bill needs every level its total reaches, so a
-- bigger bill needs more approvers. Approvals already given keep their level
-- number. Needs invoices.manage.
create or replace function ${fn("set_invoice_approval_levels")}(tenant ${ctx.idType}, levels jsonb, legal_entity_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not ${allowed("set_invoice_approval_levels.tenant", n.manage)} then
    ${fail("INVOICE_FORBIDDEN", "not allowed to manage invoices in this organization", "42501")}
  end if;
  if jsonb_typeof(set_invoice_approval_levels.levels) is distinct from 'array'
    or jsonb_array_length(set_invoice_approval_levels.levels) > 20
    or exists (
      select 1 from jsonb_array_elements(set_invoice_approval_levels.levels) x
      where jsonb_typeof(x.value) <> 'object'
        or coalesce(x.value ->> 'minAmount', '') !~ '^[0-9]{1,18}$'
        or coalesce(x.value ->> 'approverId', '') !~ '^[0-9a-fA-F-]{36}$'
        or (x.value ->> 'currency' is not null and upper(x.value ->> 'currency') !~ '^[A-Z]{3}$')
    ) then
    ${fail("INVOICE_APPROVAL_LEVELS_INVALID", "levels is an array of at most 20 { minAmount, currency?, approverId }", "22023")}
  end if;
  delete from ${levels} l
  where l.${lv("tenant")} = set_invoice_approval_levels.tenant
    and l.${lv("legalEntity")} is not distinct from set_invoice_approval_levels.legal_entity_id;
  insert into ${levels} (${lv("tenant")}, ${lv("legalEntity")}, ${lv("level")}, ${lv("minAmount")}, ${lv("currency")}, ${lv("approver")})
  select set_invoice_approval_levels.tenant, set_invoice_approval_levels.legal_entity_id,
    (row_number() over (order by (x.value ->> 'minAmount')::bigint, x.ordinality))::integer,
    (x.value ->> 'minAmount')::bigint, upper(nullif(x.value ->> 'currency', '')), (x.value ->> 'approverId')::uuid
  from jsonb_array_elements(set_invoice_approval_levels.levels) with ordinality x;
  return ${fn("list_invoice_approval_levels")}(set_invoice_approval_levels.tenant);
end;
$$;
${userGrant(`${fn("set_invoice_approval_levels")}(${ctx.idType}, jsonb, uuid)`)}

create or replace function ${fn("list_invoice_approval_levels")}(tenant ${ctx.idType})
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${allowed("list_invoice_approval_levels.tenant", n.read)} then
    ${fail("INVOICE_FORBIDDEN", "not allowed to read this organization's invoices", "42501")}
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('legalEntityId', l.${lv("legalEntity")}, 'level', l.${lv("level")},
        'minAmount', l.${lv("minAmount")}::text, 'currency', l.${lv("currency")}, 'approverId', l.${lv("approver")})
      order by l.${lv("legalEntity")} nulls first, l.${lv("level")})
    from ${levels} l where l.${lv("tenant")} = list_invoice_approval_levels.tenant
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_invoice_approval_levels")}(${ctx.idType})`)}

-- The approval of a purchase bill: its status and the levels required,
-- approved and pending.
create or replace function ${fn("purchase_invoice_approval_status")}(invoice uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${t("invoices")};
begin
  select * into v_row from ${t("invoices")} x where x.${i("id")} = purchase_invoice_approval_status.invoice and ${h.can("x", n.read)};
  if v_row.${i("id")} is null then
    ${fail("INVOICE_NOT_FOUND", "no such invoice you can read", "P0002")}
  end if;
  return ${fn("invoice_approval_state")}(v_row.${i("id")});
end;
$$;
${userGrant(`${fn("purchase_invoice_approval_status")}(uuid)`)}

-- Approves a purchase bill at every pending level the caller is the approver
-- of; the service role approves the lowest pending level for its approver.
-- Needs invoices.approve and an open bill. Returns the bill with its approval.
create or replace function ${fn("approve_purchase_invoice")}(invoice uuid, comment text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("invoices")};
  v_state jsonb;
  v_level record;
  v_actor uuid := auth.uid();
  v_done integer := 0;
  v_last integer;
begin
  select * into v_row from ${t("invoices")} x
  where x.${i("id")} = approve_purchase_invoice.invoice and ${allowed(`x.${i("tenant")}`, n.approve)} for update;
  if v_row.${i("id")} is null then
    ${fail("INVOICE_NOT_FOUND", "no such invoice you can approve", "P0002")}
  end if;
  if v_row.${i("direction")} <> 'purchase' or ${h.kd(`v_row.${i("kind")}`, ["invoice"], true)} or ${h.st(`v_row.${i("status")}`, ["issued", "partially_paid"], true)} then
    ${fail("INVOICE_NOT_APPROVABLE", "only an open purchase bill is approved", "55000")}
  end if;
  if length(approve_purchase_invoice.comment) > 2000 then
    ${fail("INVOICE_APPROVAL_INVALID", "a comment has at most 2000 characters", "22023")}
  end if;
  v_state := ${fn("invoice_approval_state")}(v_row.${i("id")});
  if v_state ->> 'status' = 'not_required' then
    ${fail("INVOICE_APPROVAL_NOT_REQUIRED", "no approval level applies to this bill", "55000")}
  end if;
  if v_state ->> 'status' = 'approved' then
    ${fail("INVOICE_ALREADY_APPROVED", "the bill has every approval it needs", "55000")}
  end if;
  for v_level in
    select (p.value ->> 'level')::integer as level, (p.value ->> 'approverId')::uuid as approver
    from jsonb_array_elements(v_state -> 'pending') p
    order by 1
  loop
    if (v_actor is null and v_done = 0) or v_level.approver = v_actor then
      insert into ${approvals} (${ap("tenant")}, ${ap("invoice")}, ${ap("level")}, ${ap("approver")}, ${ap("comment")})
      values (v_row.${i("tenant")}, v_row.${i("id")}, v_level.level, v_level.approver, nullif(trim(approve_purchase_invoice.comment), ''));
      v_done := v_done + 1;
      v_last := v_level.level;
    end if;
  end loop;
  if v_done = 0 then
    ${fail("INVOICE_APPROVER_FORBIDDEN", "the caller is not the approver of a pending level", "42501")}
  end if;
  v_state := ${fn("invoice_approval_state")}(v_row.${i("id")});
  ${h.record("invoice.approved", "v_row", ", 'level', v_last, 'approvalStatus', v_state ->> 'status'", true)}
  return ${h.row("v_row")} || jsonb_build_object('approval', v_state);
end;
$$;
${userGrant(`${fn("approve_purchase_invoice")}(uuid, text)`)}
`;
}

/** The contract of the approval functions. */
export function approvalContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  if (!hasApproval(ctx)) {
    return [];
  }

  return [
    {
      name: "set_invoice_approval_levels",
      args: ["{id}", "jsonb", "uuid"],
      returns: "jsonb",
    },
    { name: "list_invoice_approval_levels", args: ["{id}"], returns: "jsonb" },
    {
      name: "purchase_invoice_approval_status",
      args: ["uuid"],
      returns: "jsonb",
    },
    {
      name: "approve_purchase_invoice",
      args: ["uuid", "text"],
      returns: "jsonb",
    },
    { name: "invoice_approval_state", args: ["uuid"], returns: "jsonb" },
  ];
}
