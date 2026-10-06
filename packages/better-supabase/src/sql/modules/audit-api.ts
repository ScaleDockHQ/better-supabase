import type { ModuleContext } from "../context.ts";

import { SERVICE_CALLER } from "../shared.ts";
import { MODULE_PERMISSIONS } from "./access-model.ts";
import { hasColumn, impersonators } from "./audit-columns.ts";
import { auditRead, isAuditValueColumn } from "./audit-values.ts";

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
 * `list_audit_events` for the TypeScript side: a page of entries the caller
 * can read (security invoker, so the read policy decides), newest first.
 */
export function listEntries(ctx: ModuleContext, restricted: boolean): string {
  const id = ctx.idType;
  const log = ctx.table("log");
  const c = (logical: string) => ctx.col("log", logical);
  const hidden = new Set(
    impersonators(ctx) === "hide"
      ? ["impersonatedBy", "impersonationReason", "supportSession"]
      : [],
  );
  const pairs = ENTRY_KEYS.filter(
    ([logical]) =>
      hasColumn(ctx, "log", logical) &&
      !hidden.has(logical) &&
      !(restricted && (logical === "old" || logical === "new")),
  ).map(([logical, key]) => {
    const value = `l.${c(logical)}`;
    return `'${key}', ${isAuditValueColumn(logical) ? auditRead(ctx, logical, value) : value}`;
  });
  // jsonb_build_object takes at most 100 arguments; split in chunks of 20 keys.
  const chunks: string[] = [];
  for (let index = 0; index < pairs.length; index += 20)
    chunks.push(
      `jsonb_build_object(${pairs.slice(index, index + 20).join(", ")})`,
    );
  const filter = (logical: string, param: string) =>
    hasColumn(ctx, "log", logical)
      ? `
    and (${param} is null or l.${c(logical)} = ${param})`
      : "";
  return `-- A page of the entries the caller can read, newest first: the read policy
-- decides (security invoker). Page with the last entry's occurred_at and id
-- as before_at and before_id.
drop function if exists ${ctx.fn("list_audit_events")}(${id}, text, uuid, text, text, timestamptz, timestamptz, timestamptz, text, integer);
create or replace function ${ctx.fn("list_audit_events")}(
  for_tenant ${id} default null,
  for_event_type text default null,
  for_actor uuid default null,
  for_target_type text default null,
  for_record text default null,
  since timestamptz default null,
  until timestamptz default null,
  before_at timestamptz default null,
  before_id text default null,
  max_items integer default 50
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.entry order by x.occurred_at desc, x.id desc), '[]')
  from (
    select ${chunks.join(" || ")} as entry, l.${c("occurredAt")} as occurred_at, l.${c("id")}::text as id
    from ${log} l
    where (for_tenant is null or l.${c("tenant")} = for_tenant)${filter("eventType", "for_event_type")}${filter("actor", "for_actor")}${filter("targetType", "for_target_type")}${filter("record", "for_record")}
      and (since is null or l.${c("occurredAt")} >= since)
      and (until is null or l.${c("occurredAt")} < until)
      and (before_at is null or (l.${c("occurredAt")}, l.${c("id")}::text) < (before_at, coalesce(before_id, '')))
    order by l.${c("occurredAt")} desc, l.${c("id")}::text desc
    limit least(greatest(coalesce(max_items, 50), 1), 1000)
  ) x
$$;
revoke execute on function ${ctx.fn("list_audit_events")}(${id}, text, uuid, text, text, timestamptz, timestamptz, timestamptz, text, integer) from public, anon;
grant execute on function ${ctx.fn("list_audit_events")}(${id}, text, uuid, text, text, timestamptz, timestamptz, timestamptz, text, integer) to authenticated, service_role;`;
}

/**
 * `reveal_audit_entry(entry)`: the restricted details of one entry, for a
 * member who may reveal them in its tenant (or platform staff), and an
 * `audit.revealed` entry that records who looked.
 */
export function reveal(ctx: ModuleContext, restricted: boolean): string {
  if (!restricted || !ctx.installed("access")) return "";
  const log = ctx.table("log");
  const c = (logical: string) => ctx.col("log", logical);
  const r = (logical: string) => ctx.col("restricted", logical);
  const key = ctx.permission(
    "reveal",
    ctx.permissionKey("view", MODULE_PERMISSIONS.audit.view),
  );
  const viewAll = ctx.permission("viewAll", MODULE_PERMISSIONS.audit.viewAll);
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
    (${SERVICE_CALLER})
    or coalesce(better_supabase.is_platform(${viewAll}), false)
    or (owner is not null and coalesce(better_supabase.member_can(auth.uid(), owner, ${key}), false))
  ) then
    raise exception 'No audit entry %', entry using errcode = 'P0002', hint = 'AUDIT_ENTRY_NOT_FOUND';
  end if;
  select jsonb_build_object('entry', entry${fields}) into details
  from ${ctx.table("restricted")} d where d.${r("entry")}::text = entry;
  perform better_supabase.audit_event(
    event_type => 'audit.revealed',
    category => 'audit',
    target_type => 'audit_entry',
    record_id => entry,
    tenant => owner,
    actor_id => auth.uid()
  );
  return coalesce(details, jsonb_build_object('entry', entry));
end;
$$;
revoke execute on function ${ctx.fn("reveal_audit_entry")}(text) from public, anon;
grant execute on function ${ctx.fn("reveal_audit_entry")}(text) to authenticated, service_role;`;
}
