import type { BlockSqlContext } from "../context.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { SERVICE_CALLER, pageSize, userGrant, raise } from "../shared.ts";
import { hasColumn, impersonators } from "./audit-columns.ts";
import { auditRead, isAuditValueColumn } from "./audit-values.ts";
import { OPERATIONS, modulePermission } from "./permissions-model.ts";

/** Logical log column to the key `list_audit_events` returns it under. */
const ENTRY_KEYS: readonly (readonly [string, string])[] = [
  ["id", "id"],
  ["table", "table"],
  ["record", "record"],
  ["op", "op"],
  ["old", "old"],
  ["new", "new"],
  ["changed", "changed"],
  ["actor", "actorId"],
  ["actorRole", "actorRole"],
  ["actorKind", "actorKind"],
  ["actorLabel", "actorLabel"],
  ["tenant", "tenant"],
  ["tenantLabel", "tenantLabel"],
  ["occurredAt", "occurredAt"],
  ["impersonatedBy", "impersonatedBy"],
  ["impersonationReason", "impersonationReason"],
  ["supportSession", "supportSession"],
  ["eventType", "eventType"],
  ["category", "category"],
  ["outcome", "outcome"],
  ["source", "source"],
  ["targetType", "targetType"],
  ["targetLabel", "targetLabel"],
  ["summary", "summary"],
  ["requestId", "requestId"],
  ["correlationId", "correlationId"],
  ["scope", "scope"],
  ["metadata", "metadata"],
];

/**
 * `list_audit_events` for the TypeScript side: a page of entries the caller can
 * read (security invoker, so the read policy decides), newest first.
 */
