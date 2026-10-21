import type { ModuleContext, ModuleContractFunction } from "../context.ts";

import { lockTable, SERVICE_CALLER, triggerGrant } from "../shared.ts";

/** Whether `blocks.audit.options.chain` is on for a log the module manages. */
export function chainOn(ctx: ModuleContext): boolean {
  return ctx.manages && ctx.flag("chain", false);
}

/**
 * Whether `blocks.audit.options.partitioned` is on for a log the module
 * manages.
 */
export function partitionedOn(ctx: ModuleContext): boolean {
  return ctx.manages && ctx.flag("partitioned", false);
}

export const CHAIN_CONTRACT: readonly ModuleContractFunction[] = [
  {
    name: "verify_audit_chain",
    args: ["{id}", "timestamptz", "timestamptz"],
    returns: "jsonb",
  },
  { name: "audit_chain_heads", args: [], returns: "jsonb" },
  {
    name: "record_audit_checkpoint",
    args: ["{id}", "bigint", "text", "text", "text"],
    returns: "jsonb",
  },
  {
    name: "list_audit_checkpoints",
    args: ["{id}", "integer"],
    returns: "jsonb",
  },
];

const CHECKPOINTS = "better_supabase.audit_checkpoints";

/**
 * A raise with a hint the TypeScript side maps to a code; `42501` maps to
 * `forbidden`.
 */
const fail = (hint: string, message: string, errcode = "42501"): string =>
  `raise exception '${message}' using errcode = '${errcode}', hint = '${hint}';`;

/**
 * The hash chain: `chain_seq`, `prev_hash` and `row_hash` on every entry, set
 * before insert under a per-tenant advisory lock, `verify_audit_chain`, and
 * `audit_checkpoints` that a signing job fills.
 */
