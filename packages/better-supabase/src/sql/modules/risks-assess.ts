import type { BlockSqlContext } from "../context.ts";
import type { RisksSql } from "./risks-sql.ts";

import { fail, pageSize, serviceGrant, userGrant } from "../shared.ts";
import { risksSql } from "./risks-sql.ts";

const outOfRange = fail(
  "RISK_LEVEL_OUT_OF_RANGE",
  "a likelihood or impact is not a level of the risk's matrix",
  "22023",
);

/** The months an assessment or a review moves the next review ahead. */
const nextReview = (q: RisksSql, row: string): string =>
  `(current_date + make_interval(months => coalesce(${row}.${q.r("reviewIntervalMonths")}, 12)))::date`;

/** Loads `v_row` for update by `func.risk_id`, refusing a closed risk. */
function load(
  q: RisksSql,
  func: string,
  permission: string,
  what: string,
): string {
  const { r, risks } = q;

  return `select * into v_row from ${risks} x where x.${r("id")} = ${func}.risk_id for update;
  if not found then
    ${q.missing}
  end if;
  if not ${q.allowed(`v_row.${r("tenant")}`, permission)} then
    ${q.forbidden(`not allowed to ${what}`)}
  end if;
  if v_row.${r("status")} = 'closed' then
    ${q.closed}
  end if;`;
}