export function listEntries(
  ctx: BlockSqlContext,
  restricted: boolean,
  extra: readonly (readonly [column: string, key: string])[] = [],
): string {
  const id = ctx.idType;
  const log = ctx.table("log");
  const c = (logical: string) => ctx.col("log", logical);

  const hidden = new Set(
    impersonators(ctx) === "hide"
      ? ["impersonatedBy", "impersonationReason", "supportSession"]
      : [],
  );

  const entryOf = (omit: ReadonlySet<string>): string => {
    const pairs = ENTRY_KEYS.filter(
      ([logical]) =>
        hasColumn(ctx, "log", logical) &&
        !hidden.has(logical) &&
        !omit.has(logical) &&
        !(restricted && (logical === "old" || logical === "new")),
    ).map(([logical, key]) => {
      const value = `l.${c(logical)}`;

      return `'${key}', ${isAuditValueColumn(logical) ? auditRead(ctx, logical, value) : value}`;
    });

    if (extra.length > 0 && !omit.has("columns")) {
      pairs.push(
        `'columns', jsonb_build_object(${extra.map(([column]) => `${sqlString(column)}, l.${sqlIdent(column)}`).join(", ")})`,
      );
    }

    // jsonb_build_object takes at most 100 arguments; split in chunks of 20 keys.
    const chunks: string[] = [];

    for (let index = 0; index < pairs.length; index += 20) {
      chunks.push(
        `jsonb_build_object(${pairs.slice(index, index + 20).join(", ")})`,
      );
    }

    return chunks.join(" || ");
  };

  const fullEntry = entryOf(new Set());
  // The summary form leaves out what makes a row large: the old and new record, the changed columns and the metadata.
  const summaryEntry = entryOf(new Set(["old", "new", "changed", "metadata"]));

  // The filters and their positions in the dynamic query's `using` list.
  const conditions: string[] = [];

  const filter = (logical: string, param: string, position: number) => {
    if (!hasColumn(ctx, "log", logical)) {
      return;
    }

    const value = `l.${c(logical)}`;

    const read = isAuditValueColumn(logical)
      ? auditRead(ctx, logical, value)
      : value;

    conditions.push(`  if cardinality(${param}) > 0 then
    v_where := v_where || $q$ and ${read} = any ($${position})$q$;
  end if;`);
  };

  filter("tenant", "for_tenants", 1);
  filter("eventType", "for_event_types", 2);
  filter("actor", "for_actors", 3);
  filter("targetType", "for_target_types", 4);
  filter("record", "for_records", 5);
  filter("category", "for_categories", 6);
  filter("outcome", "for_outcomes", 7);
  filter("source", "for_sources", 9);
  filter("actorKind", "for_actor_kinds", 10);
  filter("correlationId", "for_correlation_ids", 11);

  const searchable = (
    [
      "eventType",
      "summary",
      "targetLabel",
      "actorLabel",
      "tenantLabel",
      "record",
      "table",
    ] as const
  )
    .filter((logical) => hasColumn(ctx, "log", logical))
    .map((logical) => `l.${c(logical)}`);

  if (searchable.length > 0) {
    conditions.push(`  if search <> '' then
    v_where := v_where || $q$ and concat_ws(' ', ${searchable.join(", ")}) ilike '%' || replace(replace(replace($8, '\\', '\\\\'), '%', '\\%'), '_', '\\_') || '%'$q$;
  end if;`);
  }

  conditions.push(`  if since is not null then
    v_where := v_where || $q$ and l.${c("occurredAt")} >= $12$q$;
  end if;
  if until is not null then
    v_where := v_where || $q$ and l.${c("occurredAt")} < $13$q$;
  end if;`);
  const where = conditions.join("\n");

  const using =
    "for_tenants, for_event_types, for_actors, for_target_types, for_records, for_categories, for_outcomes, search, for_sources, for_actor_kinds, for_correlation_ids, since, until";

  // A managed log's id is a bigint, so "10" pages after "9"; an adopted
  // log's id compares as text.
  const idKey = ctx.owns("log") ? `l.${c("id")}` : `l.${c("id")}::text`;
  const cursorKey = ctx.owns("log") ? "$15::bigint" : "$15";

  const filters = `for_tenants ${id}[] default null,
  for_event_types text[] default null,
  for_actors uuid[] default null,
  for_target_types text[] default null,
  for_records text[] default null,
  for_categories text[] default null,
  for_outcomes text[] default null,
  search text default null,
  for_sources text[] default null,
  for_actor_kinds text[] default null,
  for_correlation_ids text[] default null,
  since timestamptz default null,
  until timestamptz default null`;

  const filterTypes = `${id}[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamptz, timestamptz`;
  const previousListTypes = `${filterTypes}, timestamptz, text, integer, boolean, integer`;
  const listTypes = `${previousListTypes}, text`;
  const countTypes = `${filterTypes}, integer`;

  // A managed log without options.readPolicy grants users no select, so the
  // invoker functions would only raise 42501 for them.
  const callers =
    !ctx.owns("log") || ctx.flag("readPolicy", false)
      ? "authenticated, service_role"
      : "service_role";

  const revokeUsers = (fn: string, types: string): string =>
    callers === "service_role"
      ? `revoke execute on function ${fn}(${types}) from authenticated;\n`
      : "";

  const eventTypes = hasColumn(ctx, "log", "eventType")
    ? `

-- The distinct event types the caller can read, found by skipping through the
-- event type index (a recursive loose scan) instead of reading every row.
create or replace function ${ctx.fn("audit_event_types")}(for_tenants ${id}[] default null)
returns text[]
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_types text[] := '{}';
  v_next text;
begin
  -- One loose index scan per tenant: min() over the (tenant, event type) index
  -- reads one entry, where "tenant = any(...)" would read every row. Without
  -- for_tenants the scan has no tenant to lead with, so pass the tenants.
  loop
    if cardinality(for_tenants) > 0 then
      execute $q$select min(x.m) from unnest($1) t(scope_id)
        cross join lateral (select min(l.${c("eventType")}) as m from ${log} l
          where l.${c("tenant")} = t.scope_id and l.${c("eventType")} > $2) x$q$
      into v_next
      using for_tenants, coalesce(v_types[cardinality(v_types)], '');
    else
      execute $q$select min(l.${c("eventType")}) from ${log} l where l.${c("eventType")} > $1$q$
      into v_next
      using coalesce(v_types[cardinality(v_types)], '');
    end if;
    exit when v_next is null;
    v_types := v_types || v_next;
    exit when cardinality(v_types) >= 500;
  end loop;
  return v_types;
end;
$$;
revoke execute on function ${ctx.fn("audit_event_types")}(${id}[]) from public, anon;
${revokeUsers(ctx.fn("audit_event_types"), `${id}[]`)}grant execute on function ${ctx.fn("audit_event_types")}(${id}[]) to ${callers};`
    : "";

  return `-- A page of the entries the caller can read, newest first unless ascending:
-- the read policy decides (security invoker). Each filter takes several
-- values; search matches the event type, summary, labels, record and table.
-- Page with the last entry's occurred_at and id as cursor_at and cursor_id,
-- or open page N with skip (an offset) and count_audit_events for the total.
-- skip is ignored with a cursor, so keyset pages never scan skipped rows.
drop function if exists ${ctx.fn("list_audit_events")}(${id}, text, uuid, text, text, timestamptz, timestamptz, timestamptz, text, integer);
drop function if exists ${ctx.fn("list_audit_events")}(${filterTypes}, timestamptz, text, integer, boolean);
drop function if exists ${ctx.fn("list_audit_events")}(${previousListTypes});
create or replace function ${ctx.fn("list_audit_events")}(
  ${filters},
  cursor_at timestamptz default null,
  cursor_id text default null,
  max_items integer default 50,
  ascending boolean default false,
  skip integer default 0,
  entry_fields text default 'full'
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_where text := 'true';
  v_order text := case when ascending then 'asc' else 'desc' end;
  v_skip text := '';
  v_entry text;
  result jsonb;
begin
  -- 'summary' leaves out the old and new record, the changed columns and the
  -- metadata, so a page of a busy log stays small. get_audit_event returns the
  -- full entry.
  v_entry := case when entry_fields = 'summary'
    then $e$${summaryEntry}$e$
    else $e$${fullEntry}$e$
  end;
${where}
  if cursor_at is not null then
    v_where := v_where || case when ascending
      then $q$ and (l.${c("occurredAt")}, ${idKey}) > ($14, ${cursorKey})$q$
      else $q$ and (l.${c("occurredAt")}, ${idKey}) < ($14, ${cursorKey})$q$
    end;
  elsif coalesce(skip, 0) > 0 then
    v_skip := ' offset $17';
  end if;
  -- Only the filters passed reach the query, so the planner sees no
  -- "is null or" branches and can use the (tenant, occurred_at) index.
  execute $q$select coalesce(jsonb_agg(x.entry order by x.occurred_at $q$ || v_order || $q$, x.id $q$ || v_order || $q$), '[]')
  from (
    select $q$ || v_entry || $q$ as entry, l.${c("occurredAt")} as occurred_at, ${idKey} as id
    from ${log} l
    where $q$ || v_where || $q$
    order by l.${c("occurredAt")} $q$ || v_order || $q$, ${idKey} $q$ || v_order || $q$
    limit $16$q$ || v_skip || $q$
  ) x$q$
  into result
  using ${using}, cursor_at, cursor_id, ${pageSize("max_items", 50, 1000)}, greatest(coalesce(skip, 0), 0);
  return result;
end;
$$;
revoke execute on function ${ctx.fn("list_audit_events")}(${listTypes}) from public, anon;
${revokeUsers(ctx.fn("list_audit_events"), listTypes)}grant execute on function ${ctx.fn("list_audit_events")}(${listTypes}) to ${callers};

drop function if exists ${ctx.fn("count_audit_events")}(${filterTypes});
create or replace function ${ctx.fn("count_audit_events")}(
  ${filters},
  cap integer default null
)
returns bigint
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_where text := 'true';
  result bigint;
begin
${where}
  -- With cap the count stops there: a result equal to cap means "cap or more",
  -- and a filtered view over a large log never counts every match (ADR 0425).
  execute $q$select count(*) from (select 1 from ${log} l where $q$ || v_where
    || case when cap is null then '' else format(' limit %s', greatest(cap, 1)) end || $q$) x$q$
  into result
  using ${using};
  return result;
end;
$$;
revoke execute on function ${ctx.fn("count_audit_events")}(${countTypes}) from public, anon;
${revokeUsers(ctx.fn("count_audit_events"), countTypes)}grant execute on function ${ctx.fn("count_audit_events")}(${countTypes}) to ${callers};

-- One full entry by id, as list_audit_events returns it with entry_fields
-- 'full'. The read policy decides, so an entry the caller can't read is null.
create or replace function ${ctx.fn("get_audit_event")}(entry_id text)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  result jsonb;
begin
  execute $q$select $q$ || $e$${fullEntry}$e$ || $q$ from ${log} l where ${idKey} = $1$q$
  into result
  using ${ctx.owns("log") ? "entry_id::bigint" : "entry_id"};
  return result;
end;
$$;
revoke execute on function ${ctx.fn("get_audit_event")}(text) from public, anon;
${revokeUsers(ctx.fn("get_audit_event"), "text")}grant execute on function ${ctx.fn("get_audit_event")}(text) to ${callers};${eventTypes}`;
}