export function chainSql(ctx: ModuleContext): string {
  const log = ctx.table("log");
  const trigger = ctx.trigger("audit_chain");

  if (!chainOn(ctx)) {
    return ctx.manages ? `drop trigger if exists ${trigger} on ${log};` : "";
  }

  const id = ctx.idType;
  const c = (logical: string) => ctx.col("log", logical);
  const t = c("tenant");

  const latest = (tenant: string, where = "") => `(
      select l.chain_seq, l.row_hash, l.${c("id")} as entry_id from ${log} l
      where ${tenant === "null" ? `l.${t} is null` : `l.${t} = ${tenant}`} and l.chain_seq is not null${where}
      order by l.chain_seq desc
      limit 1
    )`;

  return `-- The hash chain: each entry hashes its row with the previous entry's hash
-- of the same tenant, so editing or removing an entry breaks every later
-- link. Purged entries leave the next one's prev_hash as the anchor.
alter table ${log} add column if not exists chain_seq bigint;
alter table ${log} add column if not exists prev_hash bytea;
alter table ${log} add column if not exists row_hash bytea;
create index if not exists audit_events_chain_idx on ${log} (${t}, chain_seq desc) where chain_seq is not null;

-- The row as JSON without the hashes and the null columns, so a column
-- added later doesn't change the hash of older entries.
create or replace function better_supabase.audit_row_hash(entry jsonb, prev bytea)
returns bytea
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.sha256(
    coalesce(prev, ''::bytea)
    || pg_catalog.convert_to(pg_catalog.jsonb_strip_nulls(entry - 'prev_hash' - 'row_hash')::text, 'UTF8')
  )
$$;

-- Timestamps render in UTC, so the JSON is the same in every session. An app trigger
-- that changes the row before insert must sort before this one.
create or replace function better_supabase.audit_chain_link()
returns trigger
language plpgsql
security definer
set search_path = ''
set "TimeZone" = 'UTC'
as $$
declare
  v_prev record;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('better_supabase.audit_chain'),
    pg_catalog.hashtext(coalesce(new.${t}::text, ''))
  );
  if new.${t} is null then
    select p.chain_seq, p.row_hash into v_prev from ${latest("null")} p;
  else
    select p.chain_seq, p.row_hash into v_prev from ${latest(`new.${t}`)} p;
  end if;
  new.chain_seq := coalesce(v_prev.chain_seq, 0) + 1;
  new.prev_hash := v_prev.row_hash;
  new.row_hash := better_supabase.audit_row_hash(pg_catalog.to_jsonb(new), v_prev.row_hash);
  return new;
end;
$$;
revoke execute on function better_supabase.audit_row_hash(jsonb, bytea) from public, anon, authenticated;
${triggerGrant("better_supabase.audit_chain_link()")}
drop trigger if exists ${trigger} on ${log};
create trigger ${trigger} before insert on ${log}
  for each row execute function better_supabase.audit_chain_link();

-- Signed chain heads: a job signs each tenant's latest hash with a key of
-- the signing-keys block and records it here, so a rewrite of the whole
-- chain still disagrees with the signatures.
create table if not exists ${CHECKPOINTS} (
  id bigint generated always as identity primary key,
  ${t} ${id},
  chain_seq bigint not null,
  row_hash bytea not null,
  entry_id bigint not null,
  key_id text not null,
  signature text not null,
  created_at timestamptz not null default now()
);
create index if not exists audit_checkpoints_tenant_idx on ${CHECKPOINTS} (${t}, chain_seq desc);
${lockTable(CHECKPOINTS)}

-- Walks the tenant's entries (null: the entries without one) from the first
-- at or after from_at to the last before to_at, in chain order. Returns
-- valid, checked and the last hash, or the first broken entry and why:
-- hash (the row changed), link (prev_hash doesn't match), gap (an entry in
-- the range is missing, or a checkpoint signed one past the last) or
-- checkpoint (a signed head disagrees).
create or replace function better_supabase.verify_audit_chain(
  tenant ${id} default null,
  from_at timestamptz default null,
  to_at timestamptz default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set "TimeZone" = 'UTC'
as $$
declare
  v_row record;
  v_prev_seq bigint;
  v_prev_hash bytea;
  v_checked integer := 0;
  v_from bigint;
  v_to bigint;
  v_signed bytea;
  v_reason text;
begin
  if not (${SERVICE_CALLER}) then
    ${fail("AUDIT_CHAIN_FORBIDDEN", "Only the service role verifies the audit chain")}
  end if;
  select min(l.chain_seq), max(l.chain_seq) into v_from, v_to from ${log} l
  where (case when verify_audit_chain.tenant is null then l.${t} is null else l.${t} = verify_audit_chain.tenant end)
    and l.chain_seq is not null
    and (from_at is null or l.${c("occurredAt")} >= from_at)
    and (to_at is null or l.${c("occurredAt")} < to_at);
  -- A signed head past the last entry means the tail was removed.
  if to_at is null and v_to is not null then
    select greatest(v_to, max(k.chain_seq)) into v_to from ${CHECKPOINTS} k
    where k.${t} is not distinct from verify_audit_chain.tenant;
  end if;
  for v_row in
    select l.${c("id")} as id, l.chain_seq, l.prev_hash, l.row_hash, pg_catalog.to_jsonb(l) as entry
    from ${log} l
    where (case when verify_audit_chain.tenant is null then l.${t} is null else l.${t} = verify_audit_chain.tenant end)
      and l.chain_seq between v_from and v_to
    order by l.chain_seq
  loop
    v_reason := case
      when v_prev_seq is not null and v_row.chain_seq <> v_prev_seq + 1 then 'gap'
      when v_prev_seq is not null and v_row.prev_hash is distinct from v_prev_hash then 'link'
      when better_supabase.audit_row_hash(v_row.entry, v_row.prev_hash) is distinct from v_row.row_hash then 'hash'
    end;
    if v_reason is null then
      select k.row_hash into v_signed from ${CHECKPOINTS} k
      where k.${t} is not distinct from verify_audit_chain.tenant and k.chain_seq = v_row.chain_seq
      order by k.id desc
      limit 1;
      if found and v_signed <> v_row.row_hash then
        v_reason := 'checkpoint';
      end if;
    end if;
    if v_reason is not null then
      return jsonb_build_object('valid', false, 'checked', v_checked, 'brokenAt', v_row.id::text, 'seq', v_row.chain_seq, 'reason', v_reason);
    end if;
    v_checked := v_checked + 1;
    v_prev_seq := v_row.chain_seq;
    v_prev_hash := v_row.row_hash;
  end loop;
  if v_to is not null and v_prev_seq is distinct from v_to then
    return jsonb_build_object('valid', false, 'checked', v_checked, 'seq', v_to, 'reason', 'gap');
  end if;
  return jsonb_build_object('valid', true, 'checked', v_checked, 'seq', v_prev_seq, 'hash', encode(v_prev_hash, 'hex'));
end;
$$;

-- Each tenant's latest entry that no checkpoint covers yet, for the signing job.
create or replace function better_supabase.audit_chain_heads()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_heads jsonb;
begin
  if not (${SERVICE_CALLER}) then
    ${fail("AUDIT_CHAIN_FORBIDDEN", "Only the service role reads the chain heads")}
  end if;
  with recursive tenants (v) as (
    (select l.${t} from ${log} l where l.${t} is not null order by l.${t} limit 1)
    union all
    select (select l.${t} from ${log} l where l.${t} > tenants.v order by l.${t} limit 1)
    from tenants where tenants.v is not null
  ),
  heads as (
    select x.v as tenant, h.* from tenants x cross join lateral ${latest("x.v")} h
    where x.v is not null
    union all
    select null, h.* from ${latest("null")} h
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'tenant', h.tenant::text,
    'seq', h.chain_seq,
    'hash', encode(h.row_hash, 'hex'),
    'entryId', h.entry_id::text
  ) order by h.tenant nulls first), '[]'::jsonb) into v_heads
  from heads h
  where not exists (
    select 1 from ${CHECKPOINTS} k
    where k.${t} is not distinct from h.tenant and k.chain_seq >= h.chain_seq
  );
  return v_heads;
end;
$$;

-- Stores a signed head; refuses one whose hash isn't the entry's.
create or replace function better_supabase.record_audit_checkpoint(
  tenant ${id},
  seq bigint,
  hash text,
  key_id text,
  signature text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_entry bigint;
  v_row ${CHECKPOINTS};
begin
  if not (${SERVICE_CALLER}) then
    ${fail("AUDIT_CHAIN_FORBIDDEN", "Only the service role records checkpoints")}
  end if;
  select l.${c("id")} into v_entry from ${log} l
  where l.${t} is not distinct from record_audit_checkpoint.tenant
    and l.chain_seq = seq
    and l.row_hash = decode(hash, 'hex');
  if v_entry is null then
    ${fail("AUDIT_CHECKPOINT_MISMATCH", "No entry has that hash at that position", "P0001")}
  end if;
  insert into ${CHECKPOINTS} (${t}, chain_seq, row_hash, entry_id, key_id, signature)
  values (record_audit_checkpoint.tenant, seq, decode(hash, 'hex'), v_entry, key_id, signature)
  returning * into v_row;
  return jsonb_build_object(
    'id', v_row.id::text,
    'tenant', v_row.${t}::text,
    'seq', v_row.chain_seq,
    'hash', encode(v_row.row_hash, 'hex'),
    'entryId', v_row.entry_id::text,
    'keyId', v_row.key_id,
    'signature', v_row.signature,
    'createdAt', v_row.created_at
  );
end;
$$;

create or replace function better_supabase.list_audit_checkpoints(tenant ${id} default null, max_rows integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  if not (${SERVICE_CALLER}) then
    ${fail("AUDIT_CHAIN_FORBIDDEN", "Only the service role lists checkpoints")}
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', k.id::text,
    'tenant', k.${t}::text,
    'seq', k.chain_seq,
    'hash', encode(k.row_hash, 'hex'),
    'entryId', k.entry_id::text,
    'keyId', k.key_id,
    'signature', k.signature,
    'createdAt', k.created_at
  ) order by k.chain_seq desc), '[]'::jsonb) into v_rows
  from (
    select * from ${CHECKPOINTS} x
    where x.${t} is not distinct from list_audit_checkpoints.tenant
    order by x.chain_seq desc
    limit max_rows
  ) k;
  return v_rows;
end;
$$;
revoke execute on function better_supabase.verify_audit_chain(${id}, timestamptz, timestamptz) from public, anon, authenticated;
revoke execute on function better_supabase.audit_chain_heads() from public, anon, authenticated;
revoke execute on function better_supabase.record_audit_checkpoint(${id}, bigint, text, text, text) from public, anon, authenticated;
revoke execute on function better_supabase.list_audit_checkpoints(${id}, integer) from public, anon, authenticated;
grant execute on function better_supabase.verify_audit_chain(${id}, timestamptz, timestamptz) to service_role;
grant execute on function better_supabase.audit_chain_heads() to service_role;
grant execute on function better_supabase.record_audit_checkpoint(${id}, bigint, text, text, text) to service_role;
grant execute on function better_supabase.list_audit_checkpoints(${id}, integer) to service_role;`;
}
