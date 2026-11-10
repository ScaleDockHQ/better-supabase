import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { partitionedOn } from "./audit-chain.ts";

/**
 * `convert_audit_log_to_partitioned(batch_size, drop_old)`: moves an audit log
 * created before `options.partitioned` onto monthly partitions while it keeps
 * taking writes. A procedure, so it commits between batches: run it with `call`
 * outside a transaction block.
 *
 * It builds the partitioned table and its indexes beside the old one, copies
 * the rows in id batches, and then, under one short lock that blocks writes but
 * not reads, copies the rows written since, swaps the names and moves the
 * grants, policies and triggers. The old table stays as `<name>_unpartitioned`
 * until `drop_old`. The unique idempotency index gains `occurred_at`, as a
 * partitioned key must. The log is append-only, so rows are copied once.
 */
/* oxlint-disable block-policies/no-raw-policy -- the procedure copies the live policies from pg_policies onto the new table, and no Policy builder describes them (1 finding). */
export function convertSql(ctx: BlockSqlContext): string {
  if (!partitionedOn(ctx)) {
    return "";
  }

  const log = ctx.table("log");
  const id = ctx.col("log", "id");
  const at = ctx.col("log", "occurredAt");
  const { schema, name } = ctx.tableName("log");
  const sequence = `${schema}.${ctx.naming.rename("audit_events_id_seq")}`;
  const proc = ctx.fn("convert_audit_log_to_partitioned");

  return `-- Moves an unpartitioned audit log onto monthly partitions without stopping writes:
-- call ${proc}(50000);  (outside a transaction block). Run it again after a
-- failure; it resumes from the rows already copied.
create or replace procedure ${proc}(batch_size integer default 50000, drop_old boolean default false)
language plpgsql
as $$
declare
  v_old regclass := ${sqlString(log)}::regclass;
  v_schema text := ${sqlString(schema)};
  v_name text := ${sqlString(name)};
  v_next text := ${sqlString(`${name}_partitioned`)};
  v_next_q text := format('%I.%I', ${sqlString(schema)}, ${sqlString(`${name}_partitioned`)});
  v_last bigint := 0;
  v_copied bigint;
  v_first timestamptz;
  v_month timestamp;
  v_end timestamp := date_trunc('month', now() at time zone 'UTC') + interval '3 months';
  v_row record;
begin
  if (select c.relkind from pg_catalog.pg_class c where c.oid = v_old) = 'p' then
    raise notice '% is already partitioned', v_old;
    return;
  end if;
  if batch_size is null or batch_size < 1 then
    raise exception 'batch_size must be at least 1' using errcode = '22023';
  end if;

  if pg_catalog.to_regclass(v_next_q) is null then
    execute format('create table %s (like %s including defaults including constraints including generated) partition by range (${at})', v_next_q, v_old);
    create sequence if not exists ${sequence};
    execute format('alter table %s alter column ${id} set default nextval(%L)', v_next_q, ${sqlString(sequence)});
    execute format('alter table %s add primary key (${id}, ${at})', v_next_q);
    execute format('create table %I.%I partition of %s default', v_schema, v_next || '_default', v_next_q);
    execute format('select min(${at}) from %s', v_old) into v_first;
    v_month := date_trunc('month', coalesce(v_first, now()) at time zone 'UTC');
    while v_month <= v_end loop
      execute format(
        'create table %I.%I partition of %s for values from (%L) to (%L)',
        v_schema, v_next || '_p' || to_char(v_month, 'YYYYMM'), v_next_q,
        v_month at time zone 'UTC', (v_month + interval '1 month') at time zone 'UTC'
      );
      v_month := v_month + interval '1 month';
    end loop;
    -- The other indexes, built while the table is empty and named *_next until the swap.
    for v_row in
      select i.indexname, i.indexdef, x.indisunique
      from pg_catalog.pg_indexes i
      join pg_catalog.pg_class c on c.relname = i.indexname
      join pg_catalog.pg_namespace n on n.oid = c.relnamespace and n.nspname = i.schemaname
      join pg_catalog.pg_index x on x.indexrelid = c.oid
      where i.schemaname = v_schema and i.tablename = v_name and not x.indisprimary
    loop
      execute regexp_replace(
        case when v_row.indisunique
          then regexp_replace(v_row.indexdef, 'USING ([a-z]+) \\(([^)]*)\\)', 'USING \\1 (\\2, ${at})')
          else v_row.indexdef end,
        '^(CREATE (?:UNIQUE )?INDEX )[^ ]+( ON )[^ ]+( USING)',
        '\\1' || quote_ident(v_row.indexname || '_next') || '\\2' || v_next_q || '\\3'
      );
    end loop;
    execute format('alter table %s enable row level security', v_next_q);
    commit;
  end if;

  execute format('select coalesce(max(${id}), 0) from %s', v_next_q) into v_last;
  loop
    execute format(
      'with moved as (insert into %s select * from %s where ${id} > %s order by ${id} limit %s returning ${id}) select count(*), coalesce(max(${id}), %s) from moved',
      v_next_q, v_old, v_last, batch_size, v_last
    ) into v_copied, v_last;
    commit;
    exit when v_copied = 0;
  end loop;

  -- The swap: blocks writes (not reads) while the last rows are copied and the names change.
  execute format('lock table %s in exclusive mode', v_old);
  execute format('insert into %s select * from %s where ${id} > %s', v_next_q, v_old, v_last);
  execute format('select setval(%L, greatest(coalesce((select max(${id}) from %s), 1), 1))', ${sqlString(sequence)}, v_old);
  for v_row in select conrelid::regclass as child, conname from pg_catalog.pg_constraint where confrelid = v_old and contype = 'f' loop
    execute format('alter table %s drop constraint %I', v_row.child, v_row.conname);
  end loop;
  for v_row in select i.indexname from pg_catalog.pg_indexes i where i.schemaname = v_schema and i.tablename = v_name and i.indexname not like '%_next' loop
    execute format('alter index %I.%I rename to %I', v_schema, v_row.indexname, left(v_row.indexname, 52) || '_unpart');
  end loop;
  execute format('alter table %s rename to %I', v_old, v_name || '_unpartitioned');
  execute format('alter table %s rename to %I', v_next_q, v_name);
  execute format('alter table %I.%I rename constraint %I to %I', v_schema, v_name, v_next || '_pkey', v_name || '_pkey');
  for v_row in select i.indexname from pg_catalog.pg_indexes i where i.schemaname = v_schema and i.tablename = v_name and i.indexname like '%_next' loop
    execute format('alter index %I.%I rename to %I', v_schema, v_row.indexname, regexp_replace(v_row.indexname, '_next$', ''));
  end loop;

  for v_row in select * from pg_catalog.pg_policies p where p.schemaname = v_schema and p.tablename = v_name || '_unpartitioned' loop
    execute format(
      'create policy %I on %I.%I as %s for %s to %s%s%s',
      v_row.policyname, v_schema, v_name, v_row.permissive, v_row.cmd, array_to_string(v_row.roles, ', '),
      case when v_row.qual is null then '' else ' using (' || v_row.qual || ')' end,
      case when v_row.with_check is null then '' else ' with check (' || v_row.with_check || ')' end
    );
  end loop;
  for v_row in
    select a.privilege_type, case a.grantee when 0 then 'public' else a.grantee::regrole::text end as grantee
    from pg_catalog.pg_class c, aclexplode(c.relacl) a
    where c.oid = format('%I.%I', v_schema, v_name || '_unpartitioned')::regclass
  loop
    execute format('grant %s on %I.%I to %s', v_row.privilege_type, v_schema, v_name, v_row.grantee);
  end loop;
  for v_row in
    select pg_get_triggerdef(t.oid) as def
    from pg_catalog.pg_trigger t
    where t.tgrelid = format('%I.%I', v_schema, v_name || '_unpartitioned')::regclass and not t.tgisinternal
  loop
    execute regexp_replace(v_row.def, ' ON [^ ]+ ', ' ON ' || format('%I.%I', v_schema, v_name) || ' ');
  end loop;

  insert into better_supabase.partitioned_tables (parent, months_ahead)
  values (format('%I.%I', v_schema, v_name)::regclass, 3)
  on conflict (parent) do nothing;
  if drop_old then
    execute format('drop table %I.%I', v_schema, v_name || '_unpartitioned');
  end if;
  commit;
end;
$$;
revoke execute on procedure ${proc}(integer, boolean) from public, anon, authenticated;
grant execute on procedure ${proc}(integer, boolean) to service_role;`;
}
