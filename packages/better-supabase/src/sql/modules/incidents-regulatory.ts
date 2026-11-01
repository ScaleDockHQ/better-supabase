import type { BlockSqlContext } from "../context.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  fail,
  lockTable,
  SERVICE_CALLER,
  serviceGrant,
  userGrant,
} from "../shared.ts";
import { moduleOperations } from "./permissions-model.ts";

/** The regimes of the regulatory reporting profile. */
const REGULATORY_REGIMES = ["nis2", "dora", "cra"] as const;

/** The filing stages each regime names. */
const REGULATORY_STAGES = [
  "early_warning",
  "notification",
  "initial",
  "intermediate",
  "final",
] as const;

const regimeList = REGULATORY_REGIMES.map((regime) => sqlString(regime)).join(
  ", ",
);

const stageList = REGULATORY_STAGES.map((stage) => sqlString(stage)).join(", ");

/**
 * The reminders block, when it keeps a one-off time on its reminders: each
 * deadline is then a reminder for the incident's commander.
 */
function remindersOf(
  ctx: BlockSqlContext,
):
  | { readonly table: string; readonly col: (column: string) => string }
  | undefined {
  if (!ctx.installed("reminders")) {
    return undefined;
  }

  const reminders = ctx.of("reminders");

  if (
    !reminders.hasTable("reminders") ||
    !reminders.has("reminders", "remindAt")
  ) {
    return undefined;
  }

  return {
    table: reminders.table("reminders"),
    col: (column) => reminders.col("reminders", column),
  };
}

/** The regulatory profile and filing tables. */
export function incidentsRegulatoryTables(ctx: BlockSqlContext): string {
  if (!ctx.manages) {
    return "";
  }

  const incidents = ctx.table("incidents");
  const profiles = ctx.table("profiles");
  const filings = ctx.table("filings");
  const i = (column: string): string => ctx.col("incidents", column);
  const p = (column: string): string => ctx.col("profiles", column);
  const f = (column: string): string => ctx.col("filings", column);

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  // An app's own table may lack the unique keys the upserts below target.
  const appKey = (logical: string, what: string, columns: string): string =>
    ctx.owns(logical)
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName(logical).name}_${what}_key`)} on ${ctx.table(logical)} (${columns});`;

  const readPolicy = (logical: string): string => {
    const table = ctx.table(logical);

    return `${lockTable(table, { read: true })}
drop policy if exists ${name(logical, "read")} on ${table};
${renderPolicy(makePolicy({ table, name: name(logical, "read"), command: "select", roles: ["authenticated"], using: ctx.scope.check(ctx.col(logical, "tenant"), ctx.permission("read", moduleOperations("incidents").read)) }), { target: table })}`;
  };

  return `
-- The regulatory reporting profile of an incident: which regimes apply, when
-- the organization became aware, and the facts that move a deadline.
create table if not exists ${profiles} (
  ${p("incident")} uuid primary key references ${incidents} (${i("id")}) on delete cascade,
  ${p("tenant")} ${ctx.idType} not null,
  ${p("regimes")} text[] not null default '{}' check (${p("regimes")} <@ array[${regimeList}]),
  ${p("awareAt")} timestamptz not null,
  ${p("classification")} text check (${p("classification")} is null or ${p("classification")} in ('major', 'non_major')),
  ${p("classifiedAt")} timestamptz,
  ${p("significant")} boolean not null default false,
  ${p("activelyExploited")} boolean not null default false,
  ${p("measureAvailableAt")} timestamptz,
  ${p("createdAt")} timestamptz not null default now(),
  ${p("updatedAt")} timestamptz not null default now()
);
create index if not exists ${name("profiles", "tenant_idx")} on ${profiles} (${p("tenant")});${appKey("profiles", "one", p("incident"))}
${readPolicy("profiles")}

-- One row per deadline. A submission fills submitted_at and the reference the
-- authority gave; reminder_id is the reminder that warns the commander.
create table if not exists ${filings} (
  ${f("id")} uuid primary key default gen_random_uuid(),
  ${f("tenant")} ${ctx.idType} not null,
  ${f("incident")} uuid not null references ${incidents} (${i("id")}) on delete cascade,
  ${f("regime")} text not null check (${f("regime")} in (${regimeList})),
  ${f("stage")} text not null check (${f("stage")} in (${stageList})),
  ${f("dueAt")} timestamptz,
  ${f("reminder")} uuid,
  ${f("submittedAt")} timestamptz,
  ${f("submittedBy")} uuid,
  ${f("reference")} text check (${f("reference")} is null or length(${f("reference")}) <= 200),
  ${f("notes")} text check (${f("notes")} is null or length(${f("notes")}) <= 5000),
  ${f("createdAt")} timestamptz not null default now(),
  unique (${f("incident")}, ${f("regime")}, ${f("stage")})
);
create index if not exists ${name("filings", "tenant_idx")} on ${filings} (${f("tenant")}, ${f("dueAt")}) where ${f("submittedAt")} is null;${appKey("filings", "slot", `${f("incident")}, ${f("regime")}, ${f("stage")}`)}
${readPolicy("filings")}
`;
}

