import type { ExtraColumn, BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { fail, userGrant } from "../shared.ts";
import { subjectTitle } from "../subject-check-sql.ts";
import { hasValueEntry } from "../value-maps.ts";
import { splitName } from "./employees-options.ts";
import { hiringCandidate } from "./hiring-adoption.ts";
import { createdFromLink } from "./quotes-functions.ts";

export interface EmployeeNames {
  readonly fn: (name: string) => string;
  readonly t: (table: string) => string;
  readonly c: (table: string, column: string) => string;
  readonly read: string;
  readonly write: string;
  /** The employees.view_sensitive key, as a SQL literal. */
  readonly sensitive: string;
  readonly create: string;
  readonly contractsRead: string;
  readonly contractsWrite: string | undefined;
  readonly privateDetailsWrite: string | undefined;
  /** `text[]` SQL of the allowed employment types; the first is the default. */
  readonly types: string;
  /** SQL that is true for the service role. */
  readonly service: string;
  readonly extras: readonly ExtraColumn[];
  readonly name: (alias: string) => string;
  readonly json: (alias: string) => string;
}

interface Field {
  /** The camelCase field a change names. */
  readonly field: string;
  /** The logical column it writes. */
  readonly column: string;
  /** The value from the jsonb expression `v`. */
  readonly value: (v: string) => string;
}

/**
 * Every field `create_employee` and `update_employees` write, by its camelCase
 * name.
 */
const typeText = (v: string): string => `nullif(trim(${v} #>> '{}'), '')`;

function fields(ctx: BlockSqlContext): readonly Field[] {
  const text = typeText;
  const split = splitName(ctx);

  const cast =
    (type: string) =>
    (v: string): string =>
      `(${v} #>> '{}')::${type}`;

  const all: readonly Field[] = [
    ...(split
      ? [
          {
            field: "firstName",
            column: "firstName",
            value: (v: string) => `trim(${v} #>> '{}')`,
          },
          { field: "lastName", column: "lastName", value: text },
        ]
      : [
          {
            field: "name",
            column: "name",
            value: (v: string) => `trim(${v} #>> '{}')`,
          },
        ]),
    { field: "email", column: "email", value: text },
    { field: "userId", column: "user", value: cast("uuid") },
    { field: "jobTitle", column: "jobTitle", value: text },
    { field: "teamId", column: "team", value: cast("uuid") },
    { field: "managerId", column: "manager", value: cast("uuid") },
    {
      field: "employmentType",
      column: "employmentType",
      value: (v: string) => ctx.cast("employees", "employmentType", text(v)),
    },
    { field: "startDate", column: "startDate", value: cast("date") },
    { field: "endDate", column: "endDate", value: cast("date") },
  ];

  return all.filter((field) => ctx.has("employees", field.column));
}

export function employeeFunctions(
  ctx: BlockSqlContext,
  n: EmployeeNames,
): string {
  const employeeId = sqlString(ctx.resolved.entityNaming.rename("employeeId"));
  const { fn, t } = n;
  const e = (column: string): string => n.c("employees", column);
  const has = (column: string): boolean => ctx.has("employees", column);
  const table = t("employees");
  const touched = has("updatedAt") ? `, ${e("updatedAt")} = now()` : "";

  const editable = (alias: string): string =>
    `(${n.service} or ${ctx.scope.can(`${alias}.${e("tenant")}`, n.write)})`;

  // True when the caller is the employee `target` or one of its managers.
  const inMyTree = (target: string): string => `exists (
    with recursive up (id, manager) as (
      select u.${e("id")}, u.${e("manager")} from ${table} u where u.${e("id")} = ${target}
      union
      select u.${e("id")}, u.${e("manager")} from ${table} u join up on u.${e("id")} = up.manager
    )
    select 1 from up join ${table} me on me.${e("id")} = up.id where me.${e("user")} = auth.uid())`;

  const payload = (alias: string, extra: string): string =>
    `jsonb_build_object('organizationId', ${alias}.${e("tenant")}, 'employeeId', ${alias}.${e("id")}, 'subjectType', 'employee', 'subjectId', ${alias}.${e("id")}::text, 'name', ${n.name(alias)}${extra})`;

  const record = (type: string, alias: string, extra = ""): string =>
    ctx.record({
      type,
      payload: payload(alias, extra),
      subject: `'employees/' || ${alias}.${e("id")}::text`,
      tenant: `${alias}.${e("tenant")}::text`,
      audit: false,
    });

  const managerChanged = (alias: string, from: string): string =>
    record(
      "employee.manager_changed",
      alias,
      `, 'fromManagerId', ${from}, 'toManagerId', ${alias}.${e("manager")}`,
    );

  const memberships = ctx.of("memberships");

  const member = (tenant: string, user: string): string => `
  if ${user} is not null and not exists (
    select 1 from ${memberships.table("memberships")} m
    where m.${memberships.col("memberships", "tenant")} = ${tenant} and m.${memberships.col("memberships", "user")} = ${user}
  ) then
    ${fail("EMPLOYEE_USER_NOT_MEMBER", "the user is not a member of this organization", "22023")}
  end if;`;

  const settableStatuses = [
    ...new Set(
      ["preboarding", "active", "on_leave"].flatMap((label) => [
        label,
        ...ctx.appValues("employees", "status", label),
      ]),
    ),
  ]
    .map(sqlString)
    .join(", ");

  const typeLabel = (alias: string): string =>
    hasValueEntry(ctx.config.values, "employees", "employmentType")
      ? `(${ctx.label("employees", "employmentType", `${alias}.${e("employmentType")}`)})::text`
      : `${alias}.${e("employmentType")}`;

  const typeCheck = (alias: string): string =>
    has("employmentType")
      ? `
  if not (${typeLabel(alias)} = any (${n.types})) then
    ${fail("EMPLOYEE_TYPE_INVALID", "unknown employment type", "22023")}
  end if;`
      : "";

  const origin = has("originType") && has("originId");

  const privateTable =
    ctx.hasTable("privateDetails") && ctx.has("privateDetails", "offboardedAt")
      ? t("privateDetails")
      : undefined;

  const offboardedAt = (value: string, id: string): string =>
    privateTable === undefined
      ? ""
      : `
  update ${privateTable} x set ${n.c("privateDetails", "offboardedAt")} = ${value}
  where x.${n.c("privateDetails", "employee")} = ${id};`;

  const list = fields(ctx);

  const split = splitName(ctx);

  const given = (key: string): string =>
    `create_employee.attrs ->> ${sqlString(key)}`;

  const firstWord = `split_part(trim(${given("name")}), ' ', 1)`;

  const attr = (field: Field): string => {
    const value = field.value(
      `create_employee.attrs -> ${sqlString(field.field)}`,
    );

    if (split && field.field === "firstName") {
      return `coalesce(nullif(${value}, ''), nullif(${firstWord}, ''))`;
    }

    if (split && field.field === "lastName") {
      return `case when create_employee.attrs ? 'lastName' then ${value} else nullif(trim(substr(trim(${given("name")}), length(${firstWord}) + 1)), '') end`;
    }

    return value;
  };

  const extraValue = (attrs: string, ident: string): string =>
    `(jsonb_populate_record(null::${table}, ${attrs})).${ident}`;

  const insertColumns = [
    e("tenant"),
    ...list.map((field) => e(field.column)),
    e("status"),
    ...(origin ? [e("originType"), e("originId")] : []),
    ...(has("createdBy") ? [e("createdBy")] : []),
    ...n.extras.map((extra) => extra.ident),
  ];

  const insertValues = [
    "create_employee.tenant",
    ...list.map((field) =>
      field.column === "employmentType"
        ? ctx.cast(
            "employees",
            "employmentType",
            `coalesce(${typeText(`create_employee.attrs -> 'employmentType'`)}, (${n.types})[1])`,
          )
        : attr(field),
    ),
    ctx.cast("employees", "status", "v_status"),
    ...(origin
      ? [
          "create_employee.attrs -> 'origin' ->> 'type'",
          "create_employee.attrs -> 'origin' ->> 'id'",
        ]
      : []),
    ...(has("createdBy") ? ["auth.uid()"] : []),
    ...n.extras.map((extra) =>
      extraValue("create_employee.attrs", extra.ident),
    ),
  ];

  const existing = origin
    ? `
  if create_employee.attrs -> 'origin' ->> 'id' is not null then
    select * into v_row from ${table} x
    where x.${e("tenant")} = create_employee.tenant
      and x.${e("originType")} = create_employee.attrs -> 'origin' ->> 'type'
      and x.${e("originId")} = create_employee.attrs -> 'origin' ->> 'id';
    if v_row.${e("id")} is not null then
      return ${n.json("v_row")};
    end if;
  end if;`
    : "";

  const link = origin
    ? `
  if v_row.${e("originId")} is not null then
    ${createdFromLink(ctx, { tenant: `v_row.${e("tenant")}`, sourceType: "'employee'", sourceId: `v_row.${e("id")}::text`, originType: `v_row.${e("originType")}`, originId: `v_row.${e("originId")}` })}
  end if;`
    : "";

  const status = has("startDate")
    ? `coalesce(create_employee.attrs ->> 'status', case when (create_employee.attrs ->> 'startDate')::date > current_date then 'preboarding' else 'active' end)`
    : `coalesce(create_employee.attrs ->> 'status', 'active')`;

  const writes = [
    ...list.map(
      (field) => `      when ${sqlString(field.field)} then
        update ${table} x set ${e(field.column)} = ${field.value("v_change -> 'value'")}${touched} where x.${e("id")} = v_id returning * into v_row;`,
    ),
    ...n.extras.map(
      (extra) => `      when ${sqlString(extra.name)} then
        update ${table} x set ${extra.ident} = ${extraValue(`jsonb_build_object(${sqlString(extra.name)}, v_change -> 'value')`, extra.ident)}${touched} where x.${e("id")} = v_id returning * into v_row;`,
    ),
  ].join("\n");

  const rehire = [
    ...(has("endDate") ? [`${e("endDate")} = null`] : []),
    ...(has("offboardReason") ? [`${e("offboardReason")} = null`] : []),
  ];

  const offboardSet = [
    `${e("status")} = ${ctx.value("employees", "status", "offboarded")}`,
    ...(has("endDate")
      ? [`${e("endDate")} = coalesce(offboard_employee.end_date, current_date)`]
      : []),
    ...(has("offboardReason")
      ? [`${e("offboardReason")} = nullif(trim(offboard_employee.reason), '')`]
      : []),
  ].join(", ");

  const rowWith = (alias: string, depth: string): string =>
    `${n.json(alias)} || jsonb_build_object('depth', ${depth}, 'direct_reports', (select count(*) from ${table} r where r.${e("manager")} = ${alias}.${e("id")} and ${ctx.is("employees", "status", `r.${e("status")}`, ["offboarded"], true)}))`;

  return `
-- Creates an employee. attrs: name (required), email, userId, jobTitle,
-- teamId, managerId, employmentType, status, startDate, endDate, origin
-- ({ type, id }) and the extra columns. With an origin, creating again
-- returns the same employee. The status defaults to preboarding before the
-- start date and active from it.
create or replace function ${fn("create_employee")}(tenant ${ctx.idType}, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${table};
  v_status text;
begin
  if not (${n.service} or ${ctx.scope.can("create_employee.tenant", n.create)}) then
    ${fail("EMPLOYEE_FORBIDDEN", "not allowed to change employees")}
  end if;${existing}
  if ${split ? "coalesce(nullif(trim(create_employee.attrs ->> 'firstName'), ''), nullif(trim(create_employee.attrs ->> 'name'), ''))" : "nullif(trim(create_employee.attrs ->> 'name'), '')"} is null then
    ${fail("EMPLOYEE_ATTRS_INVALID", "an employee needs a name", "23502")}
  end if;
  ${ctx.hook("before_employee_create", [
    [ctx.idType, "create_employee.tenant"],
    ["jsonb", "create_employee.attrs"],
  ])}
  begin
    v_status := ${status};
    if v_status = 'offboarded' then
      ${fail("EMPLOYEE_STATUS_INVALID", "create the employee, then offboard them", "22023")}
    end if;
    insert into ${table} (${insertColumns.join(", ")})
    values (${insertValues.join(", ")})
    returning * into v_row;
  exception
    when unique_violation then
      ${fail("EMPLOYEE_USER_TAKEN", "that user is already an employee of this organization", "23505")}
    when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
      ${fail("EMPLOYEE_ATTRS_INVALID", "an employee field has an invalid value", "22023")}
  end;${typeCheck("v_row")}${member(`v_row.${e("tenant")}`, `v_row.${e("user")}`)}${link}
  ${record("employee.created", "v_row", `, 'userId', v_row.${e("user")}, 'managerId', v_row.${e("manager")}, 'status', v_row.${e("status")}`)}
  ${ctx.hook("after_employee_create", [["uuid", `v_row.${e("id")}`]])}
  return ${n.json("v_row")};
end;
$$;
${userGrant(`${fn("create_employee")}(${ctx.idType}, jsonb)`)}

-- Applies a batch of { employeeId, field, value } changes, each on its own:
-- a change that fails is rejected with its reason and the others stay.
-- status takes preboarding, active or on_leave; setting it on an
-- offboarded employee rehires them. Returns { accepted: [{ employeeId,
-- field }], rejected: [{ employeeId, field, hint, reason }] }.
create or replace function ${fn("update_employees")}(changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_change jsonb;
  v_id uuid;
  v_field text;
  v_row ${table};
  v_was ${table};
  v_accepted jsonb := '[]';
  v_rejected jsonb := '[]';
  v_hint text;
  v_reason text;
  v_state text;
  v_touched uuid[] := '{}';
begin
  if jsonb_typeof(coalesce(update_employees.changes, '[]')) <> 'array' then
    ${fail("EMPLOYEE_CHANGES_INVALID", "changes must be a list of { employeeId, field, value }", "22023")}
  end if;
  for v_change in select value from jsonb_array_elements(update_employees.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_id := (v_change ->> ${employeeId})::uuid;
      select * into v_was from ${table} x where x.${e("id")} = v_id and ${editable("x")};
      if v_was.${e("id")} is null then
        ${fail("EMPLOYEE_NOT_FOUND", "no such employee you can edit", "P0002")}
      end if;
      ${ctx.hook("before_employee_update", [
        ["uuid", "v_id"],
        ["text", "v_field"],
        ["jsonb", "v_change -> 'value'"],
      ])}
      case v_field
${writes}
${
  split
    ? `      when 'name' then
        update ${table} x set ${e("firstName")} = split_part(trim(v_change ->> 'value'), ' ', 1)${has("lastName") ? `, ${e("lastName")} = nullif(trim(substr(trim(v_change ->> 'value'), length(split_part(trim(v_change ->> 'value'), ' ', 1)) + 1)), '')` : ""}${touched} where x.${e("id")} = v_id returning * into v_row;
`
    : ""
}      when 'status' then
        if (v_change ->> 'value') not in (${settableStatuses}) then
          ${fail("EMPLOYEE_STATUS_INVALID", "status is preboarding, active or on_leave; offboard to end employment", "22023")}
        end if;
        update ${table} x set ${e("status")} = ${ctx.cast("employees", "status", "v_change ->> 'value'")}${touched} where x.${e("id")} = v_id returning * into v_row;
        if ${ctx.is("employees", "status", `v_was.${e("status")}`, ["offboarded"])} then${
          rehire.length === 0
            ? ""
            : `
          update ${table} x set ${rehire.join(", ")} where x.${e("id")} = v_id returning * into v_row;`
        }${offboardedAt("null", "v_id")}
          null;
        end if;
      else
        ${fail("EMPLOYEE_FIELD_UNKNOWN", "that field can't be written", "22023")}
      end case;
      if ${split ? `v_field in ('name', 'firstName') and nullif(v_row.${e("firstName")}, '')` : `v_field = 'name' and nullif(v_row.${e("name")}, '')`} is null then
        ${fail("EMPLOYEE_ATTRS_INVALID", "an employee needs a name", "23502")}
      end if;${typeCheck("v_row")}
      if v_field = 'userId' then${member(`v_row.${e("tenant")}`, `v_row.${e("user")}`)}
        null;
      end if;
      if v_row.${e("manager")} is distinct from v_was.${e("manager")} then
        ${managerChanged("v_row", `v_was.${e("manager")}`)}
      end if;
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object(${employeeId}, v_id, 'field', v_field));
      v_touched := array_append(v_touched, v_id);
      ${ctx.hook("after_employee_update", [
        ["uuid", "v_id"],
        ["text", "v_field"],
      ])}
    exception when others then
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text, v_state = returned_sqlstate;
      if v_state = '23505' then
        v_hint := 'EMPLOYEE_USER_TAKEN';
      elsif nullif(v_hint, '') is null and v_state in ('23514', '23502', '22P02', '22007', '22008') then
        v_hint := 'EMPLOYEE_ATTRS_INVALID';
      end if;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object(${employeeId}, v_change ->> ${employeeId}, 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from ${table} x where x.${e("id")} = any (v_touched) loop
    ${record("employee.updated", "v_row", `, 'fields', (select jsonb_agg(distinct a ->> 'field') from jsonb_array_elements(v_accepted) a where (a ->> ${employeeId})::uuid = v_row.${e("id")})`)}
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$$;
${userGrant(`${fn("update_employees")}(jsonb)`)}

-- Ends an employment: the status becomes offboarded and the end date is
-- set (today by default). The employee's reports move to their manager.
-- Offboarding an offboarded employee returns them unchanged.
create or replace function ${fn("offboard_employee")}(employee uuid, end_date date, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${table};
  v_report ${table};
begin
  select * into v_row from ${table} x where x.${e("id")} = offboard_employee.employee;
  if v_row.${e("id")} is null or not ${editable("v_row")} then
    ${fail("EMPLOYEE_NOT_FOUND", "no such employee you can offboard", "P0002")}
  end if;
  if ${ctx.is("employees", "status", `v_row.${e("status")}`, ["offboarded"])} then
    return ${n.json("v_row")};
  end if;
  ${ctx.hook("before_employee_offboard", [["uuid", `v_row.${e("id")}`]])}
  begin
    update ${table} x set ${offboardSet}${touched}
    where x.${e("id")} = v_row.${e("id")}
    returning * into v_row;
  exception when check_violation then
    ${fail("EMPLOYEE_ATTRS_INVALID", "the end date is before the start date", "22023")}
  end;
  for v_report in select * from ${table} x where x.${e("manager")} = v_row.${e("id")} loop
    update ${table} x set ${e("manager")} = v_row.${e("manager")}${touched}
    where x.${e("id")} = v_report.${e("id")}
    returning * into v_report;
    ${managerChanged("v_report", `v_row.${e("id")}`)}
  end loop;${offboardedAt("now()", `v_row.${e("id")}`)}
  ${record("employee.offboarded", "v_row", `, 'endDate', ${has("endDate") ? `v_row.${e("endDate")}` : "current_date"}, 'reason', ${has("offboardReason") ? `v_row.${e("offboardReason")}` : "nullif(trim(offboard_employee.reason), '')"}`)}
  ${ctx.hook("after_employee_offboard", [["uuid", `v_row.${e("id")}`]])}
  return ${n.json("v_row")};
end;
$$;
${userGrant(`${fn("offboard_employee")}(uuid, date, text)`)}

-- The org chart under root, or under every employee without a manager when
-- root is null: current employees with their depth and number of direct
-- reports, ordered for display. Without employees.read the caller sees
-- the chart under themselves or under one of their reports.
create or replace function ${fn("org_chart")}(tenant ${ctx.idType}, root uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (${n.service} or ${ctx.scope.can("org_chart.tenant", n.read)} or (org_chart.root is not null and ${inMyTree("org_chart.root")})) then
    ${fail("EMPLOYEE_FORBIDDEN", "not allowed to read the org chart")}
  end if;
  return (
    with recursive tree (id, depth, path) as (
      select x.${e("id")}, 0, array[lower(${n.name("x")}), x.${e("id")}::text]
      from ${table} x
      where x.${e("tenant")} = org_chart.tenant and ${ctx.is("employees", "status", `x.${e("status")}`, ["offboarded"], true)}
        and case when org_chart.root is null then x.${e("manager")} is null else x.${e("id")} = org_chart.root end
      union all
      select c.${e("id")}, tree.depth + 1, tree.path || array[lower(${n.name("c")}), c.${e("id")}::text]
      from ${table} c join tree on c.${e("manager")} = tree.id
      where ${ctx.is("employees", "status", `c.${e("status")}`, ["offboarded"], true)} and tree.depth < 100
    )
    select coalesce(jsonb_agg(${rowWith("x", "tree.depth")} order by tree.path), '[]'::jsonb)
    from tree join ${table} x on x.${e("id")} = tree.id
  );
end;
$$;
${userGrant(`${fn("org_chart")}(${ctx.idType}, uuid)`)}

-- A manager's current reports: direct ones (depth 1), or everyone under
-- them with indirect. Managers read their own reports without
-- employees.read.
create or replace function ${fn("reports_of")}(manager uuid, indirect boolean)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select x.${e("tenant")} into v_tenant from ${table} x where x.${e("id")} = reports_of.manager;
  if v_tenant is null or not (${n.service} or ${ctx.scope.can("v_tenant", n.read)} or ${inMyTree("reports_of.manager")}) then
    ${fail("EMPLOYEE_NOT_FOUND", "no such employee you can read", "P0002")}
  end if;
  return (
    with recursive tree (id, depth, path) as (
      select x.${e("id")}, 1, array[lower(${n.name("x")}), x.${e("id")}::text]
      from ${table} x
      where x.${e("manager")} = reports_of.manager and ${ctx.is("employees", "status", `x.${e("status")}`, ["offboarded"], true)}
      union all
      select c.${e("id")}, tree.depth + 1, tree.path || array[lower(${n.name("c")}), c.${e("id")}::text]
      from ${table} c join tree on c.${e("manager")} = tree.id
      where coalesce(reports_of.indirect, false) and ${ctx.is("employees", "status", `c.${e("status")}`, ["offboarded"], true)} and tree.depth < 100
    )
    select coalesce(jsonb_agg(${rowWith("x", "tree.depth")} order by tree.path), '[]'::jsonb)
    from tree join ${table} x on x.${e("id")} = tree.id
  );
end;
$$;
${userGrant(`${fn("reports_of")}(uuid, boolean)`)}
${fromApplication(ctx, n)}`;
}

/**
 * `employee_from_application`, with the hiring module and the origin columns:
 * the employee for a hired application, made once.
 */
function fromApplication(ctx: BlockSqlContext, n: EmployeeNames): string {
  if (
    !ctx.installed("hiring") ||
    !ctx.has("employees", "originType") ||
    !ctx.has("employees", "originId")
  ) {
    return "";
  }

  const hiring = ctx.of("hiring");
  const a = (column: string): string => hiring.col("applications", column);
  const j = (column: string): string => hiring.col("jobs", column);
  const e = (column: string): string => n.c("employees", column);
  const candidate = hiringCandidate(hiring, "v_application");

  return `
-- The employee for a hired application, in preboarding: the name comes from
-- the candidate's record in config.records, and the job title, team and
-- employment type from the job. attrs overrides any of them. Calling it
-- again returns the same employee, and with the relations module the
-- employee is created_from the application.
create or replace function ${n.fn("employee_from_application")}(application uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_application ${hiring.table("applications")};
  v_job ${hiring.table("jobs")};
  v_existing ${n.t("employees")};
begin
  select * into v_application from ${hiring.table("applications")} x where x.${a("id")} = employee_from_application.application;
  if v_application.${a("id")} is null or not (${n.service} or ${ctx.scope.can(`v_application.${a("tenant")}`, n.write)}) then
    ${fail("EMPLOYEE_ORIGIN_NOT_FOUND", "no such application you can turn into an employee", "P0002")}
  end if;
  select * into v_existing from ${n.t("employees")} x
  where x.${e("tenant")} = v_application.${a("tenant")} and x.${e("originType")} = 'application' and x.${e("originId")} = v_application.${a("id")}::text;
  if v_existing.${e("id")} is not null then
    return ${n.json("v_existing")};
  end if;
  if v_application.${a("state")} <> 'hired' then
    ${fail("EMPLOYEE_APPLICATION_NOT_HIRED", "only a hired application becomes an employee", "55000")}
  end if;
  select * into v_job from ${hiring.table("jobs")} x where x.${j("id")} = v_application.${a("job")};
  return ${n.fn("create_employee")}(v_application.${a("tenant")}, jsonb_strip_nulls(jsonb_build_object(
      'name', ${subjectTitle(ctx, candidate.type, candidate.id)},
      'jobTitle', v_job.${j("title")},
      'teamId', v_job.${j("team")},
      'employmentType', case when v_job.${j("employmentType")} = any (${n.types}) then v_job.${j("employmentType")} end,
      'status', 'preboarding'))
    || coalesce(employee_from_application.attrs, '{}'::jsonb)
    || jsonb_build_object('origin', jsonb_build_object('type', 'application', 'id', v_application.${a("id")}::text)));
end;
$$;
${userGrant(`${n.fn("employee_from_application")}(uuid, jsonb)`)}
`;
}
