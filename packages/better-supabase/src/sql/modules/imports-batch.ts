import type { ImportTargetContribution } from "../contributions.ts";

import { sqlString } from "../../core/template.ts";
import { fail, quotedTable } from "../shared.ts";

/**
 * The SQL pieces `import_apply_batch` needs for targets that name \`batch\`
 * (ADR 0436): the condition that defers an item, the write block of the item
 * loop, and the flush that calls the batch function and records each answer.
 * \`afterWrite\` is the record-map code the one-row path shares.
 */
export function batchSql(input: {
  readonly targets: readonly ImportTargetContribution[];
  readonly dispatch: string;
  readonly records: string;
  readonly unique: string;
  readonly x: (column: string) => string;
  readonly r: (column: string) => string;
}): {
  readonly batched: readonly ImportTargetContribution[];
  readonly batchCondition: string;
  readonly writeBlock: string;
  readonly flushPending: string;
} {
  const { dispatch, records, unique, x, r } = input;

  const batched = input.targets.filter((target) => target.batch !== undefined);

  const batchCondition =
    batched.length === 0
      ? "false"
      : `v_entity = any (array[${batched.map((target) => sqlString(target.entity)).join(", ")}]::text[])`;

  const afterWrite = `v_subjects := case jsonb_typeof(v_out) when 'array' then v_out else jsonb_build_array(v_out) end;
  if not exists (
    select 1 from jsonb_array_elements(v_subjects) s
    where coalesce(s.value ->> 'role', 'primary') = 'primary' and nullif(s.value ->> 'subjectId', '') is not null
  ) then
    ${fail("IMPORT_ITEM_INVALID", "the import target returned no primary subject", "22023")}
  end if;

  for v_subject in select s.value from jsonb_array_elements(v_subjects) s loop
    if jsonb_typeof(v_subject -> 'warnings') = 'array' then
      v_warnings := v_warnings || (select coalesce(jsonb_agg(w.value || jsonb_build_object('entity', v_entity, 'key', v_key)), '[]'::jsonb) from jsonb_array_elements(v_subject -> 'warnings') w);
    end if;
    insert into ${records} (${x("tenant")}, ${x("source")}, ${x("scope")}, ${x("entity")}, ${x("externalKey")}, ${x("role")}, ${x("subjectType")}, ${x("subjectId")}, ${x("contentHash")}, ${x("firstRun")}, ${x("lastRun")}, ${x("subjectUpdatedAt")}, ${x("missingSince")})
    values (
      v_run.${r("tenant")}, v_run.${r("source")}, v_scope, v_entity, v_key,
      coalesce(v_subject ->> 'role', 'primary'),
      coalesce(v_subject ->> 'subjectType', v_subject_type),
      v_subject ->> 'subjectId',
      v_hash, v_run_id, v_run_id,
      coalesce((v_subject ->> 'updatedAt')::timestamptz, now()),
      null
    )
    on conflict ${unique} do update set
      ${x("subjectType")} = excluded.${x("subjectType")},
      ${x("subjectId")} = excluded.${x("subjectId")},
      ${x("contentHash")} = excluded.${x("contentHash")},
      ${x("lastRun")} = excluded.${x("lastRun")},
      ${x("subjectUpdatedAt")} = excluded.${x("subjectUpdatedAt")},
      ${x("missingSince")} = null;
  end loop;

  if v_found then
    v_updated := v_updated + 1;
  else
    v_inserted := v_inserted + 1;
  end if;
  `;

  const deferPending = `v_pending := v_pending || jsonb_build_object('subjectId', v_subject_id, 'found', v_found, 'key', v_key, 'scope', v_scope, 'hash', v_hash);
            v_calls := v_calls || v_call;
            v_pending_keys := v_pending_keys || (v_scope || chr(31) || v_key);`;

  const batchArms = batched
    .map(
      (target) => `        when ${sqlString(target.entity)} then
            v_subject_type := ${sqlString(target.subjectType)};
            v_raw := ${quotedTable(target.batch ?? "")}(v_run_id, to_jsonb(v_calls));`,
    )
    .join("\n");

  const writeBlock =
    batched.length === 0
      ? `${dispatch}

          ${afterWrite}`
      : `if ${batchCondition} then
            ${deferPending}
          else
            ${dispatch}

            ${afterWrite}
          end if;`;

  const flushPending =
    batched.length === 0
      ? ""
      : `if cardinality(v_pending) > 0 then
          begin
            case v_entity
  ${batchArms}
            else
              v_raw := null;
            end case;
            if jsonb_typeof(v_raw) is distinct from 'array' or jsonb_array_length(v_raw) <> cardinality(v_pending) then
              raise exception 'a batch target returns one result per item' using errcode = '22023';
            end if;
            v_results := array(select e.value from jsonb_array_elements(v_raw) e);
          exception when others then
            v_results := null;
          end;
          for v_i in 1 .. cardinality(v_pending) loop
            v_p := v_pending[v_i];
            v_key := v_p ->> 'key';
            v_scope := v_p ->> 'scope';
            v_hash := v_p ->> 'hash';
            v_found := (v_p ->> 'found')::boolean;
            v_subject_id := v_p ->> 'subjectId';
            begin
              if v_results is null then
                v_call := v_calls[v_i];
                ${dispatch}
              else
                v_out := v_results[v_i];
                if jsonb_typeof(v_out) = 'object' and v_out ? 'error' then
                  raise exception '%', coalesce(v_out -> 'error' ->> 'message', 'the import target refused the item')
                    using hint = coalesce(v_out -> 'error' ->> 'code', 'IMPORT_ITEM_INVALID');
                end if;
              end if;
              ${afterWrite}
            exception when others then
              get stacked diagnostics v_message = message_text, v_hint = pg_exception_hint;
              v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), 'message', v_message));
            end;
          end loop;
          v_pending := '{}';
          v_calls := '{}';
          v_pending_keys := '{}';
        end if;`;

  return { batched, batchCondition, writeBlock, flushPending };
}