function assessFunctions(ctx: BlockSqlContext, q: RisksSql): string {
  const { fn, m, r, a, risks, matrices, assessments, riskJson, has } = q;

  const levels = (
    likelihood: string,
    impact: string,
  ): string => `${likelihood} is null or ${impact} is null
    or ${likelihood} not between 1 and jsonb_array_length(v_matrix.${m("likelihoodLevels")})
    or ${impact} not between 1 and jsonb_array_length(v_matrix.${m("impactLevels")})`;

  const snapshot = `v_version := ${q.versions.fn("version_insert")}(v_row.${r("tenant")}, ${q.subject}, v_row.${r("id")}::text,
    jsonb_build_object('title', v_row.${r("title")}, 'category', v_row.${r("category")}, 'description', ${q.riskOf("v_row", "description")}, 'cause', ${q.riskOf("v_row", "cause")}, 'consequence', ${q.riskOf("v_row", "consequence")}, 'matrixId', v_row.${r("matrix")}, 'assessmentId', v_assessment,
      'inherent', jsonb_build_object('likelihood', assess_risk.inherent_likelihood, 'impact', assess_risk.inherent_impact, 'score', v_inherent, 'band', v_inherent_band),
      'residual', jsonb_build_object('likelihood', assess_risk.residual_likelihood, 'impact', assess_risk.residual_impact, 'score', v_residual, 'band', v_residual_band),
      'rationale', assess_risk.rationale),
    null, 'assessment', 'manual', true, auth.uid());`;

  return `
-- Scores a risk before (inherent) and after (residual) its controls on its
-- matrix, records the assessment with a frozen version of the risk, and moves
-- its next review ahead. An identified risk becomes assessed.
create or replace function ${fn("assess_risk")}(risk_id uuid, inherent_likelihood integer, inherent_impact integer, residual_likelihood integer, residual_impact integer, rationale text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${risks};
  v_matrix ${matrices};
  v_assessment uuid := gen_random_uuid();
  v_inherent integer;
  v_residual integer;
  v_inherent_band text;
  v_residual_band text;
  v_version jsonb;
begin
  ${load(q, "assess_risk", q.assess, "assess risks")}
  if length(assess_risk.rationale) > 10000 then
    ${q.invalid("a rationale is at most 10000 characters")}
  end if;
  select * into v_matrix from ${matrices} x where x.${m("id")} = v_row.${r("matrix")};
  if ${levels("assess_risk.inherent_likelihood", "assess_risk.inherent_impact")}
    or ${levels("assess_risk.residual_likelihood", "assess_risk.residual_impact")} then
    ${outOfRange}
  end if;
  v_inherent := ${q.score("v_matrix", "assess_risk.inherent_likelihood", "assess_risk.inherent_impact")};
  v_residual := ${q.score("v_matrix", "assess_risk.residual_likelihood", "assess_risk.residual_impact")};
  v_inherent_band := ${q.band("v_matrix", "v_inherent")};
  v_residual_band := ${q.band("v_matrix", "v_residual")};
  ${ctx.hook("before_risk_assess", [
    ["uuid", `v_row.${r("id")}`],
    ["integer", "v_inherent"],
    ["integer", "v_residual"],
  ])}
  ${snapshot}
  insert into ${assessments} (${a("id")}, ${a("tenant")}, ${a("risk")}, ${a("inherentLikelihood")}, ${a("inherentImpact")}, ${a("inherentScore")}, ${a("inherentBand")}, ${a("residualLikelihood")}, ${a("residualImpact")}, ${a("residualScore")}, ${a("residualBand")}${has("assessments", "rationale") ? `, ${a("rationale")}` : ""}${has("assessments", "version") ? `, ${a("version")}` : ""}, ${a("assessedBy")})
  values (v_assessment, v_row.${r("tenant")}, v_row.${r("id")}, assess_risk.inherent_likelihood, assess_risk.inherent_impact, v_inherent, v_inherent_band, assess_risk.residual_likelihood, assess_risk.residual_impact, v_residual, v_residual_band${has("assessments", "rationale") ? ", nullif(trim(assess_risk.rationale), '')" : ""}${has("assessments", "version") ? ", (v_version ->> 'id')::uuid" : ""}, auth.uid());
  update ${risks} x set
    ${r("inherentLikelihood")} = assess_risk.inherent_likelihood,
    ${r("inherentImpact")} = assess_risk.inherent_impact,
    ${r("inherentScore")} = v_inherent,
    ${r("inherentBand")} = v_inherent_band,
    ${r("residualLikelihood")} = assess_risk.residual_likelihood,
    ${r("residualImpact")} = assess_risk.residual_impact,
    ${r("residualScore")} = v_residual,
    ${r("residualBand")} = v_residual_band,
    ${r("currentAssessment")} = v_assessment,
    ${r("status")} = case when x.${r("status")} = 'identified' then 'assessed' else x.${r("status")} end,
    ${r("nextReviewOn")} = ${nextReview(q, "x")},
    ${r("reviewNotifiedFor")} = null,
    ${r("updatedAt")} = now()
  where x.${r("id")} = v_row.${r("id")}
  returning * into v_row;
  ${q.record("risk.assessed", "v_row", "risk assessed", ", 'assessmentId', v_assessment, 'inherentScore', v_inherent, 'inherentBand', v_inherent_band, 'residualScore', v_residual, 'residualBand', v_residual_band")}
  ${ctx.hook("after_risk_assess", [["uuid", `v_row.${r("id")}`]])}
  return ${riskJson("v_row")};
end;
$$;
${userGrant(`${fn("assess_risk")}(uuid, integer, integer, integer, integer, text)`)}

-- Sets how a risk is treated: mitigate and transfer make it treating, accept
-- makes it accepted (risks.manage) and avoid closes it.
create or replace function ${fn("set_risk_treatment")}(risk_id uuid, treatment text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${risks};
begin
  ${load(q, "set_risk_treatment", q.write, "write risks")}
  if coalesce(set_risk_treatment.treatment, '') not in ('mitigate', 'accept', 'transfer', 'avoid') then
    ${q.invalid("treatment is mitigate, accept, transfer or avoid")}
  end if;
  if set_risk_treatment.treatment = 'accept' and not ${q.allowed(`v_row.${r("tenant")}`, q.manage)} then
    ${q.forbidden("accepting a risk needs the manage permission")}
  end if;
  if length(set_risk_treatment.note) > 4000 then
    ${q.invalid("a note is at most 4000 characters")}
  end if;
  update ${risks} x set
    ${r("treatment")} = set_risk_treatment.treatment,
    ${r("status")} = case set_risk_treatment.treatment when 'accept' then 'accepted' when 'avoid' then 'closed' else 'treating' end,
    ${r("closedAt")} = case when set_risk_treatment.treatment = 'avoid' then now() else x.${r("closedAt")} end,
    ${r("updatedAt")} = now()
  where x.${r("id")} = v_row.${r("id")}
  returning * into v_row;
  ${q.record("risk.treatment_changed", "v_row", "risk treatment changed", ", 'treatment', set_risk_treatment.treatment, 'note', nullif(trim(set_risk_treatment.note), '')")}
  return ${riskJson("v_row")};
end;
$$;
${userGrant(`${fn("set_risk_treatment")}(uuid, text, text)`)}

-- Records that a risk was reviewed and moves its next review ahead by its
-- review interval (12 months when unset).
create or replace function ${fn("review_risk")}(risk_id uuid, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${risks};
begin
  ${load(q, "review_risk", q.assess, "review risks")}
  if length(review_risk.note) > 4000 then
    ${q.invalid("a note is at most 4000 characters")}
  end if;
  update ${risks} x set
    ${r("reviewedAt")} = now(),
    ${r("nextReviewOn")} = ${nextReview(q, "x")},
    ${r("reviewNotifiedFor")} = null,
    ${r("updatedAt")} = now()
  where x.${r("id")} = v_row.${r("id")}
  returning * into v_row;
  ${q.record("risk.reviewed", "v_row", "risk reviewed", `, 'nextReviewOn', v_row.${r("nextReviewOn")}, 'note', nullif(trim(review_risk.note), '')`)}
  return ${riskJson("v_row")};
end;
$$;
${userGrant(`${fn("review_risk")}(uuid, text)`)}

-- Closes a risk with a reason. A closed risk takes no more changes.
create or replace function ${fn("close_risk")}(risk_id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${risks};
begin
  ${load(q, "close_risk", q.manage, "close risks")}
  if coalesce(length(trim(close_risk.reason)), 0) not between 1 and 4000 then
    ${q.invalid("closing a risk needs a reason of 1 to 4000 characters")}
  end if;
  ${ctx.hook("before_risk_close", [["uuid", `v_row.${r("id")}`]])}
  update ${risks} x set
    ${r("status")} = 'closed',
    ${r("closedAt")} = now(),
    ${r("updatedAt")} = now()
  where x.${r("id")} = v_row.${r("id")}
  returning * into v_row;
  ${q.record("risk.closed", "v_row", "risk closed", ", 'reason', trim(close_risk.reason)")}
  ${ctx.hook("after_risk_close", [["uuid", `v_row.${r("id")}`]])}
  return ${riskJson("v_row")};
end;
$$;
${userGrant(`${fn("close_risk")}(uuid, text)`)}
`;
}

