import type { BlockSqlContext } from "../context.ts";
import type { AppraisalsSql } from "./appraisals-sql.ts";

import { sqlString } from "../../core/template.ts";
import { pageSize, userGrant } from "../shared.ts";
import { rubricFunctions } from "./appraisals-rubrics.ts";
import { appraisalsSql } from "./appraisals-sql.ts";
import { APPRAISAL_ANONYMITY } from "./appraisals-values.ts";
import { policyOf, policySnapshot } from "./approvals-policies.ts";
import { OPERATIONS } from "./permissions-model.ts";

/** Another block's context when it is installed with its tables. */
const managed = (
  ctx: BlockSqlContext,
  module: string,
): BlockSqlContext | undefined =>
  ctx.installed(module) && ctx.of(module).mode !== "custom"
    ? ctx.of(module)
    : undefined;

/** Whether the caller is the appraisal's subject or one of its reviewers. */
function ownership(q: AppraisalsSql, row: string): string {
  const { a, r, reviews } = q;

  return `(${row}.${a("subjectUser")} = auth.uid()
    or exists (select 1 from ${reviews} z where z.${r("appraisal")} = ${row}.${a("id")} and z.${r("reviewer")} = auth.uid()))`;
}

/** Whether the caller reads the appraisal: a reader, its subject or a reviewer. */
function visible(q: AppraisalsSql, row: string): string {
  return `coalesce(${q.allowed(`${row}.${q.a("tenant")}`, q.read)} or ${ownership(q, row)}, false)`;
}

/**
 * The step marks of an appraisal's enrollment, when the cycle follows a
 * program.
 */
function stepSql(ctx: BlockSqlContext, q: AppraisalsSql): string {
  const enrollments = managed(ctx, "enrollments");

  if (enrollments === undefined) {
    return "";
  }

  const { fn, y, a, cycles, appraisals } = q;
  const e = (column: string): string => enrollments.col("enrollments", column);

  return `
-- Marks a step of the appraisal's enrollment done when its cycle follows a
-- program that has the step. Not granted to anyone.
create or replace function ${fn("appraisal_step")}(appraisal_id uuid, step text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_enrollment uuid;
begin
  select x.${e("id")} into v_enrollment
  from ${appraisals} p join ${cycles} c on c.${y("id")} = p.${a("cycle")}
  join ${enrollments.table("enrollments")} x
    on x.${e("tenant")} is not distinct from p.${a("tenant")} and x.${e("program")} = c.${y("program")}
    and x.${e("subjectType")} = ${q.subject} and x.${e("subjectId")} = p.${a("id")}::text
  where p.${a("id")} = appraisal_step.appraisal_id and x.${e("status")} = 'active'
    and appraisal_step.step = any(x.${e("steps")});
  if v_enrollment is not null then
    perform ${enrollments.fn("enrollment_mark")}(v_enrollment, appraisal_step.step, true, auth.uid());
  end if;
end;
$$;
revoke execute on function ${fn("appraisal_step")}(uuid, text) from public, anon, authenticated;
`;
}

const mark = (
  ctx: BlockSqlContext,
  q: AppraisalsSql,
  id: string,
  step: string,
): string =>
  managed(ctx, "enrollments") === undefined
    ? ""
    : `perform ${q.fn("appraisal_step")}(${id}, '${step}');`;

