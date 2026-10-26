import type { EnrichmentEvents } from "../../blocks/enrichment/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  fail,
  lockTable,
  pageSize,
  schemaPreamble,
  SERVICE_CALLER,
  serviceGrant,
  userGrant,
} from "../shared.ts";
import { moduleOperations } from "./permissions-model.ts";

const EVENTS: BlockSqlEvents<EnrichmentEvents> = {
  "party.enriched": {
    subject: "enrichments",
    payload: [
      "organizationId",
      "subjectType",
      "subjectId",
      "provider",
      "status",
      "filled",
    ],
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    enrichment: { table: "enrichments", singular: "enrichment", primary: true },
  },
  events: EVENTS,
  tables: {
    enrichments: {
      name: "enrichments",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        company: "company_id",
        person: "person_id",
        provider: "provider",
        status: "status",
        data: "data",
        filled: "filled",
        fetchedAt: "fetched_at",
        requestedBy: "requested_by",
      },
      optional: ["requestedBy"],
      typed: ["status"],
    },
  },
};

const DOMAIN = String.raw`^[a-z0-9.-]+\.[a-z]{2,}$`;

interface EnrichmentNames {
  readonly fn: (name: string) => string;
  readonly t: (table: string) => string;
  readonly e: (column: string) => string;
  readonly co: (column: string) => string;
  readonly pe: (column: string) => string;
  readonly li: (column: string) => string;
  readonly companies: string;
  readonly people: string;
  readonly links: string;
  /** The subject type names of a company and a person, after renames. */
  readonly company: string;
  readonly person: string;
  readonly read: string;
  readonly run: string;
}

function names(ctx: BlockSqlContext): EnrichmentNames {
  const keys = moduleOperations("enrichment");
  const parties = ctx.of("contacts");

  return {
    fn: (name) => ctx.fn(name),
    t: (table) => ctx.table(table),
    e: (column) => ctx.col("enrichments", column),
    co: (column) => parties.col("companies", column),
    pe: (column) => parties.col("people", column),
    li: (column) => parties.col("links", column),
    companies: parties.table("companies"),
    people: parties.table("people"),
    links: parties.table("links"),
    company: sqlString(parties.naming.rename("company")),
    person: sqlString(parties.naming.rename("person")),
    read: ctx.permission("read", keys.read),
    run: ctx.permission("run", keys.run),
  };
}

function tables(ctx: BlockSqlContext, n: EnrichmentNames): string {
  const { t, e, co, pe } = n;
  const policy = `${ctx.tableName("enrichments").name}_read`;
  const by = ctx.has("enrichments", "requestedBy");
  const name = ctx.tableName("enrichments").name;

  // The app's table lacks the module's named unique constraints, so the
  // upserts there target these indexes by their columns.
  const keys = ctx.owns("enrichments")
    ? ""
    : (["company", "person"] as const)
        .map(
          (column) =>
            `create unique index if not exists ${sqlIdent(`bsb_${name}_${column}_provider_key`)} on ${t("enrichments")} (${e(column)}, ${e("provider")});\n`,
        )
        .join("");

  return `create table if not exists ${t("enrichments")} (
  ${e("id")} uuid primary key default gen_random_uuid(),
  ${e("tenant")} ${ctx.idType} not null,
  ${e("company")} uuid references ${n.companies} (${co("id")}) on delete cascade,
  ${e("person")} uuid references ${n.people} (${pe("id")}) on delete cascade,
  ${e("provider")} text not null check (${e("provider")} ~ '^[a-z][a-z0-9_-]{0,62}$'),
  ${e("status")} text not null check (${e("status")} in ('matched', 'not_found')),
  ${e("data")} jsonb not null default '{}'::jsonb check (jsonb_typeof(${e("data")}) = 'object'),
  ${e("filled")} text[] not null default '{}',
  ${e("fetchedAt")} timestamptz not null default now(),${by ? `\n  ${e("requestedBy")} uuid references auth.users (id) on delete set null,` : ""}
  check (num_nonnulls(${e("company")}, ${e("person")}) = 1),
  constraint ${ctx.naming.rename("enrichments_company_provider_key")} unique (${e("company")}, ${e("provider")}),
  constraint ${ctx.naming.rename("enrichments_person_provider_key")} unique (${e("person")}, ${e("provider")})
);
create index if not exists ${ctx.naming.rename("enrichments_tenant_idx")} on ${t("enrichments")} (${e("tenant")}, ${e("fetchedAt")});
${by ? `create index if not exists ${ctx.naming.rename("enrichments_requested_by_idx")} on ${t("enrichments")} (${e("requestedBy")}) where ${e("requestedBy")} is not null;\n` : ""}${keys}${lockTable(t("enrichments"), { read: true })}
${renderPolicy(makePolicy({ table: t("enrichments"), name: policy, command: "select", roles: ["authenticated"], using: ctx.scope.check(e("tenant"), n.read) }), { drop: true, target: t("enrichments") })}
`;
}

