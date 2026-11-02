import type { AppraisalsSql } from "./appraisals-sql.ts";

import { SERVICE_CALLER, userGrant } from "../shared.ts";

/**
 * Whether the caller must not learn who wrote a review. Only peer reviews are
 * anonymous, and never to their own reviewer or the service role. It also backs
 * the read policies of reviews and ratings, so a table read hides the same
 * rows. plpgsql keeps it creatable before the tables.
 */
export function reviewHiddenFunction(q: AppraisalsSql): string {
  const { fn, y, a, r, reviews, appraisals, cycles } = q;

  return `
-- Whether the caller must not learn who wrote a review: a peer review in a
-- cycle that hides peer reviewers, unless the caller wrote it. Read policies use
-- it, so it is granted to signed-in users.
create or replace function ${fn("appraisal_review_hidden")}(review_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_review ${reviews};
  v_row ${appraisals};
  v_mode text;
begin
  select * into v_review from ${reviews} x where x.${r("id")} = appraisal_review_hidden.review_id;
  if not found then
    return true;
  end if;
  if v_review.${r("kind")} <> 'peer' or v_review.${r("reviewer")} is not distinct from auth.uid() or ${SERVICE_CALLER} then
    return false;
  end if;
  select * into v_row from ${appraisals} x where x.${a("id")} = v_review.${r("appraisal")};
  select x.${y("anonymity")} into v_mode from ${cycles} x where x.${y("id")} = v_row.${a("cycle")};
  return case v_mode
    when 'none' then false
    when 'subject' then coalesce(v_row.${a("subjectUser")} = auth.uid(), false)
    else true
  end;
end;
$$;
${userGrant(`${fn("appraisal_review_hidden")}(uuid)`)}
`;
}

/** The rubric's weighted rating of an appraisal, and the rubric writer. */
export function rubricFunctions(q: AppraisalsSql): string {
  const {
    fn,
    y,
    a,
    r,
    k,
    t,
    cycles,
    appraisals,
    reviews,
    competencies,
    ratings,
  } = q;

  return `
-- The rating of an appraisal from its submitted reviews. A cycle with a rubric
-- weighs the average rating of each competency by the competency's weight;
-- overrides is { key: rating } and replaces a competency's average (a
-- calibration). A cycle without a rubric averages the review ratings. Not
-- granted to anyone.
create or replace function ${fn("appraisal_score")}(appraisal_id uuid, overrides jsonb default '{}')
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when exists (select 1 from ${competencies} w join ${appraisals} p on p.${a("cycle")} = w.${k("cycle")} where p.${a("id")} = appraisal_score.appraisal_id) then (
      select round(sum(w.${k("weight")} * coalesce((appraisal_score.overrides ->> w.${k("key")})::numeric, m.average))
          / sum(w.${k("weight")}), 2)
      from ${competencies} w
      join ${appraisals} p on p.${a("cycle")} = w.${k("cycle")}
      cross join lateral (
        select avg(z.${t("rating")}) as average
        from ${ratings} z join ${reviews} v on v.${r("id")} = z.${t("review")}
        where z.${t("competency")} = w.${k("id")} and v.${r("appraisal")} = p.${a("id")} and v.${r("submittedAt")} is not null
      ) m
      where p.${a("id")} = appraisal_score.appraisal_id
        and coalesce((appraisal_score.overrides ->> w.${k("key")})::numeric, m.average) is not null
    )
    else (
      select round(avg(v.${r("rating")}), 2) from ${reviews} v
      where v.${r("appraisal")} = appraisal_score.appraisal_id and v.${r("submittedAt")} is not null
    )
  end
$$;
revoke execute on function ${fn("appraisal_score")}(uuid, jsonb) from public, anon, authenticated;

-- Replaces the competencies of a cycle with the items of a json array
-- [{ key, name, weight }]. Not granted to anyone.
create or replace function ${fn("appraisal_write_competencies")}(cycle_id uuid, items jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_cycle ${cycles};
  v_item jsonb;
  v_position bigint;
  v_key text;
  v_name text;
  v_weight numeric;
begin
  select * into v_cycle from ${cycles} x where x.${y("id")} = appraisal_write_competencies.cycle_id;
  if appraisal_write_competencies.items is null or jsonb_typeof(appraisal_write_competencies.items) = 'null' then
    return;
  end if;
  if jsonb_typeof(appraisal_write_competencies.items) <> 'array' or jsonb_array_length(appraisal_write_competencies.items) > 20 then
    ${q.invalid("competencies is a list of at most 20 items")}
  end if;
  delete from ${competencies} x where x.${k("cycle")} = v_cycle.${y("id")};
  for v_item, v_position in
    select e, o from jsonb_array_elements(appraisal_write_competencies.items) with ordinality as t(e, o)
  loop
    begin
      v_key := trim(v_item ->> 'key');
      v_name := trim(v_item ->> 'name');
      v_weight := coalesce((v_item ->> 'weight')::numeric, 1);
    exception when invalid_text_representation or numeric_value_out_of_range then
      ${q.invalid("a competency weight is a number")}
    end;
    if v_key is null or v_key !~ '^[a-z][a-z0-9_]{0,62}$' then
      ${q.invalid("a competency key is lowercase letters, digits and underscores, starting with a letter")}
    end if;
    if coalesce(length(v_name), 0) not between 1 and 200 then
      ${q.invalid("a competency needs a name of 1 to 200 characters")}
    end if;
    if v_weight <= 0 or v_weight > 1000 then
      ${q.invalid("a competency weight is above 0 and at most 1000")}
    end if;
    begin
      insert into ${competencies} (${k("tenant")}, ${k("cycle")}, ${k("key")}, ${k("name")}, ${k("weight")}, ${k("position")})
      values (v_cycle.${y("tenant")}, v_cycle.${y("id")}, v_key, v_name, v_weight, v_position);
    exception when unique_violation then
      ${q.invalid("a competency key appears once")}
    end;
  end loop;
end;
$$;
revoke execute on function ${fn("appraisal_write_competencies")}(uuid, jsonb) from public, anon, authenticated;

-- Replaces the rubric of a draft cycle. competencies is [{ key, name, weight }]
-- with weights above 0 (default 1). The rubric stays fixed once the cycle is
-- open. Needs appraisals.manage.
create or replace function ${fn("set_appraisal_competencies")}(cycle_id uuid, competencies jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_cycle ${cycles};
begin
  select * into v_cycle from ${cycles} x where x.${y("id")} = set_appraisal_competencies.cycle_id for update;
  if not found then
    ${q.cycleMissing}
  end if;
  if not ${q.allowed(`v_cycle.${y("tenant")}`, q.manage)} then
    ${q.forbidden("not allowed to manage review cycles")}
  end if;
  if v_cycle.${y("status")} <> 'draft' then
    ${q.state("the rubric of a cycle is fixed once it is open")}
  end if;
  if set_appraisal_competencies.competencies is null or jsonb_typeof(set_appraisal_competencies.competencies) <> 'array' then
    ${q.invalid("competencies is a list")}
  end if;
  perform ${fn("appraisal_write_competencies")}(v_cycle.${y("id")}, set_appraisal_competencies.competencies);
  return ${q.cycleJson("v_cycle")};
end;
$$;
${userGrant(`${fn("set_appraisal_competencies")}(uuid, jsonb)`)}
`;
}
