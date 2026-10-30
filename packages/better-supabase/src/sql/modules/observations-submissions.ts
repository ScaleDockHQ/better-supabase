import type { BlockSqlContext } from "../context.ts";

import { fail, triggerGrant, userGrant } from "../shared.ts";
import {
  observationChecks,
  observationJson,
} from "./observations-functions.ts";
import { observationForms } from "./observations-shared.ts";
import { moduleOperations } from "./permissions-model.ts";

/**
 * Observations from form submissions: a field whose `meta.observation` names a
 * definition key records its answer, and fields that share the key with a
 * `meta.component` each fill one component. A trigger records them when a
 * submission about a record is submitted; `observations_from_submission` does
 * it on demand. Each definition is recorded once per submission.
 */
export function observationSubmissions(ctx: BlockSqlContext): string {
  if (!observationForms(ctx)) {
    return "";
  }

  const forms = ctx.of("forms");
  const s = (column: string): string => forms.col("submissions", column);
  const v = (column: string): string => forms.col("versions", column);
  const submissions = forms.table("submissions");
  const versions = forms.table("versions");
  const definitions = ctx.table("definitions");
  const observations = ctx.table("observations");
  const d = (column: string): string => ctx.col("definitions", column);
  const o = (column: string): string => ctx.col("observations", column);
  const fn = (name: string): string => ctx.fn(name);
  const trigger = ctx.trigger("observation_submission");
  const { allowed, subject, forbidden, invalid } = observationChecks(ctx);

  const record = ctx.permission(
    "record",
    moduleOperations("observations").record,
  );

  const skipOr = (raise: string): string => `if p_quiet then
      return '[]'::jsonb;
    end if;
    ${raise}`;

  return `
-- Records the observations a submission's fields map to. p_quiet skips a
-- submission the caller can't record for, which the trigger relies on.
create or replace function ${fn("observation_submission_apply")}(p_submission uuid, p_quiet boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sub ${submissions}%rowtype;
  v_form jsonb;
  v_field jsonb;
  v_key text;
  v_part text;
  v_answer jsonb;
  v_values jsonb := '{}'::jsonb;
  v_entry record;
  v_definition uuid;
  v_row ${observations}%rowtype;
  v_def ${definitions}%rowtype;
  v_out jsonb := '[]'::jsonb;
begin
  select * into v_sub from ${submissions} x where x.${s("id")} = p_submission;
  if not found then
    ${skipOr(fail("OBSERVATION_NOT_FOUND", "form submission not found", "P0002"))}
  end if;
  if v_sub.${s("subjectType")} is null or v_sub.${s("subjectId")} is null then
    ${skipOr(invalid("the submission isn't about a record"))}
  end if;
  if v_sub.${s("status")}::text not in ('submitted', 'accepted') then
    ${skipOr(invalid("the submission isn't submitted"))}
  end if;
  if not (${allowed(`v_sub.${s("tenant")}`, record)} and ${subject(`v_sub.${s("tenant")}`, `v_sub.${s("subjectType")}::text`, `v_sub.${s("subjectId")}::text`)}) then
    ${skipOr(forbidden("not allowed to record observations for this record"))}
  end if;
  select x.${v("definition")} into v_form from ${versions} x where x.${v("id")} = v_sub.${s("version")};
  for v_field in
    select f from jsonb_array_elements(coalesce(v_form -> 'steps', '[]'::jsonb)) st
    cross join lateral jsonb_array_elements(coalesce(st -> 'fields', '[]'::jsonb)) f
    where jsonb_typeof(f -> 'meta' -> 'observation') = 'string'
  loop
    v_key := v_field -> 'meta' ->> 'observation';
    v_answer := v_sub.${s("answers")} -> (v_field ->> 'key');
    if v_answer is null or v_answer in ('null'::jsonb, '""'::jsonb) then
      continue;
    end if;
    v_part := v_field -> 'meta' ->> 'component';
    if v_part is null then
      v_values := v_values || jsonb_build_object(v_key, v_answer);
    else
      v_values := v_values || jsonb_build_object(v_key, coalesce(v_values -> v_key, '{}'::jsonb) || jsonb_build_object(v_part, v_answer));
    end if;
  end loop;
  for v_entry in select e.key, e.value from jsonb_each(v_values) e loop
    select x.${d("id")} into v_definition from ${definitions} x
    where x.${d("key")} = v_entry.key and (x.${d("tenant")} = v_sub.${s("tenant")} or x.${d("tenant")} is null)
    order by x.${d("tenant")} nulls last
    limit 1;
    if v_definition is null then
      if p_quiet then
        continue;
      end if;
      ${fail("OBSERVATION_DEFINITION_NOT_FOUND", "a field names an observation definition that doesn't exist", "P0002")}
    end if;
    if exists (select 1 from ${observations} x where x.${o("submission")} = v_sub.${s("id")} and x.${o("definition")} = v_definition) then
      continue;
    end if;
    select * into v_row from ${fn("observation_insert")}(v_sub.${s("tenant")}, v_definition, v_sub.${s("subjectType")}::text, v_sub.${s("subjectId")}::text, v_entry.value, coalesce(v_sub.${s("submittedAt")}, now()), null, 'form', null, v_sub.${s("id")}, v_sub.${s("respondent")}, null, null);
    select * into v_def from ${definitions} x where x.${d("id")} = v_row.${o("definition")};
    v_out := v_out || jsonb_build_array(${observationJson(ctx, "v_row", "v_def")});
  end loop;
  return v_out;
end;
$$;
revoke execute on function ${fn("observation_submission_apply")}(uuid, boolean) from public, anon, authenticated;

-- Records the observations of a submitted submission, as the caller; a
-- second call records only what the first didn't.
create or replace function ${fn("observations_from_submission")}(submission_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  return ${fn("observation_submission_apply")}(observations_from_submission.submission_id, false);
end;
$$;
${userGrant(`${fn("observations_from_submission")}(uuid)`)}

create or replace function ${fn("observation_submission_trigger")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.${s("status")}::text = 'submitted' and (tg_op = 'INSERT' or old.${s("status")}::text is distinct from 'submitted') and new.${s("subjectType")} is not null then
    perform ${fn("observation_submission_apply")}(new.${s("id")}, true);
  end if;
  return null;
end;
$$;
${triggerGrant(`${fn("observation_submission_trigger")}()`)}
drop trigger if exists ${trigger} on ${submissions};
create trigger ${trigger}
after insert or update of ${s("status")} on ${submissions}
for each row execute function ${fn("observation_submission_trigger")}();
`;
}
