import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";

import { SPEC_PINS } from "../../core/spec-pins.ts";
import { sqlString } from "../../core/template.ts";
import { fail, SERVICE_CALLER, userGrant } from "../shared.ts";
import { evidenceAttachments } from "./compliance-shared.ts";
import { moduleOperations } from "./permissions-model.ts";

export const OSCAL_CONTRACT: readonly BlockSqlContractFunction[] = [
  {
    name: "import_oscal_catalog",
    args: ["{id}", "jsonb", "text"],
    returns: "jsonb",
  },
  { name: "apply_oscal_profile", args: ["uuid", "jsonb"], returns: "jsonb" },
  {
    name: "export_oscal_assessment_results",
    args: ["uuid", "text"],
    returns: "jsonb",
  },
];

/**
 * OSCAL import and export for frameworks: a catalog becomes a framework with a
 * control per catalog control, a profile marks which of those controls apply,
 * and an assessment-results document lists each applicable control's finding
 * with the evidence behind it.
 */
export function oscalFunctions(ctx: BlockSqlContext): string {
  const frameworks = ctx.table("frameworks");
  const controls = ctx.table("controls");
  const evidence = ctx.table("evidence");
  const f = (column: string): string => ctx.col("frameworks", column);
  const k = (column: string): string => ctx.col("controls", column);
  const e = (column: string): string => ctx.col("evidence", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const permissions = moduleOperations("compliance");
  const manage = ctx.permission("manage", permissions.manage);
  const read = ctx.permission("read", permissions.read);
  const attachments = evidenceAttachments(ctx);

  const has = (table: string, column: string): boolean =>
    ctx.has(table, column);

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, permission)})`;

  const invalid = (message: string): string =>
    fail("OSCAL_INVALID", message, "22023");

  const description = has("controls", "description");
  const source = has("controls", "source");
  const touch = has("controls", "updatedAt");
  const note = has("evidence", "note");

  const frameworkCols = [
    f("tenant"),
    f("key"),
    f("name"),
    ...(has("frameworks", "kind") ? [f("kind")] : []),
    ...(has("frameworks", "version") ? [f("version")] : []),
  ].join(", ");

  const frameworkVals = [
    "v_tenant",
    "v_key",
    "v_title",
    ...(has("frameworks", "kind") ? ["'standard'"] : []),
    ...(has("frameworks", "version") ? ["v_version"] : []),
  ].join(", ");

  const frameworkSet = [
    `${f("name")} = excluded.${f("name")}`,
    ...(has("frameworks", "version")
      ? [`${f("version")} = excluded.${f("version")}`]
      : []),
    ...(has("frameworks", "updatedAt") ? [`${f("updatedAt")} = now()`] : []),
  ].join(", ");

  const controlCols = [
    k("tenant"),
    k("framework"),
    k("code"),
    k("title"),
    ...(description ? [k("description")] : []),
    ...(source ? [k("source")] : []),
  ].join(", ");

  const controlVals = [
    "v_tenant",
    "v_framework.id_value",
    "v_code",
    "v_ctl_title",
    ...(description ? ["v_prose"] : []),
    ...(source ? ["'oscal'"] : []),
  ]
    .join(", ")
    .replace("v_framework.id_value", `v_framework.${f("id")}`);

  const controlSet = [
    `${k("title")} = excluded.${k("title")}`,
    ...(description
      ? [`${k("description")} = excluded.${k("description")}`]
      : []),
    ...(touch ? [`${k("updatedAt")} = now()`] : []),
  ].join(", ");

  const importEvent = ctx.record({
    type: "control_framework.imported",
    payload: `jsonb_build_object('organizationId', v_framework.${f("tenant")}::text, 'frameworkId', v_framework.${f("id")}, 'format', 'oscal-catalog', 'controls', v_count)`,
    subject: `'controls/' || v_framework.${f("id")}::text`,
    tenant: `v_framework.${f("tenant")}`,
    audit: {
      category: "data",
      targetType: "control_framework",
      recordId: `v_framework.${f("id")}::text`,
    },
  });

  const evidenceNote = note ? `ev.${e("note")}` : "null::text";

  const evidenceHref =
    attachments === undefined
      ? "null::text"
      : `case when ev.${e("attachment")} is null then null else 'urn:uuid:' || ev.${e("attachment")}::text end`;

  return `-- Imports an OSCAL catalog (${SPEC_PINS.oscal}) as a framework and its controls. The