/**
 * `reveal_audit_entry(entry)`: the restricted details of one entry, for a
 * member who may reveal them in its tenant (or platform staff), and an
 * `audit.revealed` entry that records who looked.
 */
export function reveal(ctx: BlockSqlContext, restricted: boolean): string {
  if (!restricted || !ctx.installed("permissions")) {
    return "";
  }

  const log = ctx.table("log");
  const c = (logical: string) => ctx.col("log", logical);
  const r = (logical: string) => ctx.col("restricted", logical);

  const key = ctx.permission(
    "reveal",
    ctx.permissionKey("read", OPERATIONS["audit.read"]),
  );

  const viewAll = modulePermission(ctx, "readAll", OPERATIONS["audit.readAll"]);

  const fields = (
    [
      ["old", "old"],
      ["new", "new"],
      ["ip", "ip"],
      ["userAgent", "userAgent"],
      ["metadata", "metadata"],
      ["sessionId", "sessionId"],
      ["changedValues", "changes"],
    ] as const
  )
    .filter(([logical]) => hasColumn(ctx, "restricted", logical))
    .map(([logical, out]) => `, '${out}', d.${r(logical)}`)
    .join("");

  const allowed = (tenant: string) => `(${SERVICE_CALLER})
    or ${ctx.scope.platform(viewAll)}
    or (${tenant} is not null and coalesce(better_supabase.member_can(auth.uid(), ${tenant}, ${key}), false))`;

  return `-- The restricted details of one entry for a member with the reveal
-- permission in its tenant, or platform staff, recorded as audit.revealed.
create or replace function ${ctx.fn("reveal_audit_entry")}(entry text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner ${ctx.idType};
  found_entry boolean;
  details jsonb;
begin
  select true, l.${c("tenant")} into found_entry, owner from ${log} l where l.${c("id")}::text = entry;
  if found_entry is null or not (
    ${allowed("owner")}
  ) then
    ${raise("No audit entry %", "P0002", "AUDIT_ENTRY_NOT_FOUND", "entry")}
  end if;
  select jsonb_build_object('entry', entry${fields}) into details
  from ${ctx.table("restricted")} d where d.${r("entry")}::text = entry;
  ${ctx.record({
    type: "audit.revealed",
    payload:
      "jsonb_build_object('organizationId', owner::text, 'entries', jsonb_build_array(entry))",
    subject: "'audit-entries/' || entry",
    tenant: "owner",
    audit: {
      category: "security",
      targetType: "audit_entry",
      recordId: "entry",
      metadata: "'{}'::jsonb",
      actor: "auth.uid()",
    },
  })}
  return coalesce(details, jsonb_build_object('entry', entry));
end;
$$;
${userGrant(`${ctx.fn("reveal_audit_entry")}(text)`)}

-- The restricted details of the entries the caller may reveal, for an
-- export; entries it may not reveal are left out. One audit.revealed entry
-- per tenant lists the revealed entry ids.
create or replace function ${ctx.fn("reveal_audit_entries")}(entries text[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  visible jsonb;
  details jsonb;
  revealed record;
begin
  select coalesce(jsonb_agg(jsonb_build_object('entry', l.${c("id")}::text, 'owner', l.${c("tenant")}) order by l.${c("occurredAt")}, l.${c("id")}), '[]') into visible
  from ${log} l
  where l.${c("id")}::text = any (entries)
    and (
    ${allowed(`l.${c("tenant")}`)}
    );
  select coalesce(jsonb_agg(jsonb_build_object('entry', v ->> 'entry'${fields})), '[]') into details
  from jsonb_array_elements(visible) v
  left join ${ctx.table("restricted")} d on d.${r("entry")}::text = v ->> 'entry';
  for revealed in
    select v ->> 'owner' as owner, jsonb_agg(v -> 'entry' order by n) as ids
    from jsonb_array_elements(visible) with ordinality as e(v, n)
    group by v ->> 'owner'
  loop
    ${ctx.record({
      type: "audit.revealed",
      payload:
        "jsonb_build_object('organizationId', revealed.owner, 'entries', revealed.ids)",
      subject: "'audit-entries/' || coalesce(revealed.owner, 'platform')",
      tenant: `(revealed.owner)::${ctx.idType}`,
      audit: {
        category: "security",
        targetType: "audit_entry",
        metadata: "jsonb_build_object('entries', revealed.ids)",
        actor: "auth.uid()",
      },
    })}
  end loop;
  return details;
end;
$$;
${userGrant(`${ctx.fn("reveal_audit_entries")}(text[])`)}`;
}