/** The regulatory profile functions. */
export function incidentsRegulatoryFunctions(ctx: BlockSqlContext): string {
  const incidents = ctx.table("incidents");
  const profiles = ctx.table("profiles");
  const filings = ctx.table("filings");
  const i = (column: string): string => ctx.col("incidents", column);
  const p = (column: string): string => ctx.col("profiles", column);
  const f = (column: string): string => ctx.col("filings", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const permissions = moduleOperations("incidents");
  const read = ctx.permission("read", permissions.read);
  const write = ctx.permission("write", permissions.write);
  const reminders = remindersOf(ctx);
  const incidentType = sqlString(ctx.resolved.entityNaming.rename("incident"));

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, permission)})`;

  const forbidden = (message: string): string =>
    fail("INCIDENTS_FORBIDDEN", message);

  const invalid = (message: string): string =>
    fail("INCIDENTS_INVALID", message, "22023");

  const missing = (code: string, message: string): string =>
    fail(code, message, "P0002");

  const profileJson = (row: string): string =>
    `jsonb_build_object('incidentId', ${row}.${p("incident")}, 'organizationId', ${row}.${p("tenant")}, 'regimes', to_jsonb(${row}.${p("regimes")}), 'awareAt', ${row}.${p("awareAt")}, 'classification', ${row}.${p("classification")}, 'classifiedAt', ${row}.${p("classifiedAt")}, 'significant', ${row}.${p("significant")}, 'activelyExploited', ${row}.${p("activelyExploited")}, 'measureAvailableAt', ${row}.${p("measureAvailableAt")}, 'createdAt', ${row}.${p("createdAt")}, 'updatedAt', ${row}.${p("updatedAt")})`;

  const filingJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${f("id")}, 'organizationId', ${row}.${f("tenant")}, 'incidentId', ${row}.${f("incident")}, 'regime', ${row}.${f("regime")}, 'stage', ${row}.${f("stage")}, 'dueAt', ${row}.${f("dueAt")}, 'submittedAt', ${row}.${f("submittedAt")}, 'submittedBy', ${row}.${f("submittedBy")}, 'reference', ${row}.${f("reference")}, 'notes', ${row}.${f("notes")}, 'createdAt', ${row}.${f("createdAt")})`;

  const withFilings = (profile: string, incident: string): string =>
    `${profileJson(profile)} || jsonb_build_object('filings', coalesce((select jsonb_agg(${filingJson("y")} order by y.${f("dueAt")} nulls last, y.${f("regime")}, y.${f("stage")}) from ${filings} y where y.${f("incident")} = ${incident}), '[]'::jsonb))`;

  const commander = ctx.has("incidents", "commander")
    ? `v_inc.${i("commander")}`
    : "null::uuid";

  const creator = ctx.has("incidents", "createdBy")
    ? `v_inc.${i("createdBy")}`
    : "null::uuid";

  // One reminder per open deadline, for the commander. A deadline that has
  // passed, or has no date yet, gets none.
  const remind =
    reminders === undefined
      ? ""
      : `
  for v_filing in
    select * from ${filings} x where x.${f("incident")} = plan_incident_filings.incident_id and x.${f("submittedAt")} is null
  loop
    v_at := case
      when v_filing.${f("dueAt")} is null then null
      when v_filing.${f("dueAt")} - interval '2 hours' > now() then v_filing.${f("dueAt")} - interval '2 hours'
      when v_filing.${f("dueAt")} > now() then v_filing.${f("dueAt")}
    end;
    if v_at is null then
      if v_filing.${f("reminder")} is not null then
        delete from ${reminders.table} r where r.${reminders.col("id")} = v_filing.${f("reminder")};
        update ${filings} x set ${f("reminder")} = null where x.${f("id")} = v_filing.${f("id")};
      end if;
    elsif v_filing.${f("reminder")} is not null then
      update ${reminders.table} r set ${reminders.col("remindAt")} = v_at where r.${reminders.col("id")} = v_filing.${f("reminder")};
    elsif v_user is not null then
      insert into ${reminders.table} (${reminders.col("tenant")}, ${reminders.col("subjectType")}, ${reminders.col("subjectId")}, ${reminders.col("user")}, ${reminders.col("offsetMinutes")}, ${reminders.col("remindAt")})
      values (v_inc.${i("tenant")}, ${incidentType}, v_inc.${i("id")}::text, v_user, 0, v_at)
      returning ${reminders.col("id")} into v_reminder;
      update ${filings} x set ${f("reminder")} = v_reminder where x.${f("id")} = v_filing.${f("id")};
    end if;
  end loop;`;

  const dropReminder =
    reminders === undefined
      ? ""
      : `
  if v_row.${f("reminder")} is not null then
    delete from ${reminders.table} r where r.${reminders.col("id")} = v_row.${f("reminder")};
    update ${filings} x set ${f("reminder")} = null where x.${f("id")} = v_row.${f("id")};
  end if;`;

  const dropped =
    reminders === undefined
      ? ""
      : `
  delete from ${reminders.table} r
  where r.${reminders.col("id")} in (
    select x.${f("reminder")} from ${filings} x
    where x.${f("incident")} = plan_incident_filings.incident_id and x.${f("submittedAt")} is null and x.${f("reminder")} is not null
      and not (x.${f("regime")} || ':' || x.${f("stage")} = any(v_keys))
  );`;

  return `-- Plans the filings of an incident from its profile: the NIS2 early warning
-- (24 hours), notification (72 hours) and final report (one month after the
-- notification); the DORA initial notification (24 hours from awareness, or
-- 4 hours from classifying the incident as major), intermediate report (72
-- hours after the initial one) and final report (one month after the
-- intermediate one); and the CRA early warning (24 hours), notification (72
-- hours) and final report (14 days after a corrective measure is available).
-- Submitted filings keep their dates.
create or replace function ${fn("plan_incident_filings")}(incident_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_inc ${incidents};
  v_p ${profiles};
  v_filing ${filings};
  v_plan jsonb := '[]'::jsonb;
  v_keys text[];
  v_due timestamptz;
  v_initial_due timestamptz;
  v_initial_sub timestamptz;
  v_inter_due timestamptz;
  v_inter_sub timestamptz;
  v_notice_sub timestamptz;
  v_el jsonb;
  v_user uuid;
  v_at timestamptz;
  v_reminder uuid;
begin
  select * into v_inc from ${incidents} x where x.${i("id")} = plan_incident_filings.incident_id;
  select * into v_p from ${profiles} x where x.${p("incident")} = plan_incident_filings.incident_id;
  if v_p.${p("incident")} is null then
    return;
  end if;
  v_user := coalesce(${commander}, ${creator}, auth.uid());
  if 'nis2' = any(v_p.${p("regimes")}) then
    select x.${f("submittedAt")} into v_notice_sub from ${filings} x
    where x.${f("incident")} = v_inc.${i("id")} and x.${f("regime")} = 'nis2' and x.${f("stage")} = 'notification';
    v_plan := v_plan
      || jsonb_build_array(jsonb_build_object('regime', 'nis2', 'stage', 'early_warning', 'due', v_p.${p("awareAt")} + interval '24 hours'))
      || jsonb_build_array(jsonb_build_object('regime', 'nis2', 'stage', 'notification', 'due', v_p.${p("awareAt")} + interval '72 hours'))
      || jsonb_build_array(jsonb_build_object('regime', 'nis2', 'stage', 'final', 'due', coalesce(v_notice_sub, v_p.${p("awareAt")} + interval '72 hours') + interval '1 month'));
  end if;
  if 'dora' = any(v_p.${p("regimes")}) then
    v_initial_due := v_p.${p("awareAt")} + interval '24 hours';
    if v_p.${p("classification")} = 'major' and v_p.${p("classifiedAt")} is not null then
      v_initial_due := least(v_initial_due, v_p.${p("classifiedAt")} + interval '4 hours');
    end if;
    select x.${f("submittedAt")} into v_initial_sub from ${filings} x
    where x.${f("incident")} = v_inc.${i("id")} and x.${f("regime")} = 'dora' and x.${f("stage")} = 'initial';
    v_inter_due := coalesce(v_initial_sub, v_initial_due) + interval '72 hours';
    select x.${f("submittedAt")} into v_inter_sub from ${filings} x
    where x.${f("incident")} = v_inc.${i("id")} and x.${f("regime")} = 'dora' and x.${f("stage")} = 'intermediate';
    v_plan := v_plan
      || jsonb_build_array(jsonb_build_object('regime', 'dora', 'stage', 'initial', 'due', v_initial_due))
      || jsonb_build_array(jsonb_build_object('regime', 'dora', 'stage', 'intermediate', 'due', v_inter_due))
      || jsonb_build_array(jsonb_build_object('regime', 'dora', 'stage', 'final', 'due', coalesce(v_inter_sub, v_inter_due) + interval '1 month'));
  end if;
  if 'cra' = any(v_p.${p("regimes")}) then
    v_plan := v_plan
      || jsonb_build_array(jsonb_build_object('regime', 'cra', 'stage', 'early_warning', 'due', v_p.${p("awareAt")} + interval '24 hours'))
      || jsonb_build_array(jsonb_build_object('regime', 'cra', 'stage', 'notification', 'due', v_p.${p("awareAt")} + interval '72 hours'));
    if v_p.${p("measureAvailableAt")} is not null then
      v_plan := v_plan || jsonb_build_array(jsonb_build_object('regime', 'cra', 'stage', 'final', 'due', v_p.${p("measureAvailableAt")} + interval '14 days'));
    end if;
  end if;
  select coalesce(array_agg(e ->> 'regime' || ':' || (e ->> 'stage')), '{}') into v_keys from jsonb_array_elements(v_plan) e;${dropped}
  delete from ${filings} x
  where x.${f("incident")} = v_inc.${i("id")} and x.${f("submittedAt")} is null
    and not (x.${f("regime")} || ':' || x.${f("stage")} = any(v_keys));
  for v_el in select e from jsonb_array_elements(v_plan) e loop
    v_due := (v_el ->> 'due')::timestamptz;
    insert into ${filings} as fl (${f("tenant")}, ${f("incident")}, ${f("regime")}, ${f("stage")}, ${f("dueAt")})
    values (v_inc.${i("tenant")}, v_inc.${i("id")}, v_el ->> 'regime', v_el ->> 'stage', v_due)
    on conflict (${f("incident")}, ${f("regime")}, ${f("stage")}) do update set ${f("dueAt")} = excluded.${f("dueAt")}
    where fl.${f("submittedAt")} is null;
  end loop;${remind}
end;
$$;
${serviceGrant(`${fn("plan_incident_filings")}(uuid)`)}

-- Saves the regulatory reporting profile of an incident and plans its
-- filings. attrs: regimes (nis2, dora, cra), awareAt, classification (major or
-- non_major), classifiedAt, significant, activelyExploited and
-- measureAvailableAt; a key left out keeps its value. The first save needs
-- regimes and awareAt.
create or replace function ${fn("save_incident_regulatory_profile")}(incident_id uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_inc ${incidents};
  v_old ${profiles};
  v_row ${profiles};
  v_regimes text[];
  v_aware timestamptz;
  v_class text;
begin
  select * into v_inc from ${incidents} x where x.${i("id")} = save_incident_regulatory_profile.incident_id;
  if v_inc.${i("id")} is null then
    ${missing("INCIDENT_NOT_FOUND", "incident not found")}
  end if;
  if not ${allowed(`v_inc.${i("tenant")}`, write)} then
    ${forbidden("not allowed to change the regulatory profile")}
  end if;
  if save_incident_regulatory_profile.attrs is null or jsonb_typeof(save_incident_regulatory_profile.attrs) <> 'object' then
    ${invalid("attrs must be an object")}
  end if;
  select * into v_old from ${profiles} x where x.${p("incident")} = v_inc.${i("id")};
  if save_incident_regulatory_profile.attrs ? 'regimes' then
    select coalesce(array_agg(distinct e), '{}') into v_regimes
    from jsonb_array_elements_text(save_incident_regulatory_profile.attrs -> 'regimes') e;
  else
    v_regimes := v_old.${p("regimes")};
  end if;
  if v_regimes is null or not (v_regimes <@ array[${regimeList}]) then
    ${invalid("regimes must list nis2, dora or cra")}
  end if;
  v_aware := coalesce((save_incident_regulatory_profile.attrs ->> 'awareAt')::timestamptz, v_old.${p("awareAt")});
  if v_aware is null then
    ${invalid("awareAt is required: when the organization became aware of the incident")}
  end if;
  v_class := case when save_incident_regulatory_profile.attrs ? 'classification' then save_incident_regulatory_profile.attrs ->> 'classification' else v_old.${p("classification")} end;
  if v_class is not null and v_class not in ('major', 'non_major') then
    ${invalid("classification must be major or non_major")}
  end if;
  insert into ${profiles} (${p("incident")}, ${p("tenant")}, ${p("regimes")}, ${p("awareAt")}, ${p("classification")}, ${p("classifiedAt")}, ${p("significant")}, ${p("activelyExploited")}, ${p("measureAvailableAt")})
  values (v_inc.${i("id")}, v_inc.${i("tenant")}, v_regimes, v_aware, v_class,
    case when save_incident_regulatory_profile.attrs ? 'classifiedAt' then (save_incident_regulatory_profile.attrs ->> 'classifiedAt')::timestamptz else v_old.${p("classifiedAt")} end,
    coalesce((save_incident_regulatory_profile.attrs ->> 'significant')::boolean, v_old.${p("significant")}, false),
    coalesce((save_incident_regulatory_profile.attrs ->> 'activelyExploited')::boolean, v_old.${p("activelyExploited")}, false),
    case when save_incident_regulatory_profile.attrs ? 'measureAvailableAt' then (save_incident_regulatory_profile.attrs ->> 'measureAvailableAt')::timestamptz else v_old.${p("measureAvailableAt")} end)
  on conflict (${p("incident")}) do update set
    ${p("regimes")} = excluded.${p("regimes")}, ${p("awareAt")} = excluded.${p("awareAt")}, ${p("classification")} = excluded.${p("classification")},
    ${p("classifiedAt")} = excluded.${p("classifiedAt")}, ${p("significant")} = excluded.${p("significant")},
    ${p("activelyExploited")} = excluded.${p("activelyExploited")}, ${p("measureAvailableAt")} = excluded.${p("measureAvailableAt")},
    ${p("updatedAt")} = now()
  returning * into v_row;
  perform ${fn("plan_incident_filings")}(v_inc.${i("id")});
  ${ctx.record({
    type: "incident_profile.updated",
    payload: `jsonb_build_object('organizationId', v_row.${p("tenant")}, 'incidentId', v_row.${p("incident")}, 'regimes', to_jsonb(v_row.${p("regimes")}))`,
    subject: `'incidents/' || v_row.${p("incident")}::text`,
    tenant: `v_row.${p("tenant")}`,
    audit: {
      category: "configuration",
      targetType: "incident",
      recordId: `v_row.${p("incident")}::text`,
      summary: "'regulatory profile saved'",
    },
  })}
  return ${withFilings("v_row", `v_row.${p("incident")}`)};
end;
$$;
${userGrant(`${fn("save_incident_regulatory_profile")}(uuid, jsonb)`)}

-- The regulatory profile of an incident with its filings, or null.
create or replace function ${fn("get_incident_regulatory_profile")}(incident_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${withFilings("x", `x.${p("incident")}`)}
  from ${profiles} x
  where x.${p("incident")} = get_incident_regulatory_profile.incident_id
$$;
${userGrant(`${fn("get_incident_regulatory_profile")}(uuid)`)}

-- The filings of an organization, the earliest deadline first. Without
-- pending, only the ones not submitted yet.
create or replace function ${fn("list_incident_filings")}(tenant ${idType}, pending boolean default true)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not ${allowed("list_incident_filings.tenant", read)} then
    ${forbidden("not allowed to read incident filings")}
  end if;
  return coalesce((
    select jsonb_agg(${filingJson("x")} order by x.${f("dueAt")} nulls last, x.${f("id")})
    from ${filings} x
    where x.${f("tenant")} = list_incident_filings.tenant
      and (coalesce(list_incident_filings.pending, true) is false or x.${f("submittedAt")} is null)
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_incident_filings")}(${idType}, boolean)`)}

