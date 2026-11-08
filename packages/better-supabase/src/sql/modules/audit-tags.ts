import type { BlockSqlContext } from "../context.ts";

import { lockTable, SERVICE_CALLER, triggerGrant } from "../shared.ts";

const CHECKPOINTS = "better_supabase.chain_checkpoints";

/**
 * Helpers behind the `append-only`, `function-writes` and `chain` table tags.
 * The audit module installs them, so any app table can use them without turning
 * the audit log's own options on.
 */
export function tagSql(ctx: BlockSqlContext): string {
  // The audit log's tenant column name, so an app that renames it gets the same default.
  const tenant = `'${ctx.col("log", "tenant")}'`;

  return `-- Tables the app must not edit: append_only refuses update, delete and
-- truncate for every role; function_writes also takes the Data API write
-- privileges away, so rows arrive only through security definer functions.
create or replace function better_supabase.append_only_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception '% is append-only', tg_table_name
    using errcode = '42501', hint = 'TABLE_APPEND_ONLY';
end;
$$;
${triggerGrant("better_supabase.append_only_guard()")}

create or replace function better_supabase.append_only(target regclass)
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('drop trigger if exists bsb_append_only on %s', target);
  execute format('create trigger bsb_append_only before update or delete on %s for each row execute function better_supabase.append_only_guard()', target);
  execute format('drop trigger if exists bsb_append_only_truncate on %s', target);
  execute format('create trigger bsb_append_only_truncate before truncate on %s for each statement execute function better_supabase.append_only_guard()', target);
end;
$$;

create or replace function better_supabase.function_writes(target regclass)
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('revoke insert, update, delete, truncate on %s from public, anon, authenticated', target);
end;
$$;

-- The hash chain for any table: chain_seq, prev_hash and row_hash columns the
-- table declares, linked per tenant column value (or one chain without a
-- tenant column) under an advisory lock.
create or replace function better_supabase.chain_row_hash(entry jsonb, prev bytea)
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

create or replace function better_supabase.chain_link()
returns trigger
language plpgsql
security definer
set search_path = ''
set "TimeZone" = 'UTC'
as $$
declare
  v_column text := nullif(tg_argv[0], '');
  v_prev record;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('better_supabase.chain:' || tg_relid::text),
    pg_catalog.hashtext(coalesce(case when v_column is null then '' else pg_catalog.to_jsonb(new) ->> v_column end, ''))
  );
  if v_column is null then
    execute format('select p.chain_seq, p.row_hash from %s p where p.chain_seq is not null order by p.chain_seq desc limit 1', tg_relid::regclass)
      into v_prev;
  elsif pg_catalog.to_jsonb(new) ->> v_column is null then
    execute format('select p.chain_seq, p.row_hash from %s p where p.%I is null and p.chain_seq is not null order by p.chain_seq desc limit 1', tg_relid::regclass, v_column)
      into v_prev;
  else
    execute format('select p.chain_seq, p.row_hash from %s p where p.%I = ($1).%I and p.chain_seq is not null order by p.chain_seq desc limit 1', tg_relid::regclass, v_column, v_column)
      into v_prev using new;
  end if;
  new.chain_seq := coalesce(v_prev.chain_seq, 0) + 1;
  new.prev_hash := v_prev.row_hash;
  new.row_hash := better_supabase.chain_row_hash(pg_catalog.to_jsonb(new), v_prev.row_hash);
  return new;
end;
$$;
${triggerGrant("better_supabase.chain_link()")}

create or replace function better_supabase.chain(target regclass, tenant_column text default null)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_tenant text := coalesce(tenant_column, (
    select a.attname::text from pg_catalog.pg_attribute a
    where a.attrelid = target and a.attname = ${tenant} and not a.attisdropped
  ), '');
begin
  if (select count(*) from pg_catalog.pg_attribute a
      where a.attrelid = target and a.attname in ('chain_seq', 'prev_hash', 'row_hash') and not a.attisdropped) <> 3 then
    raise exception 'chain needs the columns chain_seq bigint, prev_hash bytea and row_hash bytea on %', target
      using errcode = '42703', hint = 'CHAIN_COLUMNS';
  end if;
  execute format('drop trigger if exists bsb_chain on %s', target);
  execute format('create trigger bsb_chain before insert on %s for each row execute function better_supabase.chain_link(%L)', target, v_tenant);
end;
$$;

-- Signed heads of any chained table, recorded by a signing job.
create table if not exists ${CHECKPOINTS} (
  id bigint generated always as identity primary key,
  table_name text not null,
  tenant text,
  chain_seq bigint not null,
  row_hash bytea not null,
  key_id text not null,
  signature text not null,
  created_at timestamptz not null default now()
);
create index if not exists chain_checkpoints_idx on ${CHECKPOINTS} (table_name, tenant, chain_seq desc);
${lockTable(CHECKPOINTS)}

-- Walks one chain in order. Returns valid, checked and the last hash, or the
-- first broken row and why: hash (the row changed), link (prev_hash doesn't
-- match), gap (a row is missing) or checkpoint (a signed head disagrees).
create or replace function better_supabase.verify_chain(target regclass, tenant_column text default null, tenant text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set "TimeZone" = 'UTC'
as $$
declare
  v_seq bigint;
  v_link bytea;
  v_hash bytea;
  v_entry jsonb;
  v_prev_seq bigint;
  v_prev_hash bytea;
  v_checked integer := 0;
  v_reason text;
  v_signed bytea;
  v_max bigint;
  v_where text := case
    when tenant_column is null then 'true'
    when tenant is null then format('t.%I is null', tenant_column)
    else format('t.%I::text = %L', tenant_column, tenant)
  end;
begin
  if not (${SERVICE_CALLER}) then
    raise exception 'Only the service role verifies a chain' using errcode = '42501', hint = 'CHAIN_FORBIDDEN';
  end if;
  for v_seq, v_link, v_hash, v_entry in execute format(
    'select t.chain_seq, t.prev_hash, t.row_hash, pg_catalog.to_jsonb(t) as entry from %s t where %s and t.chain_seq is not null order by t.chain_seq',
    target, v_where
  ) loop
    v_reason := case
      when v_prev_seq is not null and v_seq <> v_prev_seq + 1 then 'gap'
      when v_prev_seq is not null and v_link is distinct from v_prev_hash then 'link'
      when better_supabase.chain_row_hash(v_entry, v_link) is distinct from v_hash then 'hash'
    end;
    if v_reason is null then
      select k.row_hash into v_signed from ${CHECKPOINTS} k
      where k.table_name = target::text and k.tenant is not distinct from verify_chain.tenant and k.chain_seq = v_seq
      order by k.id desc limit 1;
      if found and v_signed <> v_hash then
        v_reason := 'checkpoint';
      end if;
    end if;
    if v_reason is not null then
      return jsonb_build_object('valid', false, 'checked', v_checked, 'seq', v_seq, 'reason', v_reason);
    end if;
    v_checked := v_checked + 1;
    v_prev_seq := v_seq;
    v_prev_hash := v_hash;
  end loop;
  -- A signed head past the last row means the tail was removed.
  select max(k.chain_seq) into v_max from ${CHECKPOINTS} k
  where k.table_name = target::text and k.tenant is not distinct from verify_chain.tenant;
  if v_max is not null and v_prev_seq is distinct from v_max and coalesce(v_prev_seq, 0) < v_max then
    return jsonb_build_object('valid', false, 'checked', v_checked, 'seq', v_max, 'reason', 'gap');
  end if;
  return jsonb_build_object('valid', true, 'checked', v_checked, 'seq', v_prev_seq, 'hash', encode(v_prev_hash, 'hex'));
end;
$$;


-- Each tenant's latest row that no checkpoint covers yet, for the signing job.
create or replace function better_supabase.chain_heads(target regclass, tenant_column text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant text := case when tenant_column is null then 'null::text' else format('t.%I::text', tenant_column) end;
  v_heads jsonb;
begin
  if not (${SERVICE_CALLER}) then
    raise exception 'Only the service role reads chain heads' using errcode = '42501', hint = 'CHAIN_FORBIDDEN';
  end if;
  execute format($q$
    select coalesce(jsonb_agg(jsonb_build_object('tenant', h.tenant, 'seq', h.chain_seq, 'hash', encode(h.row_hash, 'hex')) order by h.tenant nulls first), '[]'::jsonb)
    from (
      select distinct on (%1$s) %1$s as tenant, t.chain_seq, t.row_hash
      from %2$s t where t.chain_seq is not null
      order by %1$s, t.chain_seq desc
    ) h
    where not exists (
      select 1 from ${CHECKPOINTS} k
      where k.table_name = %3$L and k.tenant is not distinct from h.tenant and k.chain_seq >= h.chain_seq
    )
  $q$, v_tenant, target, target::text) into v_heads;
  return v_heads;
end;
$$;

create or replace function better_supabase.list_chain_checkpoints(target regclass, tenant text default null, max_rows integer default 100)
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
    raise exception 'Only the service role lists checkpoints' using errcode = '42501', hint = 'CHAIN_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', k.id::text, 'tenant', k.tenant, 'seq', k.chain_seq, 'hash', encode(k.row_hash, 'hex'),
    'keyId', k.key_id, 'signature', k.signature, 'createdAt', k.created_at
  ) order by k.chain_seq desc), '[]'::jsonb) into v_rows
  from (
    select * from ${CHECKPOINTS} x
    where x.table_name = target::text and x.tenant is not distinct from list_chain_checkpoints.tenant
    order by x.chain_seq desc limit max_rows
  ) k;
  return v_rows;
end;
$$;

-- The proof for one row: the rows from it up to the first signed checkpoint
-- that covers it (or the chain head when none does), and that checkpoint.
create or replace function better_supabase.chain_proof(target regclass, tenant_column text, tenant text, seq bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set "TimeZone" = 'UTC'
as $$
declare
  v_where text := case
    when tenant_column is null then 'true'
    when tenant is null then format('t.%I is null', tenant_column)
    else format('t.%I::text = %L', tenant_column, tenant)
  end;
  v_checkpoint record;
  v_entries jsonb;
begin
  if not (${SERVICE_CALLER}) then
    raise exception 'Only the service role builds chain proofs' using errcode = '42501', hint = 'CHAIN_FORBIDDEN';
  end if;
  select k.chain_seq, k.row_hash, k.key_id, k.signature into v_checkpoint from ${CHECKPOINTS} k
  where k.table_name = target::text and k.tenant is not distinct from chain_proof.tenant and k.chain_seq >= chain_proof.seq
  order by k.chain_seq limit 1;
  execute format($q$
    select coalesce(jsonb_agg(jsonb_build_object(
      'seq', t.chain_seq, 'prevHash', encode(t.prev_hash, 'hex'), 'rowHash', encode(t.row_hash, 'hex'), 'entry', pg_catalog.to_jsonb(t),
      'hashed', pg_catalog.jsonb_strip_nulls(pg_catalog.to_jsonb(t) - 'prev_hash' - 'row_hash')::text
    ) order by t.chain_seq), '[]'::jsonb)
    from %1$s t where %2$s and t.chain_seq between $1 and coalesce($2, t.chain_seq)
  $q$, target, v_where) into v_entries using seq, v_checkpoint.chain_seq;
  return jsonb_build_object(
    'table', target::text,
    'tenant', tenant,
    'entries', v_entries,
    'checkpoint', case when v_checkpoint.chain_seq is null then null else jsonb_build_object(
      'seq', v_checkpoint.chain_seq, 'hash', encode(v_checkpoint.row_hash, 'hex'),
      'keyId', v_checkpoint.key_id, 'signature', v_checkpoint.signature) end
  );
end;
$$;

create or replace function better_supabase.record_chain_checkpoint(
  target regclass, tenant_column text, tenant text, seq bigint, hash text, key_id text, signature text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_found boolean;
  v_where text := case
    when tenant_column is null then 'true'
    when tenant is null then format('t.%I is null', tenant_column)
    else format('t.%I::text = %L', tenant_column, tenant)
  end;
  v_id bigint;
begin
  if not (${SERVICE_CALLER}) then
    raise exception 'Only the service role records checkpoints' using errcode = '42501', hint = 'CHAIN_FORBIDDEN';
  end if;
  execute format('select exists (select 1 from %s t where %s and t.chain_seq = $1 and t.row_hash = decode($2, ''hex''))', target, v_where)
    into v_found using seq, hash;
  if not v_found then
    raise exception 'No row has that hash at that position' using errcode = 'P0001', hint = 'CHECKPOINT_MISMATCH';
  end if;
  insert into ${CHECKPOINTS} (table_name, tenant, chain_seq, row_hash, key_id, signature)
  values (target::text, record_chain_checkpoint.tenant, seq, decode(hash, 'hex'), key_id, signature)
  returning id into v_id;
  return jsonb_build_object('id', v_id::text, 'tenant', record_chain_checkpoint.tenant, 'seq', seq, 'hash', hash, 'keyId', key_id, 'signature', record_chain_checkpoint.signature);
end;
$$;
revoke execute on function better_supabase.chain_heads(regclass, text) from public, anon, authenticated;
revoke execute on function better_supabase.list_chain_checkpoints(regclass, text, integer) from public, anon, authenticated;
revoke execute on function better_supabase.chain_proof(regclass, text, text, bigint) from public, anon, authenticated;
grant execute on function better_supabase.chain_heads(regclass, text) to service_role;
grant execute on function better_supabase.list_chain_checkpoints(regclass, text, integer) to service_role;
grant execute on function better_supabase.chain_proof(regclass, text, text, bigint) to service_role;
revoke execute on function better_supabase.append_only(regclass) from public, anon, authenticated;
revoke execute on function better_supabase.function_writes(regclass) from public, anon, authenticated;
revoke execute on function better_supabase.chain(regclass, text) from public, anon, authenticated;
revoke execute on function better_supabase.chain_row_hash(jsonb, bytea) from public, anon, authenticated;
revoke execute on function better_supabase.verify_chain(regclass, text, text) from public, anon, authenticated;
revoke execute on function better_supabase.record_chain_checkpoint(regclass, text, text, bigint, text, text, text) from public, anon, authenticated;
grant execute on function better_supabase.verify_chain(regclass, text, text) to service_role;
grant execute on function better_supabase.record_chain_checkpoint(regclass, text, text, bigint, text, text, text) to service_role;`;
}
