SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.record_chain_checkpoint (
  target        regclass,
  tenant_column text,
  tenant        text,
  seq           bigint,
  hash          text,
  key_id        text,
  signature     text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_found boolean;
  v_where text := case
    when tenant_column is null then 'true'
    when tenant is null then format('t.%I is null', tenant_column)
    else format('t.%I::text = %L', tenant_column, tenant)
  end;
  v_id bigint;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role records checkpoints' using errcode = '42501', hint = 'CHAIN_FORBIDDEN';
  end if;
  execute format('select exists (select 1 from %s t where %s and t.chain_seq = $1 and t.row_hash = decode($2, ''hex''))', target, v_where)
    into v_found using seq, hash;
  if not v_found then
    raise exception 'No row has that hash at that position' using errcode = 'P0001', hint = 'CHECKPOINT_MISMATCH';
  end if;
  insert into better_supabase.chain_checkpoints (table_name, tenant, chain_seq, row_hash, key_id, signature)
  values (target::text, record_chain_checkpoint.tenant, seq, decode(hash, 'hex'), key_id, signature)
  returning id into v_id;
  return jsonb_build_object('id', v_id::text, 'tenant', record_chain_checkpoint.tenant, 'seq', seq, 'hash', hash, 'keyId', key_id, 'signature', record_chain_checkpoint.signature);
end;
$function$;

drop trigger if exists bsb_chain on better_supabase.audit_events;
insert into better_supabase.blocks (name, version, mode)
values ('audit', 13, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
