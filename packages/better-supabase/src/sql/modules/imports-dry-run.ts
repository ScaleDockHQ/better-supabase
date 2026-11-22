import type { BlockSqlContext } from "../context.ts";

import { ISSUES } from "./imports-issues.ts";

/**
 * Re-records what a dry-run batch found. The batch ran in a subtransaction it
 * rolled back, which took its issue rows with it, so the report keeps them from
 * the result instead.
 */
export function dryRunIssues(ctx: BlockSqlContext): string {
  const note = ctx.fn("import_note_issue");

  return `
  if v_run.${ctx.col("runs", "dryRun")} then
    for v_row in select e.value from jsonb_array_elements(coalesce(v_result -> 'conflictKeys', '[]'::jsonb)) e loop
      perform ${note}(v_run_id, v_entity, v_row #>> '{}', 'conflict', 'IMPORT_CONFLICT', 'the subject changed after the last import');
    end loop;
    for v_row in select e.value from jsonb_array_elements(coalesce(v_result -> 'errors', '[]'::jsonb)) e loop
      perform ${note}(v_run_id, v_entity, v_row ->> 'key', 'error', coalesce(nullif(v_row ->> 'code', ''), 'IMPORT_ITEM_INVALID'), coalesce(v_row ->> 'message', ''));
    end loop;
    perform ${ctx.fn("import_note_warnings")}(v_run_id, v_entity, v_result -> 'warnings');
  end if;`;
}

/** What canceling a dry run removes: its stored chunks and the issues it noted. */
export function dryRunCleanup(ctx: BlockSqlContext): string {
  const chunks = ctx.table("chunks");
  const c = (column: string): string => ctx.col("chunks", column);

  return `
  if v_run.${ctx.col("runs", "dryRun")} then
    delete from ${chunks} x where x.${c("run")} = cancel_import_run.id;
    delete from ${ISSUES(ctx)} i where i."run_id" = cancel_import_run.id;
  end if;`;
}

/**
 * Reads the import records of every item of a batch in one query, so the loop
 * looks each one up in memory. A key that appears twice in the batch is read
 * live the second time, because the first write changed its record.
 */
export function recordPrefetch(
  ctx: BlockSqlContext,
  records: string,
): {
  readonly declare: string;
  readonly load: string;
  readonly lookup: string;
} {
  const x = (column: string): string => ctx.col("records", column);
  const r = (column: string): string => ctx.col("runs", column);

  return {
    declare: "  v_known jsonb;\n  v_seen text[] := '{}';\n  v_slot text;\n",
    load: `v_known := coalesce((
    select jsonb_object_agg(k.${x("scope")} || chr(31) || k.${x("externalKey")}, to_jsonb(k))
    from ${records} k
    where k.${x("tenant")} = v_run.${r("tenant")} and k.${x("source")} = v_run.${r("source")}
      and k.${x("entity")} = v_entity and k.${x("role")} = 'primary'
      and (k.${x("scope")}, k.${x("externalKey")}) in (
        select coalesce(e.value ->> 'scope', ''), e.value ->> 'key' from jsonb_array_elements(v_items) e
      )
  ), '{}'::jsonb);`,
    lookup: `v_slot := v_scope || chr(31) || v_key;
      if v_slot = any (v_seen) then
        select * into v_rec from ${records} x
        where x.${x("tenant")} = v_run.${r("tenant")} and x.${x("source")} = v_run.${r("source")} and x.${x("scope")} = v_scope
          and x.${x("entity")} = v_entity and x.${x("externalKey")} = v_key and x.${x("role")} = 'primary';
        v_found := found;
      elsif v_known ? v_slot then
        v_rec := jsonb_populate_record(null::${records}, v_known -> v_slot);
        v_found := true;
      else
        v_rec := null;
        v_found := false;
      end if;
      v_seen := v_seen || v_slot;`,
  };
}
