import { MAX_BATCH } from "../../core/batch-limit.ts";
import { fail, userGrant } from "../shared.ts";

/** What `prune_deadlines` and `compute_deadlines_many` need of the module. */
export interface DeadlinePruneKit {
  /** The caller's write check on a tenant expression. */
  readonly allowed: (tenant: string) => string;
  /**
   * The caller's prune check, which deleting history (`pending_only` false)
   * needs.
   */
  readonly prunes: (tenant: string) => string;
  /** Whether the caller may read subject `type`/`id` in `tenant`. */
  readonly visible: (type: string, id: string, tenant: string) => string;
  readonly d: (column: string) => string;
  readonly deadlines: string;
  readonly fn: (name: string) => string;
  readonly idType: string;
}

/** `prune_deadlines` and `compute_deadlines_many`. */
export function deadlinePruneSql(kit: DeadlinePruneKit): string {
  const { allowed, prunes, visible, d, deadlines, fn, idType } = kit;

  return `
-- Deletes a subject's deadlines and returns how many: the pending ones of every
-- jurisdiction but keep_jurisdiction (all pending ones without it), or with
-- pending_only false every deadline, satisfied history included, as when the
-- subject goes. Needs deadlines.write and read access to the subject, and
-- the prune key (deadlines.manage unless permissions.prune names another) to
-- delete more than the pending ones.
create or replace function ${fn("prune_deadlines")}(tenant ${idType}, subject_type text, subject_id text, keep_jurisdiction text default null, pending_only boolean default true)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_count integer;
begin
  if not ${allowed("prune_deadlines.tenant")} then
    ${fail("DEADLINE_FORBIDDEN", "not allowed to prune deadlines")}
  end if;
  if not coalesce(prune_deadlines.pending_only, true) and not ${prunes("prune_deadlines.tenant")} then
    ${fail("DEADLINE_FORBIDDEN", "not allowed to delete settled deadlines")}
  end if;
  if not ${visible("prune_deadlines.subject_type", "prune_deadlines.subject_id", "prune_deadlines.tenant")} then
    ${fail("DEADLINE_FORBIDDEN", "not allowed to prune deadlines for this subject")}
  end if;
  delete from ${deadlines} x
  where x.${d("tenant")} = prune_deadlines.tenant
    and x.${d("subjectType")} = prune_deadlines.subject_type
    and x.${d("subjectId")} = prune_deadlines.subject_id
    and (not coalesce(prune_deadlines.pending_only, true) or x.${d("state")} = 'pending')
    and (prune_deadlines.keep_jurisdiction is null or x.${d("jurisdiction")} <> prune_deadlines.keep_jurisdiction);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
${userGrant(`${fn("prune_deadlines")}(${idType}, text, text, text, boolean)`)}

-- compute_deadlines for up to ${String(MAX_BATCH)} subjects in one call. items is a list of
-- { subjectType, subjectId, jurisdiction, kind, facts, asOf, group }; with prune,
-- each subject's pending deadlines of other jurisdictions go first. One failed
-- item doesn't undo the others: it answers { ok: false, hint, message }, the
-- rest { ok: true, deadlines }, in the order given.
create or replace function ${fn("compute_deadlines_many")}(tenant ${idType}, items jsonb, prune boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_item jsonb;
  v_out jsonb := '[]'::jsonb;
  v_hint text;
  v_message text;
begin
  if jsonb_typeof(compute_deadlines_many.items) is distinct from 'array' or jsonb_array_length(compute_deadlines_many.items) > ${String(MAX_BATCH)} then
    ${fail("DEADLINE_INVALID", `items is a list of at most ${String(MAX_BATCH)} subjects`, "22023")}
  end if;
  for v_item in select value from jsonb_array_elements(compute_deadlines_many.items) loop
    begin
      if compute_deadlines_many.prune then
        perform ${fn("prune_deadlines")}(compute_deadlines_many.tenant, v_item ->> 'subjectType', v_item ->> 'subjectId', v_item ->> 'jurisdiction');
      end if;
      v_out := v_out || jsonb_build_array(jsonb_build_object(
        'subjectType', v_item ->> 'subjectType',
        'subjectId', v_item ->> 'subjectId',
        'ok', true,
        'deadlines', ${fn("compute_deadlines")}(
          compute_deadlines_many.tenant,
          v_item ->> 'subjectType',
          v_item ->> 'subjectId',
          v_item ->> 'jurisdiction',
          v_item ->> 'kind',
          coalesce(v_item -> 'facts', '{}'::jsonb),
          coalesce((v_item ->> 'asOf')::date, current_date),
          v_item ->> 'group'
        )
      ));
    exception when others then
      get stacked diagnostics v_hint = pg_exception_hint, v_message = message_text;
      v_out := v_out || jsonb_build_array(jsonb_build_object(
        'subjectType', v_item ->> 'subjectType',
        'subjectId', v_item ->> 'subjectId',
        'ok', false,
        'hint', nullif(v_hint, ''),
        'message', v_message
      ));
    end;
  end loop;
  return v_out;
end;
$$;
${userGrant(`${fn("compute_deadlines_many")}(${idType}, jsonb, boolean)`)}
`;
}
