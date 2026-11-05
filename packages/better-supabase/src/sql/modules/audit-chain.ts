import type { BlockSqlContext } from "../context.ts";

/** Whether `blocks.audit.options.chain` is on for a log the module manages. */
function chainOn(ctx: BlockSqlContext): boolean {
  return ctx.owns("log") && ctx.flag("chain", false);
}

/**
 * Whether `blocks.audit.options.partitioned` is on for a log the module
 * manages.
 */
export function partitionedOn(ctx: BlockSqlContext): boolean {
  return ctx.owns("log") && ctx.flag("partitioned", false);
}

/**
 * The audit log's hash chain (`blocks.audit.options.chain`) is the shared
 * `chain` tag: `chain_seq`, `prev_hash` and `row_hash` on every entry, linked
 * per tenant by `better_supabase.chain`, verified by `verify_chain` and signed
 * in `chain_checkpoints`. A log from before version 13 drops its own trigger
 * and functions and moves its checkpoints; the hashes stay valid because both
 * hash the row the same way.
 */
export function chainSql(ctx: BlockSqlContext): string {
  const log = ctx.table("log");
  const trigger = ctx.trigger("audit_chain");

  if (!chainOn(ctx)) {
    return ctx.owns("log")
      ? `drop trigger if exists ${trigger} on ${log};
drop trigger if exists bsb_chain on ${log};`
      : "";
  }

  const c = (logical: string) => ctx.col("log", logical);
  const t = c("tenant");
  const raw = ctx.colName("log", "tenant");

  return `-- The hash chain: each entry hashes its row with the previous entry's hash
-- of the same tenant, so editing or removing an entry breaks every later
-- link. Purged entries leave the next one's prev_hash as the anchor.
alter table ${log} add column if not exists chain_seq bigint;
alter table ${log} add column if not exists prev_hash bytea;
alter table ${log} add column if not exists row_hash bytea;
create index if not exists audit_events_chain_idx on ${log} (${t}, chain_seq desc) where chain_seq is not null;

drop trigger if exists ${trigger} on ${log};
do $bsb$
begin
  if pg_catalog.to_regclass('better_supabase.audit_checkpoints') is not null then
    insert into better_supabase.chain_checkpoints (table_name, tenant, chain_seq, row_hash, key_id, signature, created_at)
    select '${log}'::regclass::text, pg_catalog.to_jsonb(k) ->> '${raw}', k.chain_seq, k.row_hash, k.key_id, k.signature, k.created_at
    from better_supabase.audit_checkpoints k;
    drop table better_supabase.audit_checkpoints;
  end if;
end
$bsb$;
drop function if exists better_supabase.audit_chain_link();
drop function if exists better_supabase.audit_row_hash(jsonb, bytea);
drop function if exists better_supabase.audit_chain_heads();
drop function if exists better_supabase.verify_audit_chain(${ctx.idType}, timestamptz, timestamptz);
drop function if exists better_supabase.record_audit_checkpoint(${ctx.idType}, bigint, text, text, text);
drop function if exists better_supabase.list_audit_checkpoints(${ctx.idType}, integer);
select better_supabase.chain('${log}', '${raw}');`;
}