function reads(ctx: BlockSqlContext, q: RisksSql): string {
  const { fn, m, r, a, risks, matrices, assessments, riskJson, matrixJson } = q;

  const idType = ctx.idType;
  const rel = q.relations;

  const links = (kind: string): string => {
    if (rel === undefined) {
      return "'[]'::jsonb";
    }

    const l = (column: string): string => rel.col("relations", column);
    const title = ctx.of("subjects").fn("subject_title");

    return `coalesce((
      select jsonb_agg(jsonb_build_object('linkId', l.${l("id")}, 'type', l.${l("targetType")}, 'id', l.${l("targetId")}, 'title', ${title}(l.${l("targetType")}, l.${l("targetId")})) order by l.${l("createdAt")})
      from ${rel.table("relations")} l
      where l.${l("tenant")} = v_row.${r("tenant")} and l.${l("kind")} = '${kind}'
        and l.${l("sourceType")} = ${q.subject} and l.${l("sourceId")} = v_row.${r("id")}::text
    ), '[]'::jsonb)`;
  };

  const search = [
    `x.${r("title")} ilike v_search`,
    `x.${r("number")} ilike v_search`,
    ...(["description", "cause", "consequence"] as const)
      .filter((column) => q.has("risks", column))
      .map((column) => `x.${r(column)} ilike v_search`),
  ].join(" or ");

  return `
-- A risk with its matrix, its assessments (newest first), its barriers (the
-- mitigated_by links) and the cases it materialized as.
create or replace function ${fn("get_risk")}(risk_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${risks};
  v_matrix ${matrices};
begin
  select * into v_row from ${risks} x where x.${r("id")} = get_risk.risk_id;
  if not found or not ${q.allowed(`v_row.${r("tenant")}`, q.read)} then
    ${q.missing}
  end if;
  select * into v_matrix from ${matrices} x where x.${m("id")} = v_row.${r("matrix")};
  return ${riskJson("v_row")} || jsonb_build_object(
    'matrix', ${matrixJson("v_matrix")},
    'assessments', coalesce((
      select jsonb_agg(${q.assessmentJson("y")} order by y.${a("assessedAt")} desc)
      from ${assessments} y where y.${a("tenant")} = v_row.${r("tenant")} and y.${a("risk")} = v_row.${r("id")}
    ), '[]'::jsonb),
    'barriers', ${links("mitigated_by")},
    'cases', ${links("materialized_as")}
  );
end;
$$;
${userGrant(`${fn("get_risk")}(uuid)`)}

-- The organization's risks, the highest residual score first. filters is
-- { category, band (residual), ownerId, status, reviewDue, search, limit,
-- offset }; closed risks are left out unless status asks for them.
create or replace function ${fn("list_risks")}(tenant ${idType}, filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_risks.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\\', '\\\\'), '%', '\\%'), '_', '\\_') || '%' end;
  v_limit integer := ${pageSize("(v_filters ->> 'limit')::integer", 50, 200)};
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
begin
  if not ${q.allowed("list_risks.tenant", q.read)} then
    ${q.forbidden("not allowed to read risks")}
  end if;
  if jsonb_typeof(v_filters) <> 'object' then
    ${q.invalid("filters must be an object")}
  end if;
  return coalesce((
    select jsonb_agg(${riskJson("x")} order by x.${r("residualScore")} desc nulls last, x.${r("sequence")})
    from (
      select * from ${risks} x
      where x.${r("tenant")} = list_risks.tenant
        and x.${r("archivedAt")} is null
        and (case when v_filters ? 'status' then x.${r("status")} = v_filters ->> 'status' else x.${r("status")} <> 'closed' end)
        and (not v_filters ? 'category' or x.${r("category")} = v_filters ->> 'category')
        and (not v_filters ? 'band' or x.${r("residualBand")} = v_filters ->> 'band')
        and (not v_filters ? 'ownerId' or x.${r("owner")} = (v_filters ->> 'ownerId')::uuid)
        and (coalesce((v_filters ->> 'reviewDue')::boolean, false) is false or x.${r("nextReviewOn")} <= current_date)
        and (v_search is null or ${search})
      order by x.${r("residualScore")} desc nulls last, x.${r("sequence")}
      limit v_limit offset v_offset
    ) x
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_risks")}(${idType}, jsonb)`)}

