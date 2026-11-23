/**
 * The shared parts of a built-in batch target (ADR 1217): a batch function
 * writes the items its set-based statement accepts and hands every other item
 * to the entity's one-row `write`, so an update, a refused item or an edge the
 * statement doesn't cover answers exactly as the one-row path does.
 */

/** The declarations every batch function starts with. */
export const BATCH_DECLARE: string = `  v_done jsonb[] := array_fill(null::jsonb, array[jsonb_array_length(items)]);
  v_row record;
  v_call jsonb;
  v_message text;
  v_hint text;`;

/**
 * The loop that writes each item the set-based statement left, through `write`,
 * and answers with the array the import loop reads: one entry per item, either
 * what `write` returned or `{ "error": { code, message } }`.
 */
export function batchRest(write: string): string {
  return `  for v_i in 1 .. jsonb_array_length(items) loop
    if v_done[v_i] is null then
      v_call := items -> (v_i - 1);
      begin
        v_done[v_i] := ${write}(run, v_call, nullif(v_call ->> 'subjectId', ''));
      exception when others then
        get stacked diagnostics v_message = message_text, v_hint = pg_exception_hint;
        v_done[v_i] := jsonb_build_object('error', jsonb_build_object('code', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), 'message', v_message));
      end;
    end if;
  end loop;
  return to_jsonb(v_done);`;
}

/** Text that casts to `type`, or null; `pg_input_is_valid` never raises. */
export function castOrNull(text: string, type: string): string {
  return `case when pg_input_is_valid(coalesce(${text}, ''), '${type}') then (${text})::${type} end`;
}