function viewFunction(q: AppraisalsSql): string {
  const {
    fn,
    y,
    a,
    r,
    c,
    g,
    k,
    t,
    cycles,
    appraisals,
    reviews,
    calibrations,
    goals,
    competencies,
    ratings,
  } = q;

  // The appraised person reads the feedback once it is signed off, when the
  // cycle shares it.
  const shared = `(x.${a("subjectUser")} = auth.uid() and x.${a("status")} = 'signed_off'
      and (select z.${y("shareFeedback")} from ${cycles} z where z.${y("id")} = x.${a("cycle")}))`;

  return `
-- The appraisal as json. all_reviews false keeps only the caller's own
-- reviews, plus everyone's submitted manager and peer reviews for the appraised
-- person once a cycle that shares feedback is signed off. A peer reviewer
-- stays unset where the cycle hides peer reviewers. Not granted to anyone.
create or replace function ${fn("appraisal_json")}(appraisal_id uuid, all_reviews boolean)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', x.${a("id")}, 'organizationId', x.${a("tenant")}, 'cycleId', x.${a("cycle")},
    'subjectUserId', x.${a("subjectUser")}, 'managerId', x.${a("manager")}, 'status', x.${a("status")},
    'rating', x.${a("rating")}::text, 'calibratedRating', x.${a("calibratedRating")}, 'approvalId', x.${a("approval")},
    'signedOffAt', x.${a("signedOffAt")}, 'signedOffBy', x.${a("signedOffBy")}, 'createdAt', x.${a("createdAt")},
    'rubric', coalesce((
      select jsonb_agg(jsonb_build_object('key', w.${k("key")}, 'name', w.${k("name")}, 'weight', w.${k("weight")}) order by w.${k("position")})
      from ${competencies} w where w.${k("cycle")} = x.${a("cycle")}
    ), '[]'::jsonb),
    'competencies', case when appraisal_json.all_reviews or ${shared} then coalesce((
      select jsonb_agg(jsonb_build_object('key', w.${k("key")}, 'name', w.${k("name")}, 'weight', w.${k("weight")},
        'average', (
          select round(avg(z.${t("rating")}), 2)::text from ${ratings} z join ${reviews} v on v.${r("id")} = z.${t("review")}
          where z.${t("competency")} = w.${k("id")} and v.${r("appraisal")} = x.${a("id")} and v.${r("submittedAt")} is not null
        ),
        'calibrated', x.${a("calibratedCompetencies")} -> w.${k("key")}) order by w.${k("position")})
      from ${competencies} w where w.${k("cycle")} = x.${a("cycle")}
    ), '[]'::jsonb) else '[]'::jsonb end,
    'reviews', coalesce((
      select jsonb_agg(jsonb_build_object('id', y.${r("id")},
        'reviewerId', case when ${fn("appraisal_review_hidden")}(y.${r("id")}) then null else y.${r("reviewer")} end,
        'kind', y.${r("kind")}, 'rating', y.${r("rating")}, 'comments', y.${r("comments")}, 'submissionId', y.${r("submission")}, 'submittedAt', y.${r("submittedAt")},
        'ratings', coalesce((
          select jsonb_agg(jsonb_build_object('competency', w.${k("key")}, 'rating', z.${t("rating")}, 'comment', z.${t("comment")}) order by w.${k("position")})
          from ${ratings} z join ${competencies} w on w.${k("id")} = z.${t("competency")}
          where z.${t("review")} = y.${r("id")}
        ), '[]'::jsonb))
        order by y.${r("kind")}, y.${r("id")})
      from ${reviews} y
      where y.${r("appraisal")} = x.${a("id")}
        and (appraisal_json.all_reviews or y.${r("reviewer")} = auth.uid() or (${shared} and y.${r("submittedAt")} is not null))
    ), '[]'::jsonb),
    'calibrations', coalesce((
      select jsonb_agg(jsonb_build_object('id', z.${c("id")}, 'fromRating', z.${c("fromRating")}::text, 'toRating', z.${c("toRating")},
        'competencyRatings', z.${c("competencyRatings")},
        'reason', z.${c("reason")}, 'calibratedBy', z.${c("calibratedBy")}, 'calibratedAt', z.${c("calibratedAt")})
        order by z.${c("calibratedAt")}, z.${c("id")})
      from ${calibrations} z where z.${c("appraisal")} = x.${a("id")} and appraisal_json.all_reviews
    ), '[]'::jsonb),
    'goalIds', coalesce((
      select jsonb_agg(w.${g("goal")} order by w.${g("goal")}) from ${goals} w where w.${g("appraisal")} = x.${a("id")}
    ), '[]'::jsonb))
  from ${appraisals} x where x.${a("id")} = appraisal_json.appraisal_id
$$;
revoke execute on function ${fn("appraisal_json")}(uuid, boolean) from public, anon, authenticated;
`;
}

