SET local check_function_bodies = off;

DROP FUNCTION "better_supabase"."ensure_chain_checkpoints"();

CREATE TABLE "better_supabase"."chain_checkpoints" (
  "id"         bigint                   GENERATED ALWAYS AS IDENTITY NOT NULL,
  "table_name" text                     NOT NULL,
  "tenant"     text,
  "chain_seq"  bigint                   NOT NULL,
  "row_hash"   bytea                    NOT NULL,
  "key_id"     text                     NOT NULL,
  "signature"  text                     NOT NULL,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "chain_checkpoints_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."chain_checkpoints"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION better_supabase.chain (
  target        regclass,
  tenant_column text     DEFAULT NULL::text
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_tenant text := coalesce(tenant_column, (
    select a.attname::text from pg_catalog.pg_attribute a
    where a.attrelid = target and a.attname = '"organization_id"' and not a.attisdropped
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.verify_chain (
  target        regclass,
  tenant_column text     DEFAULT NULL::text,
  tenant        text     DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  SET "TimeZone" TO 'UTC'
  AS $function$
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
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
      select k.row_hash into v_signed from better_supabase.chain_checkpoints k
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
  select max(k.chain_seq) into v_max from better_supabase.chain_checkpoints k
  where k.table_name = target::text and k.tenant is not distinct from verify_chain.tenant;
  if v_max is not null and v_prev_seq is distinct from v_max and coalesce(v_prev_seq, 0) < v_max then
    return jsonb_build_object('valid', false, 'checked', v_checked, 'seq', v_max, 'reason', 'gap');
  end if;
  return jsonb_build_object('valid', true, 'checked', v_checked, 'seq', v_prev_seq, 'hash', encode(v_prev_hash, 'hex'));
end;
$function$;

CREATE INDEX chain_checkpoints_idx ON better_supabase.chain_checkpoints USING btree (table_name, tenant, chain_seq DESC);

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."chain_checkpoints" TO "service_role";