/** What a provider looks up for a company row `c`. */
function companyTarget(n: EnrichmentNames, row: string): string {
  const { co } = n;

  return `jsonb_build_object('kind', 'company', 'organizationId', ${row}.${co("tenant")}, 'subjectType', ${n.company}, 'subjectId', ${row}.${co("id")}, 'name', ${row}.${co("name")}, 'domain', ${row}.${co("domain")}, 'website', ${row}.${co("website")})`;
}

/** What a provider looks up for a person row, with their company's domain. */
function personTarget(n: EnrichmentNames, row: string): string {
  const { pe, co, li } = n;

  return `jsonb_build_object('kind', 'person', 'organizationId', ${row}.${pe("tenant")}, 'subjectType', ${n.person}, 'subjectId', ${row}.${pe("id")}, 'name', ${row}.${pe("name")}, 'email', ${row}.${pe("email")}, 'phone', ${row}.${pe("phone")}, 'title', ${row}.${pe("title")}, 'companyDomain', (
    select c.${co("domain")} from ${n.links} l
    join ${n.companies} c on c.${co("id")} = l.${li("company")}
    where l.${li("person")} = ${row}.${pe("id")} and c.${co("archivedAt")} is null
    order by l.${li("isPrimary")} desc, l.${li("createdAt")}
    limit 1))`;
}