-- A matrix (the default without matrix_id) with one cell per likelihood and
-- impact: the open risks scored there, on their residual or inherent score.
create or replace function ${fn("risk_heatmap")}(tenant ${idType}, matrix_id uuid default null, basis text default 'residual')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_matrix ${matrices};
begin
  if not ${q.allowed("risk_heatmap.tenant", q.read)} then
    ${q.forbidden("not allowed to read risks")}
  end if;
  if coalesce(risk_heatmap.basis, '') not in ('residual', 'inherent') then
    ${q.invalid("basis is residual or inherent")}
  end if;
  select * into v_matrix from ${matrices} x
  where x.${m("tenant")} = risk_heatmap.tenant
    and x.${m("id")} = coalesce(risk_heatmap.matrix_id, ${fn("ensure_risk_matrix")}(risk_heatmap.tenant));
  if not found then
    ${q.matrixMissing}
  end if;
  return jsonb_build_object(
    'matrix', ${matrixJson("v_matrix")},
    'basis', risk_heatmap.basis,
    'cells', coalesce((
      select jsonb_agg(jsonb_build_object(
        'likelihood', c.likelihood, 'impact', c.impact,
        'score', ${q.score("v_matrix", "c.likelihood", "c.impact")},
        'band', ${q.band("v_matrix", q.score("v_matrix", "c.likelihood", "c.impact"))},
        'count', coalesce(cardinality(c.ids), 0), 'riskIds', to_jsonb(coalesce(c.ids, '{}'::uuid[]))
      ) order by c.likelihood, c.impact)
      from (
        select l.l as likelihood, i.i as impact, (
          select array_agg(x.${r("id")} order by x.${r("sequence")})
          from ${risks} x
          where x.${r("tenant")} = v_matrix.${m("tenant")} and x.${r("matrix")} = v_matrix.${m("id")}
            and x.${r("status")} <> 'closed' and x.${r("archivedAt")} is null
            and case when risk_heatmap.basis = 'inherent'
              then x.${r("inherentLikelihood")} = l.l and x.${r("inherentImpact")} = i.i
              else x.${r("residualLikelihood")} = l.l and x.${r("residualImpact")} = i.i end
        ) as ids
        from generate_series(1, jsonb_array_length(v_matrix.${m("likelihoodLevels")})) l (l)
        cross join generate_series(1, jsonb_array_length(v_matrix.${m("impactLevels")})) i (i)
      ) c
    ), '[]'::jsonb)
  );
