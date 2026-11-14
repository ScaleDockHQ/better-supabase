import type { WarrantyEvents } from "../../blocks/warranty/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockContributes } from "../contributions.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { filterAny, listBody, listDeclare } from "../list-template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  fail,
  lockTable,
  schemaPreamble,
  SERVICE_CALLER,
  userGrant,
} from "../shared.ts";
import { OPERATIONS } from "./permissions-model.ts";
import { transitionTrigger } from "./state-machine.ts";
import { WARRANTY_STATUSES } from "./warranty-values.ts";

const CLAIM = ["organizationId", "id", "title", "assetId", "status"] as const;

const EVENTS: BlockSqlEvents<WarrantyEvents> = {
  "warranty_claim.created": { subject: "warranty-claims", payload: CLAIM },
  "warranty_claim.submitted": { subject: "warranty-claims", payload: CLAIM },
  "warranty_claim.decided": {
    subject: "warranty-claims",
    payload: [...CLAIM, "decision"],
  },
  "warranty_claim.closed": { subject: "warranty-claims", payload: CLAIM },
};

const NAMES: BlockSqlNames = {
  entities: {
    warranty_claim: {
      table: "claims",
      singular: "warranty_claim",
      primary: true,
      subject: {
        title: "title",
        permissions: { read: "read", write: "write", upload: "write" },
        search: { title: "title", body: ["manufacturer", "decision"] },
      },
    },
  },
  events: EVENTS,
  options: [],
  tables: {
    claims: {
      name: "warranty_claims",
      app: {},
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        title: "title",
        supplier: "supplier_id",
        manufacturer: "manufacturer",
        asset: "asset_id",
        amount: "amount",
        currency: "currency",
        status: "status",
        decision: "decision",
        decidedAt: "decided_at",
        decidedBy: "decided_by",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
  },
};

const quoted = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

const UUID =
  "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$";

const STATUSES = quoted(WARRANTY_STATUSES);

interface WarrantySql {
  readonly claims: string;
  readonly c: (column: string) => string;
  readonly read: string;
  readonly write: string;
  readonly decide: string;
  readonly allowed: (tenant: string, permission: string) => string;
  readonly invalid: (message: string) => string;
  readonly forbidden: (message: string) => string;
  readonly missing: string;
  readonly transition: string;
  readonly claim: (row: string) => string;
}

function warrantySql(ctx: BlockSqlContext): WarrantySql {
  const c = (column: string): string => ctx.col("claims", column);
  const read = ctx.permission("read", OPERATIONS["warranty.read"]);
  const write = ctx.permission("write", OPERATIONS["warranty.write"]);
  const decide = ctx.permission("decide", OPERATIONS["warranty.decide"]);

  return {
    claims: ctx.table("claims"),
    c,
    read,
    write,
    decide,
    allowed: (tenant, permission) =>
      `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.scope.can(tenant, permission)}))`,
    // The literal is the catalog entry. The argument is what the function raises.
    invalid: (message) =>
      fail(
        "WARRANTY_INVALID",
        "a warranty claim is invalid",
        "22023",
      ).replaceAll("a warranty claim is invalid", message),
    forbidden: (message) =>
      fail(
        "WARRANTY_FORBIDDEN",
        "not allowed to change a warranty claim",
      ).replaceAll("not allowed to change a warranty claim", message),
    missing: fail("WARRANTY_NOT_FOUND", "no such warranty claim", "P0002"),
    transition: fail(
      "WARRANTY_TRANSITION",
      "that status change is not allowed",
    ),
    claim: (row) => `jsonb_build_object(
    'id', ${row}.${c("id")},
    'organizationId', ${row}.${c("tenant")},
    'title', ${row}.${c("title")},
    'assetId', ${row}.${c("asset")},
    'supplierId', ${row}.${c("supplier")},
    'manufacturer', ${row}.${c("manufacturer")},
    'amount', ${row}.${c("amount")}::text,
    'currency', ${row}.${c("currency")},
    'status', ${row}.${c("status")},
    'decision', ${row}.${c("decision")},
    'decidedAt', ${row}.${c("decidedAt")},
    'decidedBy', ${row}.${c("decidedBy")})`,
  };
}

function tables(ctx: BlockSqlContext): string {
  const q = warrantySql(ctx);
  const { c, claims } = q;
  const physical = ctx.tableName("claims").name;

  const index = (suffix: string): string =>
    sqlIdent(`bsb_${physical}_${suffix}`);

  const readPolicy = renderPolicy(
    makePolicy({
      table: claims,
      name: index("read"),
      command: "select",
      roles: ["authenticated"],
      using: ctx.scope.check(c("tenant"), q.read),
    }),
    { target: claims },
  );

  return `
create table if not exists ${claims} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType} not null,
  ${c("title")} text not null check (char_length(${c("title")}) between 1 and 200),
  ${c("supplier")} uuid,
  ${c("manufacturer")} text,
  ${c("asset")} uuid not null,
  ${c("amount")} bigint not null check (${c("amount")} >= 0),
  ${c("currency")} text not null check (${c("currency")} ~ '^[A-Z]{3}$'),
  ${c("status")} text not null default 'draft' check (${c("status")} in (${STATUSES})),
  ${c("decision")} text,
  ${c("decidedAt")} timestamptz,
  ${c("decidedBy")} uuid,
  ${c("createdBy")} uuid,
  ${c("createdAt")} timestamptz not null default now(),
  ${c("updatedAt")} timestamptz not null default now(),
  -- A claim names the supplier, the manufacturer, or both.
  check (${c("supplier")} is not null or nullif(btrim(${c("manufacturer")}), '') is not null),
  unique (${c("tenant")}, ${c("id")})
);
create index if not exists ${index("asset_idx")} on ${claims} (${c("tenant")}, ${c("asset")});
create index if not exists ${index("status_idx")} on ${claims} (${c("tenant")}, ${c("status")});
${lockTable(claims, { read: true })}
${readPolicy}`;
}

function functions(ctx: BlockSqlContext): string {
  const q = warrantySql(ctx);
  const { c, claims } = q;
  const fn = (name: string): string => ctx.fn(name);

  const idType = ctx.idType;

  const list = {
    name: "list_warranty_claims",
    from: claims,
    alias: "x",
    where: [
      `x.${c("tenant")} = list_warranty_claims.tenant`,
      filterAny("status", `x.${c("status")}`),
      filterAny("assetId", `x.${c("asset")}`, "uuid"),
    ],
    keys: [
      { expr: `x.${c("createdAt")}`, dir: "desc", type: "timestamptz" },
      { expr: `x.${c("id")}`, dir: "asc", type: "uuid" },
    ],
    sorts: {
      createdAt: [
        { expr: `x.${c("createdAt")}`, dir: "desc", type: "timestamptz" },
        { expr: `x.${c("id")}`, dir: "asc", type: "uuid" },
      ],
      amount: [
        { expr: `x.${c("amount")}`, dir: "desc", type: "bigint" },
        { expr: `x.${c("id")}`, dir: "asc", type: "uuid" },
      ],
    },
    facets: { status: `x.${c("status")}` },
    rowJson: q.claim("x"),
    invalid: q.invalid,
  } as const;

  return `
-- A draft claim for an asset, covered for amount in currency's minor units.
-- supplierId or manufacturer is required. Needs warranty.write.
create or replace function ${fn("create_warranty_claim")}(tenant ${idType}, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${claims};
  v_title text;
  v_asset text;
  v_supplier text;
  v_manufacturer text;
  v_amount text;
  v_currency text;
begin
  if not ${q.allowed("create_warranty_claim.tenant", q.write)} then
    ${q.forbidden("not allowed to write warranty claims")}
  end if;
  if jsonb_typeof(create_warranty_claim.input) is distinct from 'object' then
    ${q.invalid("input must be an object")}
  end if;
  v_title := btrim(create_warranty_claim.input ->> 'title');
  v_asset := nullif(create_warranty_claim.input ->> 'assetId', '');
  v_supplier := nullif(create_warranty_claim.input ->> 'supplierId', '');
  v_manufacturer := nullif(btrim(create_warranty_claim.input ->> 'manufacturer'), '');
  v_amount := create_warranty_claim.input ->> 'amount';
  v_currency := upper(btrim(create_warranty_claim.input ->> 'currency'));
  if v_title is null or char_length(v_title) not between 1 and 200 then
    ${q.invalid("title must be 1 to 200 characters")}
  end if;
  if v_asset is null or v_asset !~ '${UUID}' then
    ${q.invalid("assetId must be a uuid")}
  end if;
  if v_supplier is not null and v_supplier !~ '${UUID}' then
    ${q.invalid("supplierId must be a uuid")}
  end if;
  if v_supplier is null and v_manufacturer is null then
    ${q.invalid("a claim names a supplier or a manufacturer")}
  end if;
  if v_amount is null or v_amount !~ '^[0-9]+$' then
    ${q.invalid("amount is minor units, as digits")}
  end if;
  if v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    ${q.invalid("currency is an ISO 4217 code")}
  end if;
  insert into ${claims} (
    ${c("tenant")}, ${c("title")}, ${c("supplier")}, ${c("manufacturer")}, ${c("asset")},
    ${c("amount")}, ${c("currency")}, ${c("createdBy")}
  ) values (
    create_warranty_claim.tenant, v_title, v_supplier::uuid, v_manufacturer, v_asset::uuid,
    v_amount::bigint, v_currency, auth.uid()
  ) returning * into v_row;
  ${ctx.record({
    type: "warranty_claim.created",
    payload: `jsonb_build_object('organizationId', v_row.${c("tenant")}, 'id', v_row.${c("id")}, 'title', v_row.${c("title")}, 'assetId', v_row.${c("asset")}, 'status', v_row.${c("status")})`,
    subject: `'warranty-claims/' || v_row.${c("id")}::text`,
    tenant: `v_row.${c("tenant")}`,
    audit: false,
  })}
  return ${q.claim("v_row")};
end;
$$;
${userGrant(`${fn("create_warranty_claim")}(${idType}, jsonb)`)}

-- draft -> submitted. Needs warranty.write.
create or replace function ${fn("submit_warranty_claim")}(claim_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${claims};
begin
  select * into v_row from ${claims} x where x.${c("id")} = submit_warranty_claim.claim_id for update;
  if not found or not ${q.allowed(`v_row.${c("tenant")}`, q.read)} then
    ${q.missing}
  end if;
  if not ${q.allowed(`v_row.${c("tenant")}`, q.write)} then
    ${q.forbidden("not allowed to write warranty claims")}
  end if;
  if v_row.${c("status")} is distinct from 'draft' then
    ${q.transition}
  end if;
  update ${claims} x set ${c("status")} = 'submitted', ${c("updatedAt")} = now()
  where x.${c("id")} = v_row.${c("id")}
  returning * into v_row;
  ${ctx.record({
    type: "warranty_claim.submitted",
    payload: `jsonb_build_object('organizationId', v_row.${c("tenant")}, 'id', v_row.${c("id")}, 'title', v_row.${c("title")}, 'assetId', v_row.${c("asset")}, 'status', v_row.${c("status")})`,
    subject: `'warranty-claims/' || v_row.${c("id")}::text`,
    tenant: `v_row.${c("tenant")}`,
    audit: false,
  })}
  return ${q.claim("v_row")};
end;
$$;
${userGrant(`${fn("submit_warranty_claim")}(uuid)`)}

-- submitted -> approved or denied, then either -> closed.
-- Approving or denying stores the decision. Needs warranty.decide.
-- The state machine allows the same edges when it is installed.
create or replace function ${fn("decide_warranty_claim")}(claim_id uuid, next_status text, decision text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${claims};
  v_decision text := nullif(btrim(decide_warranty_claim.decision), '');
begin
  select * into v_row from ${claims} x where x.${c("id")} = decide_warranty_claim.claim_id for update;
  if not found or not ${q.allowed(`v_row.${c("tenant")}`, q.read)} then
    ${q.missing}
  end if;
  if not ${q.allowed(`v_row.${c("tenant")}`, q.decide)} then
    ${q.forbidden("not allowed to decide warranty claims")}
  end if;
  if not (
    (v_row.${c("status")} = 'submitted' and decide_warranty_claim.next_status in ('approved', 'denied'))
    or (v_row.${c("status")} in ('approved', 'denied') and decide_warranty_claim.next_status = 'closed')
  ) then
    ${q.transition}
  end if;
  if decide_warranty_claim.next_status in ('approved', 'denied') and v_decision is null then
    ${q.invalid("a decision says why the claim was approved or denied")}
  end if;
  update ${claims} x set
    ${c("status")} = decide_warranty_claim.next_status,
    ${c("decision")} = case when decide_warranty_claim.next_status in ('approved', 'denied') then v_decision else x.${c("decision")} end,
    ${c("decidedAt")} = case when decide_warranty_claim.next_status in ('approved', 'denied') then now() else x.${c("decidedAt")} end,
    ${c("decidedBy")} = case when decide_warranty_claim.next_status in ('approved', 'denied') then auth.uid() else x.${c("decidedBy")} end,
    ${c("updatedAt")} = now()
  where x.${c("id")} = v_row.${c("id")}
  returning * into v_row;
  if v_row.${c("status")} = 'closed' then
    ${ctx.record({
      type: "warranty_claim.closed",
      payload: `jsonb_build_object('organizationId', v_row.${c("tenant")}, 'id', v_row.${c("id")}, 'title', v_row.${c("title")}, 'assetId', v_row.${c("asset")}, 'status', v_row.${c("status")})`,
      subject: `'warranty-claims/' || v_row.${c("id")}::text`,
      tenant: `v_row.${c("tenant")}`,
      audit: false,
    })}
  else
    ${ctx.record({
      type: "warranty_claim.decided",
      payload: `jsonb_build_object('organizationId', v_row.${c("tenant")}, 'id', v_row.${c("id")}, 'title', v_row.${c("title")}, 'assetId', v_row.${c("asset")}, 'status', v_row.${c("status")}, 'decision', v_row.${c("decision")})`,
      subject: `'warranty-claims/' || v_row.${c("id")}::text`,
      tenant: `v_row.${c("tenant")}`,
      audit: false,
    })}
  end if;
  return ${q.claim("v_row")};
end;
$$;
${userGrant(`${fn("decide_warranty_claim")}(uuid, text, text)`)}

-- A claim by id. Needs warranty.read.
create or replace function ${fn("get_warranty_claim")}(claim_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${claims};
begin
  select * into v_row from ${claims} x where x.${c("id")} = get_warranty_claim.claim_id;
  if not found or not ${q.allowed(`v_row.${c("tenant")}`, q.read)} then
    ${q.missing}
  end if;
  return ${q.claim("v_row")};
end;
$$;
${userGrant(`${fn("get_warranty_claim")}(uuid)`)}

-- Claims of an organization, newest first. filters is { status, assetId (each a
-- value or a list of them), sort, direction, facet, count, limit, after,
-- offset, paged, total, totalCap } (ADR 0749).
-- Needs warranty.read.
create or replace function ${fn("list_warranty_claims")}(tenant ${idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_warranty_claims.filters, '{}'::jsonb);
  ${listDeclare(list)}
begin
  if not ${q.allowed("list_warranty_claims.tenant", q.read)} then
    ${q.forbidden("not allowed to read warranty claims")}
  end if;
  if exists (
    select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'status') = 'array' then v_filters -> 'status' else jsonb_build_array(v_filters -> 'status') end) s
    where s not in (${STATUSES})
  ) then
    ${q.invalid("status is not a warranty status")}
  end if;
  if exists (
    select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'assetId') = 'array' then v_filters -> 'assetId' else jsonb_build_array(v_filters -> 'assetId') end) s
    where s !~ '${UUID}'
  ) then
    ${q.invalid("assetId must be a uuid")}
  end if;
  ${listBody(list)}
end;
$$;
${userGrant(`${fn("list_warranty_claims")}(${idType}, jsonb)`)}
`;
}

const CONTRIBUTES: BlockContributes = {
  approvals: (own) => [
    {
      subject: own.naming.rename("warranty_claim"),
      access: "declared",
      approve: ({ subjectId, comment }) =>
        `perform ${own.fn("decide_warranty_claim")}(${subjectId}::uuid, 'approved', ${comment});`,
      reject: ({ subjectId, comment }) =>
        `perform ${own.fn("decide_warranty_claim")}(${subjectId}::uuid, 'denied', ${comment});`,
    },
  ],
  "state-machine": (own) => {
    const { schema, name } = own.tableName("claims");

    return [
      {
        name: own.naming.rename("warranty_claim"),
        entry: {
          table: `${schema}.${name}`,
          column: own.colName("claims", "status"),
          id: own.colName("claims", "id"),
          idType: "uuid",
          tenant: own.colName("claims", "tenant"),
          initial: "draft",
          transitions: {
            draft: ["submitted"],
            submitted: ["approved", "denied"],
            approved: ["closed"],
            denied: ["closed"],
          },
        },
      },
    ];
  },
};

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "create_warranty_claim",
      args: ["{id}", "jsonb"],
      returns: "jsonb",
    },
    { name: "submit_warranty_claim", args: ["uuid"], returns: "jsonb" },
    { name: "get_warranty_claim", args: ["uuid"], returns: "jsonb" },
    {
      name: "decide_warranty_claim",
      args: ["uuid", "text", "text"],
      returns: "jsonb",
    },
    { name: "list_warranty_claims", args: ["{id}", "jsonb"], returns: "jsonb" },
  ];
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  return `${schemaPreamble(ctx)}
-- Warranty claims: a supplier or manufacturer, an asset, a covered amount and
-- a decision. Status moves draft, submitted, approved or denied, then closed.
${tables(ctx)}
${functions(ctx)}
${transitionTrigger({
  name: ctx.naming.rename("warranty_claim"),
  table: `${ctx.tableName("claims").schema}.${ctx.tableName("claims").name}`,
  column: ctx.colName("claims", "status"),
})}`;
}

export const WARRANTY: BlockSqlDefinition = {
  name: "warranty",
  scopes: ["tenant"],
  title: "Warranty",
  description:
    "Warranty claims for an asset: the supplier or manufacturer, the covered amount, a status, a decision and attachments on the claim.",
  requires: [
    "memberships",
    "permissions",
    "subjects",
    "state-machine",
    "approvals",
    "attachments",
  ],
  integrates: ["outbox", "audit"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contributes: CONTRIBUTES,
  contract,
  build,
};