function cycleFunctions(ctx: BlockSqlContext, q: AppraisalsSql): string {
  const { fn, y, a, r, cycles, appraisals, reviews } = q;
  const idType = ctx.idType;
  const enrollments = managed(ctx, "enrollments");

  const programCheck =
    enrollments === undefined
      ? `if v_program is not null then
    ${q.invalid("a cycle follows a program only when the enrollments block is installed")}
  end if;`
      : `if v_program is not null and not exists (
    select 1 from ${enrollments.table("programs")} x
    where x.${enrollments.col("programs", "tenant")} = create_appraisal_cycle.tenant and x.${enrollments.col("programs", "key")} = v_program
  ) then
    ${q.invalid("no such enrollment program")}
  end if;`;

  const enroll =
    enrollments === undefined
      ? ""
      : `
      if v_cycle.${y("program")} is not null then
        select x.${enrollments.col("programs", "version")}, array(select s ->> 'id' from jsonb_array_elements(x.${enrollments.col("programs", "steps")}) s)
        into v_version, v_steps
        from ${enrollments.table("programs")} x
        where x.${enrollments.col("programs", "tenant")} = v_cycle.${y("tenant")} and x.${enrollments.col("programs", "key")} = v_cycle.${y("program")};
        perform ${enrollments.fn("enrollment_ensure")}(v_cycle.${y("tenant")}, v_cycle.${y("program")}, v_version, v_steps,
          ${q.subject}, v_appraisal.${a("id")}::text, auth.uid());
      end if;`;

  return `
-- Creates a draft review cycle. input is { name, startsOn, endsOn, program,
-- anonymity, shareFeedback, competencies }. anonymity is none, subject (default)
-- or all and says who learns which peer wrote a review; shareFeedback lets the
-- appraised person read the manager and peer reviews once signed off;
-- competencies is the rubric [{ key, name, weight }].
-- program is the key of an enrollment program whose steps may be named
-- self_review, peer_review, manager_review, calibration and sign_off; the
-- appraisals of the cycle are enrolled in it. Needs appraisals.manage.
create or replace function ${fn("create_appraisal_cycle")}(tenant ${idType}, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${cycles};
  v_name text;
  v_starts date;
  v_ends date;
  v_program text;
  v_anonymity text;
  v_share boolean;
begin
  if not ${q.allowed("create_appraisal_cycle.tenant", q.manage)} then
    ${q.forbidden("not allowed to manage review cycles")}
  end if;
  if jsonb_typeof(create_appraisal_cycle.input) is distinct from 'object' then
    ${q.invalid("input must be an object")}
  end if;
  begin
    v_name := trim(create_appraisal_cycle.input ->> 'name');
    v_starts := (create_appraisal_cycle.input ->> 'startsOn')::date;
    v_ends := (create_appraisal_cycle.input ->> 'endsOn')::date;
    v_program := nullif(trim(create_appraisal_cycle.input ->> 'program'), '');
    v_anonymity := coalesce(nullif(trim(create_appraisal_cycle.input ->> 'anonymity'), ''), 'subject');
    v_share := coalesce((create_appraisal_cycle.input ->> 'shareFeedback')::boolean, false);
  exception when invalid_datetime_format or datetime_field_overflow then
    ${q.invalid("startsOn and endsOn are dates")}
  when invalid_text_representation then
    ${q.invalid("shareFeedback is true or false")}
  end;
  if v_anonymity not in (${APPRAISAL_ANONYMITY.map((v) => `'${v}'`).join(", ")}) then
    ${q.invalid("anonymity is none, subject or all")}
  end if;
  if coalesce(length(v_name), 0) not between 1 and 200 then
    ${q.invalid("a cycle needs a name of 1 to 200 characters")}
  end if;
  if v_starts is null or v_ends is null or v_ends < v_starts then
    ${q.invalid("a cycle needs a start date and an end date on or after it")}
  end if;
  ${programCheck}
  ${ctx.hook("before_appraisal_cycle_create", [
    [idType, "create_appraisal_cycle.tenant"],
    ["jsonb", "create_appraisal_cycle.input"],
  ])}
  insert into ${cycles} (${y("tenant")}, ${y("name")}, ${y("startsOn")}, ${y("endsOn")}, ${y("program")}, ${y("anonymity")}, ${y("shareFeedback")}, ${y("createdBy")})
  values (create_appraisal_cycle.tenant, v_name, v_starts, v_ends, v_program, v_anonymity, v_share, auth.uid())
  returning * into v_row;
  perform ${fn("appraisal_write_competencies")}(v_row.${y("id")}, create_appraisal_cycle.input -> 'competencies');
  ${q.recordCycle("appraisal_cycle.created", "v_row", "review cycle created")}
  ${ctx.hook("after_appraisal_cycle_create", [["uuid", `v_row.${y("id")}`]])}
  return ${q.cycleJson("v_row")};
end;
$$;
${userGrant(`${fn("create_appraisal_cycle")}(${idType}, jsonb)`)}

-- Opens a cycle and creates the appraisals it names. assignments is
-- [{ subjectUserId, managerId, peerIds: [] }]: each person gets a self review,
-- a manager review when managerId is set and one review per peer. A person who
-- already has an appraisal in the cycle keeps it. Calling it again on an open
-- cycle adds people. Needs appraisals.manage.
create or replace function ${fn("open_appraisal_cycle")}(cycle_id uuid, assignments jsonb default '[]')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_cycle ${cycles};
  v_appraisal ${appraisals};
  v_item jsonb;
  v_subject uuid;
  v_manager uuid;
  v_peer text;
  v_peers uuid[];${
    enrollments === undefined
      ? ""
      : `
  v_version integer;
  v_steps text[];`
  }
  v_made integer := 0;
begin
  select * into v_cycle from ${cycles} x where x.${y("id")} = open_appraisal_cycle.cycle_id for update;
  if not found then
    ${q.cycleMissing}
  end if;
  if not ${q.allowed(`v_cycle.${y("tenant")}`, q.manage)} then
    ${q.forbidden("not allowed to manage review cycles")}
  end if;
  if v_cycle.${y("status")} = 'closed' then
    ${q.state("a closed cycle can't be opened again")}
  end if;
  if jsonb_typeof(open_appraisal_cycle.assignments) is distinct from 'array' then
    ${q.invalid("assignments must be a list")}
  end if;
  for v_item in select e from jsonb_array_elements(open_appraisal_cycle.assignments) e loop
    begin
      v_subject := (v_item ->> 'subjectUserId')::uuid;
      v_manager := nullif(v_item ->> 'managerId', '')::uuid;
      v_peers := '{}';
      if v_item ? 'peerIds' then
        for v_peer in select p from jsonb_array_elements_text(v_item -> 'peerIds') p loop
          v_peers := v_peers || v_peer::uuid;
        end loop;
      end if;
    exception when invalid_text_representation or invalid_parameter_value or null_value_not_allowed then
      ${q.invalid("subjectUserId, managerId and peerIds are user ids")}
    end;
    if v_subject is null then
      ${q.invalid("an assignment needs a subjectUserId")}
    end if;
    if v_manager = v_subject then
      ${q.invalid("a person can't be their own manager")}
    end if;
    if v_subject = any(v_peers) or v_manager = any(v_peers) then
      ${q.invalid("a peer is neither the person nor the manager")}
    end if;
    insert into ${appraisals} (${a("tenant")}, ${a("cycle")}, ${a("subjectUser")}, ${a("manager")})
    values (v_cycle.${y("tenant")}, v_cycle.${y("id")}, v_subject, v_manager)
    on conflict do nothing
    returning * into v_appraisal;
    if v_appraisal.${a("id")} is not null then
      v_made := v_made + 1;
      insert into ${reviews} (${r("tenant")}, ${r("appraisal")}, ${r("reviewer")}, ${r("kind")})
      values (v_appraisal.${a("tenant")}, v_appraisal.${a("id")}, v_subject, 'self');
      if v_manager is not null then
        insert into ${reviews} (${r("tenant")}, ${r("appraisal")}, ${r("reviewer")}, ${r("kind")})
        values (v_appraisal.${a("tenant")}, v_appraisal.${a("id")}, v_manager, 'manager');
      end if;
      insert into ${reviews} (${r("tenant")}, ${r("appraisal")}, ${r("reviewer")}, ${r("kind")})
      select distinct v_appraisal.${a("tenant")}, v_appraisal.${a("id")}, p, 'peer' from unnest(v_peers) p;${enroll}
      ${q.recordAppraisal("appraisal.created", "v_appraisal", "appraisal created")}
    end if;
    v_appraisal := null;
  end loop;
  update ${cycles} x set ${y("status")} = 'open', ${y("openedAt")} = coalesce(x.${y("openedAt")}, now())
  where x.${y("id")} = v_cycle.${y("id")}
  returning * into v_cycle;
  if v_made > 0 or v_cycle.${y("openedAt")} = now() then
    ${q.recordCycle("appraisal_cycle.opened", "v_cycle", "review cycle opened")}
  end if;
  return ${q.cycleJson("v_cycle")} || jsonb_build_object('appraisalsCreated', v_made);
end;
$$;
${userGrant(`${fn("open_appraisal_cycle")}(uuid, jsonb)`)}

-- Closes a cycle once every appraisal in it is signed off. Needs
-- appraisals.manage.
create or replace function ${fn("close_appraisal_cycle")}(cycle_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_cycle ${cycles};
begin
  select * into v_cycle from ${cycles} x where x.${y("id")} = close_appraisal_cycle.cycle_id for update;
  if not found then
    ${q.cycleMissing}
  end if;
  if not ${q.allowed(`v_cycle.${y("tenant")}`, q.manage)} then
    ${q.forbidden("not allowed to manage review cycles")}
  end if;
  if v_cycle.${y("status")} <> 'open' then
    ${q.state("only an open cycle closes")}
  end if;
  if exists (select 1 from ${appraisals} x where x.${a("cycle")} = v_cycle.${y("id")} and x.${a("status")} <> 'signed_off') then
    ${q.state("every appraisal in the cycle must be signed off first")}
  end if;
  update ${cycles} x set ${y("status")} = 'closed', ${y("closedAt")} = now()
  where x.${y("id")} = v_cycle.${y("id")}
  returning * into v_cycle;
  ${q.recordCycle("appraisal_cycle.closed", "v_cycle", "review cycle closed")}
  return ${q.cycleJson("v_cycle")};
end;
$$;
${userGrant(`${fn("close_appraisal_cycle")}(uuid)`)}

-- The cycles of an organization, newest first. Needs appraisals.read.
create or replace function ${fn("list_appraisal_cycles")}(tenant ${idType})
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not ${q.allowed("list_appraisal_cycles.tenant", q.read)} then
    ${q.forbidden("not allowed to read review cycles")}
  end if;
  return coalesce((
    select jsonb_agg(${q.cycleJson("x")} order by x.${y("startsOn")} desc, x.${y("id")})
    from ${cycles} x where x.${y("tenant")} = list_appraisal_cycles.tenant
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_appraisal_cycles")}(${idType})`)}
`;
}

function reviewFunctions(ctx: BlockSqlContext, q: AppraisalsSql): string {
  const {
    fn,
    y,
    a,
    r,
    c,
    g,
    cycles,
    appraisals,
    reviews,
    calibrations,
    goals,
    competencies,
    ratings,
    k,
    t,
  } = q;

  const idType = ctx.idType;

  return `