function functions(ctx: BlockSqlContext, n: EnrichmentNames): string {
  const { fn, t, e, co, pe } = n;
  const by = ctx.has("enrichments", "requestedBy");

  const json = (row: string): string =>
    `jsonb_build_object('id', ${row}.${e("id")}, 'organizationId', ${row}.${e("tenant")}, 'subjectType', case when ${row}.${e("company")} is not null then ${n.company} else ${n.person} end, 'subjectId', coalesce(${row}.${e("company")}, ${row}.${e("person")}), 'provider', ${row}.${e("provider")}, 'status', ${row}.${e("status")}, 'data', ${row}.${e("data")}, 'filled', to_jsonb(${row}.${e("filled")}), 'fetchedAt', ${row}.${e("fetchedAt")}, 'requestedBy', ${by ? `${row}.${e("requestedBy")}` : "null"})`;

  const unknown = fail(
    "ENRICHMENT_SUBJECT_UNKNOWN",
    "subject_type must be the company or the person type",
    "22023",
  );

  const notFound = fail(
    "ENRICHMENT_NOT_FOUND",
    "No company or person you can enrich has this id",
    "P0002",
  );

  const upsert = (
    column: "company" | "person",
  ): string => `insert into ${t("enrichments")} (${e("tenant")}, ${e(column)}, ${e("provider")}, ${e("status")}, ${e("data")}, ${e("filled")}${by ? `, ${e("requestedBy")}` : ""})
    values (v_tenant, record_enrichment.subject_id, record_enrichment.provider, ${ctx.cast("enrichments", "status", "v_status")}, v_data, v_filled${by ? ", auth.uid()" : ""})
    on conflict ${ctx.owns("enrichments") ? `on constraint ${ctx.naming.rename(`enrichments_${column}_provider_key`)}` : `(${e(column)}, ${e("provider")})`} do update set
      ${e("status")} = excluded.${e("status")},
      ${e("data")} = excluded.${e("data")},
      ${e("filled")} = excluded.${e("filled")},
      ${e("fetchedAt")} = now()${by ? `,\n      ${e("requestedBy")} = excluded.${e("requestedBy")}` : ""}
    returning * into v_row;`;

  const due = (
    kind: "company" | "person",
  ): string => `select ${kind === "company" ? companyTarget(n, "x") : personTarget(n, "x")} as target, y.${e("fetchedAt")} as fetched_at, x.${kind === "company" ? co("id") : pe("id")} as id
    from ${kind === "company" ? n.companies : n.people} x
    left join ${t("enrichments")} y on y.${e(kind)} = x.${kind === "company" ? co("id") : pe("id")} and y.${e("provider")} = enrichment_due.provider
    where x.${kind === "company" ? co("archivedAt") : pe("archivedAt")} is null
      and (enrichment_due.subject_type is null or enrichment_due.subject_type = ${kind === "company" ? n.company : n.person})
      and ${kind === "company" ? `(x.${co("domain")} is not null or x.${co("website")} is not null)` : `x.${pe("email")} is not null`}
      and (y.${e("fetchedAt")} is null or y.${e("fetchedAt")} < now() - coalesce(enrichment_due.stale_after, interval '30 days'))`;

  return `
-- What a provider looks up for one company or person: its name and the
-- domain, website or email it can be matched by. Needs enrichment.run.
create or replace function ${fn("enrichment_target")}(subject_type text, subject_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_target jsonb;
begin
  if enrichment_target.subject_type = ${n.company} then
    select ${companyTarget(n, "c")} into v_target from ${n.companies} c
    where c.${co("id")} = enrichment_target.subject_id and c.${co("archivedAt")} is null;
  elsif enrichment_target.subject_type = ${n.person} then
    select ${personTarget(n, "p")} into v_target from ${n.people} p
    where p.${pe("id")} = enrichment_target.subject_id and p.${pe("archivedAt")} is null;
  else
    ${unknown}
  end if;
  if v_target is null or not (${SERVICE_CALLER} or ${ctx.scope.can(`(v_target ->> 'organizationId')::${ctx.idType}`, n.run)}) then
    ${notFound}
  end if;
  return v_target;
end;
$$;
${userGrant(`${fn("enrichment_target")}(text, uuid)`)}

-- Stores what a provider returned for a company or person. result is
-- { status: 'matched' | 'not_found', data }. With fill, a match fills the
-- record's empty columns: a company's domain and website, a person's phone
-- and title. A domain another active company holds is left out. Returns the
-- stored result.
create or replace function ${fn("record_enrichment")}(subject_type text, subject_id uuid, provider text, result jsonb, fill boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$${ctx.owns("enrichments") ? "" : "\n#variable_conflict use_column"}
declare
  v_tenant ${ctx.idType};
  v_company ${n.companies};
  v_person ${n.people};
  v_row ${t("enrichments")};
  v_status text;
  v_data jsonb;
  v_filled text[] := '{}';
  v_domain text;
  v_website text;
  v_phone text;
  v_title text;
begin
  if jsonb_typeof(result) is distinct from 'object' then
    ${fail("ENRICHMENT_INVALID", "result must be an object", "22023")}
  end if;
  v_status := result ->> 'status';
  if v_status is null or v_status not in ('matched', 'not_found') then
    ${fail("ENRICHMENT_INVALID", "result.status must be matched or not_found", "22023")}
  end if;
  v_data := case when v_status = 'matched' then coalesce(result -> 'data', '{}'::jsonb) else '{}'::jsonb end;
  if jsonb_typeof(v_data) is distinct from 'object' then
    ${fail("ENRICHMENT_INVALID", "result.data must be an object", "22023")}
  end if;
  if record_enrichment.provider is null or record_enrichment.provider !~ '^[a-z][a-z0-9_-]{0,62}$' then
    ${fail("ENRICHMENT_INVALID", "provider must be a lowercase name", "22023")}
  end if;
  if record_enrichment.subject_type = ${n.company} then
    select * into v_company from ${n.companies} c
    where c.${co("id")} = record_enrichment.subject_id and c.${co("archivedAt")} is null for update;
    v_tenant := v_company.${co("tenant")};
  elsif record_enrichment.subject_type = ${n.person} then
    select * into v_person from ${n.people} p
    where p.${pe("id")} = record_enrichment.subject_id and p.${pe("archivedAt")} is null for update;
    v_tenant := v_person.${pe("tenant")};
  else
    ${unknown}
  end if;
  if v_tenant is null or not (${SERVICE_CALLER} or ${ctx.scope.can("v_tenant", n.run)}) then
    ${notFound}
  end if;
  if v_status = 'matched' and coalesce(record_enrichment.fill, true) then
    if v_company.${co("id")} is not null then
      v_domain := lower(nullif(trim(v_data ->> 'domain'), ''));
      if v_company.${co("domain")} is null and v_domain ~ '${DOMAIN}'
        and not exists (
          select 1 from ${n.companies} c
          where c.${co("tenant")} = v_tenant and c.${co("domain")} = v_domain and c.${co("archivedAt")} is null
        ) then
        v_filled := v_filled || 'domain'::text;
      else
        v_domain := null;
      end if;
      v_website := nullif(trim(v_data ->> 'website'), '');
      if v_company.${co("website")} is null and length(v_website) <= 2048 then
        v_filled := v_filled || 'website'::text;
      else
        v_website := null;
      end if;
      if cardinality(v_filled) > 0 then
        update ${n.companies} c set
          ${co("domain")} = coalesce(c.${co("domain")}, v_domain),
          ${co("website")} = coalesce(c.${co("website")}, v_website),
          ${co("updatedAt")} = now()
        where c.${co("id")} = v_company.${co("id")};
      end if;
    else
      v_phone := nullif(trim(v_data ->> 'phone'), '');
      if v_person.${pe("phone")} is null and length(v_phone) <= 50 then
        v_filled := v_filled || 'phone'::text;
      else
        v_phone := null;
      end if;
      v_title := nullif(trim(v_data ->> 'title'), '');
      if v_person.${pe("title")} is null and length(v_title) <= 300 then
        v_filled := v_filled || 'title'::text;
      else
        v_title := null;
      end if;
      if cardinality(v_filled) > 0 then
        update ${n.people} p set
          ${pe("phone")} = coalesce(p.${pe("phone")}, v_phone),
          ${pe("title")} = coalesce(p.${pe("title")}, v_title),
          ${pe("updatedAt")} = now()
        where p.${pe("id")} = v_person.${pe("id")};
      end if;
    end if;
  end if;
  if v_company.${co("id")} is not null then
    ${upsert("company")}
  else
    ${upsert("person")}
  end if;
  ${ctx.record({
    type: "party.enriched",
    payload: `jsonb_build_object('organizationId', v_tenant, 'subjectType', record_enrichment.subject_type, 'subjectId', record_enrichment.subject_id, 'provider', record_enrichment.provider, 'status', v_status, 'filled', to_jsonb(v_filled))`,
    subject: `'enrichments/' || v_row.${e("id")}::text`,
    tenant: "v_tenant::text",
    audit: false,
  })}
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("record_enrichment")}(text, uuid, text, jsonb, boolean)`)}