end;
$$;
${userGrant(`${fn("risk_heatmap")}(${idType}, uuid, text)`)}
`;
}

function dueReviews(ctx: BlockSqlContext, q: RisksSql): string {
  const { fn, r, risks } = q;

  const notify = ctx.installed("notifications")
    ? `if v_row.${r("owner")} is not null then
      ${ctx.notify(
        `jsonb_build_object(
        'type', 'risk.review_date_reached',
        'tenant', v_row.${r("tenant")},
        'actor', null,
        'subject_type', ${q.subject},
        'subject_id', v_row.${r("id")}::text,
        'summary', v_row.${r("number")} || ' ' || v_row.${r("title")},
        'recipients', to_jsonb(array[v_row.${r("owner")}]),
        'key', 'risk.review_date_reached:' || v_row.${r("id")}::text || ':' || v_row.${r("nextReviewOn")}::text,
        'data', jsonb_build_object('riskId', v_row.${r("id")}, 'nextReviewOn', v_row.${r("nextReviewOn")})
      )`,
        { indent: "      " },
      )}
    end if;`
    : "";

  return `
-- Reports each open risk whose review date has come once per date: a
-- risk.review_date_reached event and, with notifications, a notification to its owner.
-- Run it daily from a job (the risks.reviews block timer).
create or replace function ${fn("notify_due_risk_reviews")}()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${risks}%rowtype;
  v_claims text;
  v_count integer := 0;
begin
  for v_row in
    select * from ${risks} x
    where x.${r("status")} <> 'closed' and x.${r("archivedAt")} is null
      and x.${r("nextReviewOn")} <= current_date
      and x.${r("reviewNotifiedFor")} is distinct from x.${r("nextReviewOn")}
    for update skip locked
  loop
    ${q.record("risk.review_date_reached", "v_row", "risk review due", `, 'ownerId', v_row.${r("owner")}, 'nextReviewOn', v_row.${r("nextReviewOn")}`)}
    ${notify}
    update ${risks} x set ${r("reviewNotifiedFor")} = v_row.${r("nextReviewOn")} where x.${r("id")} = v_row.${r("id")};
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("notify_due_risk_reviews")}()`)}
`;
}

export function riskAssessFunctions(ctx: BlockSqlContext): string {
  const q = risksSql(ctx);

  return `${assessFunctions(ctx, q)}${reads(ctx, q)}${dueReviews(ctx, q)}`;
}