-- framework key defaults to the catalog uuid. Groups and nested controls
-- flatten into controls by id; the statement prose becomes the description.
-- Importing the same catalog again updates titles and descriptions only.
create or replace function ${fn("import_oscal_catalog")}(tenant ${idType}, document jsonb, key text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${idType} := import_oscal_catalog.tenant;
  v_catalog jsonb;
  v_key text;
  v_title text;
  v_version text;
  v_framework ${frameworks}%rowtype;
  v_ctl jsonb;
  v_code text;
  v_ctl_title text;
  v_prose text;
  v_count integer := 0;
begin
  if not ${allowed("v_tenant", manage)} then
    ${fail("CONTROL_FORBIDDEN", "not allowed to manage controls")}
  end if;
  if import_oscal_catalog.document is null or jsonb_typeof(import_oscal_catalog.document -> 'catalog') is distinct from 'object' then
    ${invalid("the document needs a catalog object")}
  end if;
  v_catalog := import_oscal_catalog.document -> 'catalog';
  v_title := nullif(trim(v_catalog #>> '{metadata,title}'), '');
  if v_title is null then
    ${invalid("the catalog needs a metadata title")}
  end if;
  v_version := nullif(trim(v_catalog #>> '{metadata,version}'), '');
  v_key := coalesce(nullif(trim(import_oscal_catalog.key), ''), 'oscal-' || lower(left(replace(coalesce(v_catalog ->> 'uuid', ''), '-', ''), 12)));
  if v_key !~ '^[a-z0-9][a-z0-9_.-]{0,62}$' then
    ${invalid("key must be lowercase letters, digits, dots, dashes or underscores")}
  end if;
  insert into ${frameworks} (${frameworkCols})
  values (${frameworkVals})
  on conflict (${f("tenant")}, ${f("key")}) do update set ${frameworkSet}
  returning * into v_framework;
  for v_ctl in
    select c from jsonb_path_query(v_catalog, 'strict $.**.controls[*]') c
  loop
    v_code := left(trim(v_ctl ->> 'id'), 50);
    v_ctl_title := left(trim(v_ctl ->> 'title'), 200);
    if v_code is null or v_code = '' or v_ctl_title is null or v_ctl_title = '' then
      ${invalid("every control needs an id and a title")}
    end if;
    v_prose := left(nullif(trim(jsonb_path_query_first(v_ctl, 'lax $.parts[*] ? (@.name == "statement").prose') #>> '{}'), ''), 10000);
    insert into ${controls} (${controlCols})
    values (${controlVals})
    on conflict (${k("framework")}, ${k("code")}) do update set ${controlSet};
    v_count := v_count + 1;
  end loop;
  ${importEvent}
  return jsonb_build_object('frameworkId', v_framework.${f("id")}, 'key', v_framework.${f("key")}, 'controls', v_count);
end;
$$;
${userGrant(`${fn("import_oscal_catalog")}(${idType}, jsonb, text)`)}

-- Applies an OSCAL profile to a framework: the controls it includes apply and
-- the others do not (the statement of applicability). A profile includes
-- controls with include-all or include-controls with-ids, minus
-- exclude-controls with-ids, across its imports. Its import href is not
-- followed; the profile applies to the framework you name. Returns the counts
-- and the ids the framework has no control for.
create or replace function ${fn("apply_oscal_profile")}(framework_id uuid, document jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_framework ${frameworks}%rowtype;
  v_import jsonb;
  v_all boolean := false;
  v_included text[] := '{}';
  v_excluded text[] := '{}';
  v_codes text[];
  v_applicable integer;
  v_other integer;
begin
  select * into v_framework from ${frameworks} x where x.${f("id")} = apply_oscal_profile.framework_id;
  if not found then
    ${fail("CONTROL_FRAMEWORK_NOT_FOUND", "framework not found", "P0002")}
  end if;
  if not ${allowed(`v_framework.${f("tenant")}`, manage)} then
    ${fail("CONTROL_FORBIDDEN", "not allowed to manage controls")}
  end if;
  if apply_oscal_profile.document is null or jsonb_typeof(apply_oscal_profile.document -> 'profile') is distinct from 'object' then
    ${invalid("the document needs a profile object")}
  end if;
  if jsonb_typeof(apply_oscal_profile.document #> '{profile,imports}') is distinct from 'array' then
    ${invalid("the profile needs imports")}
  end if;
  for v_import in select i from jsonb_array_elements(apply_oscal_profile.document #> '{profile,imports}') i loop
    if v_import ? 'include-all' then
      v_all := true;
    end if;
    v_included := v_included || coalesce(array(select jsonb_array_elements_text(jsonb_path_query_array(v_import, 'lax $."include-controls"[*]."with-ids"[*]'))), '{}');
    v_excluded := v_excluded || coalesce(array(select jsonb_array_elements_text(jsonb_path_query_array(v_import, 'lax $."exclude-controls"[*]."with-ids"[*]'))), '{}');
  end loop;
  if not v_all and cardinality(v_included) = 0 then
    ${invalid("the profile includes no controls")}
  end if;
  select coalesce(array_agg(c.${k("code")}), '{}') into v_codes from ${controls} c where c.${k("framework")} = v_framework.${f("id")};
  update ${controls} c set ${k("applicable")} = (v_all or c.${k("code")} = any(v_included)) and not (c.${k("code")} = any(v_excluded))${touch ? `, ${k("updatedAt")} = now()` : ""}
  where c.${k("framework")} = v_framework.${f("id")}
    and c.${k("applicable")} is distinct from ((v_all or c.${k("code")} = any(v_included)) and not (c.${k("code")} = any(v_excluded)));
  select count(*) filter (where c.${k("applicable")}), count(*) filter (where not c.${k("applicable")}) into v_applicable, v_other
  from ${controls} c where c.${k("framework")} = v_framework.${f("id")};
  return jsonb_build_object(
    'frameworkId', v_framework.${f("id")},
    'applicable', v_applicable,
    'notApplicable', v_other,
    'unknownIds', to_jsonb(array(select distinct i from unnest(v_included || v_excluded) i where not (i = any(v_codes)) order by i))
  );
end;
$$;
${userGrant(`${fn("apply_oscal_profile")}(uuid, jsonb)`)}

-- An OSCAL assessment-results document (${SPEC_PINS.oscal}) for a framework: one
-- result with an observation per piece of evidence and a finding per applicable
-- control, satisfied when the control has evidence that is still valid. The
-- import-ap href is the framework's urn, as no assessment plan exists.
create or replace function ${fn("export_oscal_assessment_results")}(framework_id uuid, title text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_framework ${frameworks}%rowtype;
  v_now text := to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
  v_title text;
begin
  select * into v_framework from ${frameworks} x where x.${f("id")} = export_oscal_assessment_results.framework_id;
  if not found then
    ${fail("CONTROL_FRAMEWORK_NOT_FOUND", "framework not found", "P0002")}
  end if;
  if not ${allowed(`v_framework.${f("tenant")}`, read)} then
    ${fail("CONTROL_FORBIDDEN", "not allowed to read controls")}
  end if;
  v_title := coalesce(nullif(trim(export_oscal_assessment_results.title), ''), v_framework.${f("name")} || ' assessment results');
  return jsonb_build_object('assessment-results', jsonb_build_object(
    'uuid', gen_random_uuid(),
    'metadata', jsonb_build_object(
      'title', v_title,
      'last-modified', v_now,
      'version', ${has("frameworks", "version") ? `coalesce(v_framework.${f("version")}, '1')` : "'1'"},
      'oscal-version', ${sqlString(SPEC_PINS.oscal)}
    ),
    'import-ap', jsonb_build_object('href', 'urn:uuid:' || v_framework.${f("id")}::text),
    'results', jsonb_build_array(jsonb_build_object(
      'uuid', gen_random_uuid(),
      'title', v_title,
      'description', 'Evidence collected for the applicable controls of ' || v_framework.${f("name")} || '.',
      'start', v_now,
      'reviewed-controls', jsonb_build_object('control-selections', jsonb_build_array(jsonb_build_object(
        'include-controls', coalesce((
          select jsonb_agg(jsonb_build_object('control-id', c.${k("code")}) order by c.${k("code")})
          from ${controls} c where c.${k("framework")} = v_framework.${f("id")} and c.${k("applicable")}
        ), '[]'::jsonb)
      ))),
      'observations', coalesce((
        select jsonb_agg(jsonb_build_object(
          'uuid', ev.${e("id")},
          'description', coalesce(${evidenceNote}, 'Evidence for control ' || c.${k("code")}),
          'methods', jsonb_build_array('EXAMINE'),
          'collected', to_char(ev.${e("collectedAt")} at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
          'relevant-evidence', jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
            'description', coalesce(${evidenceNote}, 'Attachment'),
            'href', ${evidenceHref}
          )))
        ) order by c.${k("code")}, ev.${e("collectedAt")}, ev.${e("id")})
        from ${evidence} ev
        join ${controls} c on c.${k("id")} = ev.${e("control")}
        where c.${k("framework")} = v_framework.${f("id")} and c.${k("applicable")}
      ), '[]'::jsonb),
      'findings', coalesce((
        select jsonb_agg(jsonb_build_object(
          'uuid', gen_random_uuid(),
          'title', c.${k("code")} || ' ' || c.${k("title")},
          'description', c.${k("title")},
          'target', jsonb_build_object(
            'type', 'objective-id',
            'target-id', c.${k("code")},
            'status', jsonb_build_object('state', case when exists (
              select 1 from ${evidence} ev where ev.${e("control")} = c.${k("id")} and (ev.${e("validUntil")} is null or ev.${e("validUntil")} >= current_date)
            ) then 'satisfied' else 'not-satisfied' end)
          ),
          'related-observations', coalesce((
            select jsonb_agg(jsonb_build_object('observation-uuid', ev.${e("id")}) order by ev.${e("collectedAt")}, ev.${e("id")})
            from ${evidence} ev where ev.${e("control")} = c.${k("id")}
          ), '[]'::jsonb)
        ) order by c.${k("code")})
        from ${controls} c where c.${k("framework")} = v_framework.${f("id")} and c.${k("applicable")}
      ), '[]'::jsonb)
    ))
  ));
end;
$$;
${userGrant(`${fn("export_oscal_assessment_results")}(uuid, text)`)}
`;
}