-- A company's or person's stored results, one per provider, newest first.
create or replace function ${fn("enrichments_of")}(subject_type text, subject_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(${json("x")} order by x.${e("fetchedAt")} desc, x.${e("provider")}), '[]'::jsonb)
  from ${t("enrichments")} x
  where case
      when enrichments_of.subject_type = ${n.company} then x.${e("company")} = enrichments_of.subject_id
      when enrichments_of.subject_type = ${n.person} then x.${e("person")} = enrichments_of.subject_id
      else false
    end
    and ${ctx.scope.can(`x.${e("tenant")}`, n.read)}
$$;
${userGrant(`${fn("enrichments_of")}(text, uuid)`)}

-- The companies and people a provider has no result for, or one older than
-- stale_after, never enriched first, for a cron. A company needs a domain or
-- a website and a person an email to be looked up.
create or replace function ${fn("enrichment_due")}(provider text, max_count integer default null, stale_after interval default null, subject_type text default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(z.target order by z.fetched_at nulls first, z.id), '[]'::jsonb)
  from (
    select * from (
      ${due("company")}
      union all
      ${due("person")}
    ) w
    order by w.fetched_at nulls first, w.id
    limit ${pageSize("enrichment_due.max_count", 25, 500)}
  ) z
$$;
${serviceGrant(`${fn("enrichment_due")}(text, integer, interval, text)`)}
`;
}

function build(ctx: BlockSqlContext): string {
  const n = names(ctx);

  return `${schemaPreamble(ctx)}
-- Enrichment: what a provider returned for a company or a person, one result
-- per provider, and the empty columns a match filled.
${tables(ctx, n)}${functions(ctx, n)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    { name: "enrichment_target", args: ["text", "uuid"], returns: "jsonb" },
    {
      name: "record_enrichment",
      args: ["text", "uuid", "text", "jsonb", "boolean"],
      returns: "jsonb",
    },
    { name: "enrichments_of", args: ["text", "uuid"], returns: "jsonb" },
    {
      name: "enrichment_due",
      args: ["text", "integer", "interval", "text"],
      returns: "jsonb",
    },
  ];
}

export const ENRICHMENT: BlockSqlDefinition = {
  name: "enrichment",
  scopes: ["tenant"],
  title: "Enrichment",
  description:
    "Company and person data from an enrichment provider, such as a company's industry and size or a person's title: one result per provider, the empty columns a match fills, and a list of the records due for a cron.",
  requires: ["memberships", "permissions", "contacts"],
  integrates: ["outbox", "data-lifecycle"],
  target: "schema",
  modes: ["managed"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