-- Records that a filing was submitted to the authority: when, by whom and the
-- reference the authority gave. A later stage's deadline then counts from it,
-- and the reminder for the filing is removed.
create or replace function ${fn("submit_incident_filing")}(incident_id uuid, regime text, stage text, reference text default null, notes text default null, submitted_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${filings};
begin
  select * into v_row from ${filings} x
  where x.${f("incident")} = submit_incident_filing.incident_id and x.${f("regime")} = submit_incident_filing.regime and x.${f("stage")} = submit_incident_filing.stage
  for update;
  if v_row.${f("id")} is null then
    ${missing("INCIDENT_FILING_NOT_FOUND", "no such filing is planned for this incident")}
  end if;
  if not ${allowed(`v_row.${f("tenant")}`, write)} then
    ${forbidden("not allowed to record a filing")}
  end if;
  if v_row.${f("submittedAt")} is not null then
    ${invalid("this filing was submitted already")}
  end if;
  if length(submit_incident_filing.reference) > 200 or length(submit_incident_filing.notes) > 5000 then
    ${invalid("the reference holds at most 200 characters and the notes 5000")}
  end if;
  update ${filings} x
  set ${f("submittedAt")} = coalesce(submit_incident_filing.submitted_at, now()), ${f("submittedBy")} = auth.uid(),
    ${f("reference")} = nullif(trim(submit_incident_filing.reference), ''), ${f("notes")} = nullif(trim(submit_incident_filing.notes), '')
  where x.${f("id")} = v_row.${f("id")}
  returning * into v_row;${dropReminder}
  perform ${fn("plan_incident_filings")}(v_row.${f("incident")});
  select * into v_row from ${filings} x where x.${f("id")} = v_row.${f("id")};
  ${ctx.record({
    type: "incident_filing.submitted",
    payload: `jsonb_build_object('organizationId', v_row.${f("tenant")}, 'incidentId', v_row.${f("incident")}, 'id', v_row.${f("id")}, 'regime', v_row.${f("regime")}, 'stage', v_row.${f("stage")}, 'dueAt', v_row.${f("dueAt")}, 'reference', v_row.${f("reference")})`,
    subject: `'incidents/' || v_row.${f("incident")}::text`,
    tenant: `v_row.${f("tenant")}`,
    audit: {
      category: "data",
      targetType: "incident",
      recordId: `v_row.${f("incident")}::text`,
      summary: `v_row.${f("regime")} || ' ' || v_row.${f("stage")} || ' submitted'`,
    },
  })}
  return ${filingJson("v_row")};
end;
$$;
${userGrant(`${fn("submit_incident_filing")}(uuid, text, text, text, text, timestamptz)`)}
`;
}