-- Submits a review the caller was assigned. input is { rating: 1 to 5,
-- comments, submissionId } where submissionId is the forms submission that
-- holds the longer answers. A cycle with a rubric takes
-- ratings: [{ competency, rating, comment }] for every competency instead of
-- rating, and the review's rating is their weighted average, rounded. A
-- submitted review stays. When the last review of an appraisal arrives, the
-- appraisal is reviewed and its rating is the average, or the weighted average
-- of the competencies. Needs appraisals.review.
create or replace function ${fn("submit_appraisal_review")}(review_id uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_review ${reviews};
  v_row ${appraisals};
  v_cycle ${cycles};
  v_rating integer;
  v_comments text;
  v_submission uuid;
  v_left integer;
  v_rubric integer;
  v_item jsonb;
  v_key text;
  v_value integer;
  v_note text;
  v_comp ${competencies};
  v_keys text[] := '{}';
  v_sum numeric := 0;
  v_weights numeric := 0;
begin
  select * into v_review from ${reviews} x where x.${r("id")} = submit_appraisal_review.review_id for update;
  if not found then
    ${q.reviewMissing}
  end if;
  select * into v_row from ${appraisals} x where x.${a("id")} = v_review.${r("appraisal")} for update;
  select * into v_cycle from ${cycles} x where x.${y("id")} = v_row.${a("cycle")};
  if not coalesce(${q.allowed(`v_review.${r("tenant")}`, q.review)} and v_review.${r("reviewer")} = auth.uid(), false) then
    ${q.forbidden("only the assigned reviewer submits this review")}
  end if;
  if v_review.${r("submittedAt")} is not null then
    ${q.state("this review is already submitted")}
  end if;
  if v_cycle.${y("status")} <> 'open' or v_row.${a("status")} <> 'pending' then
    ${q.state("reviews are open while the cycle is open and the appraisal is pending")}
  end if;
  if jsonb_typeof(submit_appraisal_review.input) is distinct from 'object' then
    ${q.invalid("input must be an object")}
  end if;
  select count(*) into v_rubric from ${competencies} x where x.${k("cycle")} = v_cycle.${y("id")};
  begin
    v_rating := (submit_appraisal_review.input ->> 'rating')::integer;
    v_comments := nullif(trim(submit_appraisal_review.input ->> 'comments'), '');
    v_submission := nullif(submit_appraisal_review.input ->> 'submissionId', '')::uuid;
  exception when invalid_text_representation or numeric_value_out_of_range then
    ${q.invalid("rating is a whole number and submissionId an id")}
  end;
  if length(v_comments) > 10000 then
    ${q.invalid("comments are at most 10000 characters")}
  end if;
  if v_rubric = 0 then
    if submit_appraisal_review.input ? 'ratings' then
      ${q.invalid("this cycle has no rubric; send a rating")}
    end if;
    if v_rating is null or v_rating not between 1 and 5 then
      ${q.invalid("the rating is a whole number from 1 to 5")}
    end if;
  else
    if submit_appraisal_review.input ? 'rating' then
      ${q.invalid("this cycle has a rubric; send a rating for each competency")}
    end if;
    if jsonb_typeof(submit_appraisal_review.input -> 'ratings') is distinct from 'array' then
      ${q.invalid("ratings is a list of { competency, rating, comment }")}
    end if;
  end if;
  update ${reviews} x
  set ${r("rating")} = coalesce(v_rating, 1), ${r("comments")} = v_comments, ${r("submission")} = v_submission, ${r("submittedAt")} = now()
  where x.${r("id")} = v_review.${r("id")}
  returning * into v_review;
  if v_rubric > 0 then
    for v_item in select e from jsonb_array_elements(submit_appraisal_review.input -> 'ratings') e loop
      begin
        v_key := v_item ->> 'competency';
        v_value := (v_item ->> 'rating')::integer;
        v_note := nullif(trim(v_item ->> 'comment'), '');
      exception when invalid_text_representation or numeric_value_out_of_range then
        ${q.invalid("a competency rating is a whole number from 1 to 5")}
      end;
      select * into v_comp from ${competencies} x where x.${k("cycle")} = v_cycle.${y("id")} and x.${k("key")} = v_key;
      if not found then
        ${q.invalid("no such competency in this cycle's rubric")}
      end if;
      if v_value is null or v_value not between 1 and 5 then
        ${q.invalid("a competency rating is a whole number from 1 to 5")}
      end if;
      if length(v_note) > 2000 then
        ${q.invalid("a competency comment is at most 2000 characters")}
      end if;
      if v_key = any(v_keys) then
        ${q.invalid("rate each competency once")}
      end if;
      v_keys := v_keys || v_key;
      v_sum := v_sum + v_comp.${k("weight")} * v_value;
      v_weights := v_weights + v_comp.${k("weight")};
      insert into ${ratings} (${t("tenant")}, ${t("review")}, ${t("competency")}, ${t("rating")}, ${t("comment")})
      values (v_review.${r("tenant")}, v_review.${r("id")}, v_comp.${k("id")}, v_value, v_note);
    end loop;
    if cardinality(v_keys) <> v_rubric then
      ${q.invalid("rate every competency of the rubric")}
    end if;
    update ${reviews} x
    set ${r("rating")} = round(v_sum / v_weights)::integer
    where x.${r("id")} = v_review.${r("id")}
    returning * into v_review;
  end if;
  ${q.recordReview("appraisal_review.submitted", "v_review", "appraisal review submitted")}
  ${
    managed(ctx, "enrollments") === undefined
      ? ""
      : `perform ${fn("appraisal_step")}(v_row.${a("id")}, case v_review.${r("kind")} when 'self' then 'self_review' when 'manager' then 'manager_review' end);`
  }
  select count(*) into v_left from ${reviews} x
  where x.${r("appraisal")} = v_row.${a("id")} and x.${r("submittedAt")} is null;
  update ${appraisals} x
  set ${a("rating")} = ${fn("appraisal_score")}(x.${a("id")}, '{}'::jsonb),
    ${a("status")} = case when v_left = 0 then 'reviewed' else x.${a("status")} end,
    ${a("updatedAt")} = now()
  where x.${a("id")} = v_row.${a("id")}
  returning * into v_row;${
    managed(ctx, "enrollments") === undefined
      ? ""
      : `
  if v_review.${r("kind")} = 'peer' and not exists (
    select 1 from ${reviews} z where z.${r("appraisal")} = v_row.${a("id")} and z.${r("kind")} = 'peer' and z.${r("submittedAt")} is null
  ) then
    perform ${fn("appraisal_step")}(v_row.${a("id")}, 'peer_review');
  end if;`
  }
  return ${fn("appraisal_json")}(v_row.${a("id")}, ${q.allowed(`v_row.${a("tenant")}`, q.read)});
end;
$$;
${userGrant(`${fn("submit_appraisal_review")}(uuid, jsonb)`)}

-- Moves the rating of a reviewed appraisal in a calibration session and keeps
-- the reason and the previous value. Needs appraisals.manage and an open
-- cycle.
create or replace function ${fn("calibrate_appraisal")}(appraisal_id uuid, rating integer, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${appraisals};
  v_cycle ${cycles};
  v_reason text := nullif(trim(calibrate_appraisal.reason), '');
begin
  select * into v_row from ${appraisals} x where x.${a("id")} = calibrate_appraisal.appraisal_id for update;
  if not found then
    ${q.appraisalMissing}
  end if;
  if not ${q.allowed(`v_row.${a("tenant")}`, q.manage)} then
    ${q.forbidden("not allowed to calibrate appraisals")}
  end if;
  select * into v_cycle from ${cycles} x where x.${y("id")} = v_row.${a("cycle")};
  if v_cycle.${y("status")} <> 'open' or v_row.${a("status")} not in ('reviewed', 'calibrated') then
    ${q.state("only a reviewed appraisal in an open cycle is calibrated")}
  end if;
  if calibrate_appraisal.rating is null or calibrate_appraisal.rating not between 1 and 5 then
    ${q.invalid("the rating is a whole number from 1 to 5")}
  end if;
  if v_reason is null or length(v_reason) > 2000 then
    ${q.invalid("a calibration needs a reason of up to 2000 characters")}
  end if;
  insert into ${calibrations} (${c("tenant")}, ${c("appraisal")}, ${c("fromRating")}, ${c("toRating")}, ${c("reason")}, ${c("calibratedBy")})
  values (v_row.${a("tenant")}, v_row.${a("id")}, coalesce(v_row.${a("calibratedRating")}::numeric, v_row.${a("rating")}), calibrate_appraisal.rating, v_reason, auth.uid());
  update ${appraisals} x
  set ${a("calibratedRating")} = calibrate_appraisal.rating, ${a("status")} = 'calibrated', ${a("updatedAt")} = now()
  where x.${a("id")} = v_row.${a("id")}
  returning * into v_row;
  ${q.recordAppraisal("appraisal.calibrated", "v_row", "appraisal calibrated", `, 'rating', v_row.${a("calibratedRating")}`)}
  ${mark(ctx, q, `v_row.${a("id")}`, "calibration")}
  return ${fn("appraisal_json")}(v_row.${a("id")}, true);
end;
$$;
${userGrant(`${fn("calibrate_appraisal")}(uuid, integer, text)`)}

-- Moves the competency ratings of a reviewed appraisal in a calibration
-- session. competencies is { key: 1 to 5 } for the competencies that move; the
-- rest keep their review average. The calibrated rating becomes the weighted
-- rating of the result, and the reason and previous value stay. Needs
-- appraisals.manage, an open cycle and a cycle with a rubric.
create or replace function ${fn("calibrate_appraisal_competencies")}(appraisal_id uuid, competencies jsonb, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${appraisals};
  v_cycle ${cycles};
  v_reason text := nullif(trim(calibrate_appraisal_competencies.reason), '');
  v_item record;
  v_merged jsonb;
  v_rating numeric;
begin
  select * into v_row from ${appraisals} x where x.${a("id")} = calibrate_appraisal_competencies.appraisal_id for update;
  if not found then
    ${q.appraisalMissing}
  end if;
  if not ${q.allowed(`v_row.${a("tenant")}`, q.manage)} then
    ${q.forbidden("not allowed to calibrate appraisals")}
  end if;
  select * into v_cycle from ${cycles} x where x.${y("id")} = v_row.${a("cycle")};
  if v_cycle.${y("status")} <> 'open' or v_row.${a("status")} not in ('reviewed', 'calibrated') then
    ${q.state("only a reviewed appraisal in an open cycle is calibrated")}
  end if;
  if jsonb_typeof(calibrate_appraisal_competencies.competencies) is distinct from 'object'
    or calibrate_appraisal_competencies.competencies = '{}'::jsonb then
    ${q.invalid("competencies is an object of competency ratings")}
  end if;
  if v_reason is null or length(v_reason) > 2000 then
    ${q.invalid("a calibration needs a reason of up to 2000 characters")}
  end if;
  for v_item in select e.key, e.value from jsonb_each(calibrate_appraisal_competencies.competencies) e loop
    if not exists (select 1 from ${competencies} w where w.${k("cycle")} = v_cycle.${y("id")} and w.${k("key")} = v_item.key) then
      ${q.invalid("no such competency in this cycle's rubric")}
    end if;
    if jsonb_typeof(v_item.value) <> 'number' or v_item.value::text !~ '^[1-5]$' then
      ${q.invalid("a competency rating is a whole number from 1 to 5")}
    end if;
  end loop;
  v_merged := v_row.${a("calibratedCompetencies")} || calibrate_appraisal_competencies.competencies;
  v_rating := ${fn("appraisal_score")}(v_row.${a("id")}, v_merged);
  insert into ${calibrations} (${c("tenant")}, ${c("appraisal")}, ${c("fromRating")}, ${c("toRating")}, ${c("competencyRatings")}, ${c("reason")}, ${c("calibratedBy")})
  values (v_row.${a("tenant")}, v_row.${a("id")}, coalesce(v_row.${a("calibratedRating")}::numeric, v_row.${a("rating")}), round(v_rating)::integer,
    calibrate_appraisal_competencies.competencies, v_reason, auth.uid());
  update ${appraisals} x
  set ${a("calibratedCompetencies")} = v_merged, ${a("calibratedRating")} = round(v_rating)::integer,
    ${a("status")} = 'calibrated', ${a("updatedAt")} = now()
  where x.${a("id")} = v_row.${a("id")}
  returning * into v_row;
  ${q.recordAppraisal("appraisal.calibrated", "v_row", "appraisal calibrated", `, 'rating', v_row.${a("calibratedRating")}`)}
  ${mark(ctx, q, `v_row.${a("id")}`, "calibration")}
  return ${fn("appraisal_json")}(v_row.${a("id")}, true);
end;
$$;
${userGrant(`${fn("calibrate_appraisal_competencies")}(uuid, jsonb, text)`)}

-- Replaces the goals an appraisal looks back on with goal ids from the goals
-- block (or your own table). Needs appraisals.manage.
create or replace function ${fn("set_appraisal_goals")}(appraisal_id uuid, goal_ids uuid[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${appraisals};
begin
  select * into v_row from ${appraisals} x where x.${a("id")} = set_appraisal_goals.appraisal_id for update;
  if not found then
    ${q.appraisalMissing}
  end if;
  if not ${q.allowed(`v_row.${a("tenant")}`, q.manage)} then
    ${q.forbidden("not allowed to manage appraisals")}
  end if;
  if v_row.${a("status")} = 'signed_off' then
    ${q.state("a signed-off appraisal doesn't change")}
  end if;
  delete from ${goals} x where x.${g("appraisal")} = v_row.${a("id")};
  insert into ${goals} (${g("tenant")}, ${g("appraisal")}, ${g("goal")})
  select v_row.${a("tenant")}, v_row.${a("id")}, distinct_goal
  from (select distinct unnest(coalesce(set_appraisal_goals.goal_ids, '{}')) as distinct_goal) z
  where distinct_goal is not null;
  return ${fn("appraisal_json")}(v_row.${a("id")}, true);
end;
$$;
${userGrant(`${fn("set_appraisal_goals")}(uuid, uuid[])`)}

-- One appraisal with its reviews, calibrations and goals. Its subject, its
-- reviewers and readers of appraisals see it; only readers see everyone's
-- reviews and the calibrations.
create or replace function ${fn("get_appraisal")}(appraisal_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${appraisals};
begin
  select * into v_row from ${appraisals} x where x.${a("id")} = get_appraisal.appraisal_id;
  if not found or not ${visible(q, "v_row")} then
    ${q.appraisalMissing}
  end if;
  return ${fn("appraisal_json")}(v_row.${a("id")}, ${q.allowed(`v_row.${a("tenant")}`, q.read)});
end;
$$;
${userGrant(`${fn("get_appraisal")}(uuid)`)}

-- Appraisals of an organization. filters is { cycleId, status, subjectUserId,
-- mine: true, limit, offset }. Readers see all of them; everyone else sees
-- the ones they are the subject or a reviewer of.
create or replace function ${fn("list_appraisals")}(tenant ${idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_appraisals.filters, '{}'::jsonb);
  v_limit integer := ${pageSize("(v_filters ->> 'limit')::integer", 50, 200)};
  v_all boolean := ${q.allowed("list_appraisals.tenant", q.read)};
begin
  return coalesce((
    select jsonb_agg(${fn("appraisal_json")}(y.id, v_all) order by y.created_at desc, y.id)
    from (
      select x.${a("id")} as id, x.${a("createdAt")} as created_at
      from ${appraisals} x
      where x.${a("tenant")} = list_appraisals.tenant
        and (not v_filters ? 'cycleId' or x.${a("cycle")} = (v_filters ->> 'cycleId')::uuid)
        and (not v_filters ? 'status' or x.${a("status")} = v_filters ->> 'status')
        and (not v_filters ? 'subjectUserId' or x.${a("subjectUser")} = (v_filters ->> 'subjectUserId')::uuid)
        and ((v_all and (v_filters ->> 'mine') is distinct from 'true') or ${ownership(q, "x")})
      order by x.${a("createdAt")} desc, x.${a("id")}
      limit v_limit offset coalesce((v_filters ->> 'offset')::integer, 0)
    ) y
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_appraisals")}(${idType}, jsonb)`)}
`;
}

function signOffFunctions(ctx: BlockSqlContext, q: AppraisalsSql): string {
  const { fn, a, y, appraisals, cycles } = q;
  const approvals = managed(ctx, "approvals");

  const finish = `
  update ${appraisals} x
  set ${a("status")} = 'signed_off', ${a("signedOffAt")} = now(), ${a("signedOffBy")} = auth.uid(), ${a("updatedAt")} = now()
  where x.${a("id")} = v_row.${a("id")}
  returning * into v_row;
  ${q.recordAppraisal("appraisal.finalized", "v_row", "appraisal signed off", `, 'rating', coalesce(v_row.${a("calibratedRating")}::numeric, v_row.${a("rating")})`)}
  ${mark(ctx, q, `v_row.${a("id")}`, "sign_off")}`;

  const approvedHandlers =
    approvals === undefined
      ? ""
      : `
-- Signs an appraisal off once its approval is final. Approvals calls it; it
-- isn't granted to anyone.
create or replace function ${fn("appraisal_approved")}(appraisal_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${appraisals};
begin
  select * into v_row from ${appraisals} x
  where x.${a("id")} = appraisal_approved.appraisal_id and x.${a("status")} = 'awaiting_signoff' for update;
  if not found then
    return;
  end if;${finish}
end;
$$;
revoke execute on function ${fn("appraisal_approved")}(uuid) from public, anon, authenticated;

-- Sends an appraisal back to where it was when its sign-off is rejected.
-- Approvals calls it; it isn't granted to anyone.
create or replace function ${fn("appraisal_rejected")}(appraisal_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update ${appraisals} x
  set ${a("status")} = case when x.${a("calibratedRating")} is null then 'reviewed' else 'calibrated' end,
    ${a("approval")} = null, ${a("updatedAt")} = now()
  where x.${a("id")} = appraisal_rejected.appraisal_id and x.${a("status")} = 'awaiting_signoff'
$$;
revoke execute on function ${fn("appraisal_rejected")}(uuid) from public, anon, authenticated;
`;

  const request =
    approvals === undefined
      ? finish
      : `
  v_payload := jsonb_build_object('appraisalId', v_row.${a("id")}, 'cycleId', v_row.${a("cycle")}, 'subjectUserId', v_row.${a("subjectUser")},
    'rating', coalesce(v_row.${a("calibratedRating")}::numeric, v_row.${a("rating")})::text,
    'competencies', ${fn("appraisal_json")}(v_row.${a("id")}, true) -> 'competencies');
  v_approval := ${approvals.fn("open_approval")}(
    v_row.${a("tenant")}, ${q.subject}, v_row.${a("id")}::text, 'sign_off',
    coalesce(${approvals.fn("approval_effective_policy")}(v_row.${a("tenant")}, ${q.subject}, 'sign_off', v_payload), ${sqlString(defaultPolicy(ctx))}::jsonb),
    null, v_payload
  );
  update ${appraisals} x
  set ${a("status")} = 'awaiting_signoff', ${a("approval")} = (v_approval ->> 'id')::uuid, ${a("updatedAt")} = now()
  where x.${a("id")} = v_row.${a("id")}
  returning * into v_row;`;

  return `${approvedHandlers}
-- Signs an appraisal off. With the approvals block it files the sign-off as a
-- request under the organization's policy for appraisal sign_off (default: a
-- holder of appraisals.manage) and the appraisal waits as awaiting_signoff
-- until it is approved. Without approvals, a holder of appraisals.manage
-- signs it off directly. Needs a reviewed or calibrated appraisal in an open
-- cycle.
create or replace function ${fn("sign_off_appraisal")}(appraisal_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${appraisals};
  v_cycle ${cycles};${
    approvals === undefined
      ? ""
      : `
  v_payload jsonb;
  v_approval jsonb;`
  }
begin
  select * into v_row from ${appraisals} x where x.${a("id")} = sign_off_appraisal.appraisal_id for update;
  if not found then
    ${q.appraisalMissing}
  end if;
  if not ${q.allowed(`v_row.${a("tenant")}`, q.manage)} then
    ${q.forbidden("not allowed to sign off appraisals")}
  end if;
  select * into v_cycle from ${cycles} x where x.${y("id")} = v_row.${a("cycle")};
  if v_cycle.${y("status")} <> 'open' or v_row.${a("status")} not in ('reviewed', 'calibrated') then
    ${q.state("only a reviewed or calibrated appraisal in an open cycle is signed off")}
  end if;${request}
  return ${fn("appraisal_json")}(v_row.${a("id")}, true);
end;
$$;
${userGrant(`${fn("sign_off_appraisal")}(uuid)`)}
`;
}

/** The policy a sign-off snapshots when no policy covers it: a holder of manage. */
function defaultPolicy(ctx: BlockSqlContext): string {
  return policySnapshot(
    policyOf(
      ctx.naming.rename("appraisal"),
      "sign_off",
      {
        steps: [
          {
            approvers: {
              permission: ctx.permissionKey(
                "manage",
                OPERATIONS["appraisals.manage"],
              ),
            },
          },
        ],
      },
      "blocks.appraisals",
    ),
  );
}

export function appraisalsFunctions(ctx: BlockSqlContext): string {
  const q = appraisalsSql(ctx);

  return `${stepSql(ctx, q)}${rubricFunctions(q)}${viewFunction(q)}${cycleFunctions(ctx, q)}${reviewFunctions(ctx, q)}${signOffFunctions(ctx, q)}`;
}
