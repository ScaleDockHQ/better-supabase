import type { EmployeesEvents } from "../../blocks/employees/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";
import type { EmployeeNames } from "./employees-functions.ts";

import { sqlString } from "../../core/template.ts";
import { employeeKeyBackfillSql, employeeKeySql } from "../employee-key-sql.ts";
import {
  addExtraColumns,
  addForeignKey,
  fail,
  lockTable,
  schemaPreamble,
  triggerGrant,
} from "../shared.ts";
import { employeeFunctions } from "./employees-functions.ts";
import {
  editableContracts,
  FLAT_DETAILS,
  flatDetails,
  splitName,
} from "./employees-options.ts";
import { sensitiveFunctions } from "./employees-sensitive.ts";
import { moduleOperations } from "./permissions-model.ts";

const EMPLOYEE = [
  "organizationId",
  "employeeId",
  "subjectType",
  "subjectId",
  "name",
] as const;

const EVENTS: BlockSqlEvents<EmployeesEvents> = {
  "employee.created": {
    subject: "employees",
    payload: [...EMPLOYEE, "userId", "managerId", "status"],
  },
  "employee.updated": {
    subject: "employees",
    payload: [...EMPLOYEE, "fields"],
  },
  "employee.offboarded": {
    subject: "employees",
    payload: [...EMPLOYEE, "endDate", "reason"],
  },
  "employee.manager_changed": {
    subject: "employees",
    payload: [...EMPLOYEE, "fromManagerId", "toManagerId"],
  },
};

/** The statuses, in the order an employee usually moves through them. */
const EMPLOYEE_STATUSES = [
  "preboarding",
  "active",
  "on_leave",
  "offboarded",
] as const;

const EMPLOYMENT_TYPES = ["employee", "contractor", "intern", "temporary"];

const NAMES: BlockSqlNames = {
  entities: {
    employee: {
      table: "employees",
      singular: "employee",
      primary: true,
      subject: {
        title: "name",
        fallbackTitle: "firstName",
        permissions: { read: "read", write: "write" },
        search: { title: "name", body: ["email", "jobTitle"] },
      },
    },
  },
  events: EVENTS,
  hooks: [
    "before_employee_create",
    "after_employee_create",
    "before_employee_update",
    "after_employee_update",
    "before_employee_offboard",
    "after_employee_offboard",
  ],
  options: [
    "employmentTypes",
    "extraColumns",
    "privateDetailsExtraColumns",
    "contractExtraColumns",
    "name",
    "privateDetails",
    "contracts",
  ],
  tables: {
    employees: {
      name: "employees",
      app: {
        unused: (ctx) => (splitName(ctx) ? [] : ["firstName", "lastName"]),
      },
      lifecycle: { tenant: "tenant", user: "user", export: true },
      optional: [
        "name",
        "firstName",
        "lastName",
        "email",
        "jobTitle",
        "team",
        "employmentType",
        "startDate",
        "endDate",
        "offboardReason",
        "originType",
        "originId",
        "createdBy",
        "createdAt",
        "updatedAt",
      ],
      columns: {
        id: "id",
        tenant: "tenant_id",
        user: "user_id",
        name: "name",
        email: "email",
        jobTitle: "job_title",
        team: "team_id",
        manager: "manager_id",
        employmentType: "employment_type",
        status: "status",
        startDate: "start_date",
        endDate: "end_date",
        offboardReason: "offboard_reason",
        originType: "origin_type",
        originId: "origin_id",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
        firstName: "first_name",
        lastName: "last_name",
      },
      typed: ["status"],
    },
    privateDetails: {
      name: "employee_private_details",
      app: { unused: (ctx) => (flatDetails(ctx) ? [] : [...FLAT_DETAILS]) },
      optionalTable: true,
      lifecycle: { tenant: "tenant", user: "user", export: true },
      optional: [
        "user",
        "nationalId",
        "iban",
        "birthDate",
        "personalEmail",
        "phone",
        "address",
        "emergencyContacts",
        "offboardedAt",
        "anonymizedAt",
        "updatedAt",
        "updatedBy",
        ...FLAT_DETAILS,
      ],
      columns: {
        employee: "employee_id",
        tenant: "tenant_id",
        user: "user_id",
        nationalId: "national_id",
        iban: "iban",
        birthDate: "birth_date",
        personalEmail: "personal_email",
        phone: "phone",
        address: "address",
        emergencyContacts: "emergency_contacts",
        offboardedAt: "offboarded_at",
        anonymizedAt: "anonymized_at",
        updatedAt: "updated_at",
        updatedBy: "updated_by",
        addressLine1: "address_line1",
        addressLine2: "address_line2",
        postalCode: "postal_code",
        city: "city",
        region: "region",
        country: "country",
        emergencyName: "emergency_contact_name",
        emergencyPhone: "emergency_contact_phone",
        emergencyRelation: "emergency_contact_relation",
      },
    },
    contracts: {
      name: "employee_contracts",
      app: {},
      optionalTable: true,
      lifecycle: { tenant: "tenant", export: true },
      optional: ["salaryPeriod", "note", "createdBy", "createdAt"],
      columns: {
        id: "id",
        tenant: "tenant_id",
        employee: "employee_id",
        startsOn: "starts_on",
        endsOn: "ends_on",
        hoursPerWeek: "hours_per_week",
        salary: "salary",
        currency: "currency",
        salaryPeriod: "salary_period",
        note: "note",
        createdBy: "created_by",
        createdAt: "created_at",
      },
      mappable: ["salaryPeriod"],
    },
  },
};

function nameColumns(
  ctx: BlockSqlContext,
  e: (column: string) => string,
): string {
  if (!splitName(ctx)) {
    return `  ${e("name")} text not null check (length(trim(${e("name")})) between 1 and 200),`;
  }

  const last = ctx.has("employees", "lastName");

  return [
    `  ${e("firstName")} text not null check (length(trim(${e("firstName")})) between 1 and 200),`,
    ...(last
      ? [
          `  ${e("lastName")} text check (${e("lastName")} is null or length(${e("lastName")}) <= 200),`,
        ]
      : []),
    ...(ctx.has("employees", "name")
      ? [
          `  ${e("name")} text generated always as (trim(${e("firstName")}${last ? ` || coalesce(' ' || ${e("lastName")}, '')` : ""})) stored,`,
        ]
      : []),
  ].join("\n");
}

/** The keys the employee reads return next to the table's columns. */
const RESERVED = ["depth", "direct_reports"];

function tablesSql(ctx: BlockSqlContext, n: EmployeeNames): string {
  if (!ctx.manages) {
    return "";
  }

  const { t } = n;
  const e = (column: string): string => n.c("employees", column);
  const p = (column: string): string => n.c("privateDetails", column);
  const k = (column: string): string => n.c("contracts", column);
  const statuses = EMPLOYEE_STATUSES.map(sqlString).join(", ");

  return `
create table if not exists ${t("employees")} (
  ${e("id")} uuid primary key default gen_random_uuid(),
  ${e("tenant")} ${ctx.idType} not null,
  ${e("user")} uuid references auth.users (id) on delete set null,
${nameColumns(ctx, e)}
  ${e("email")} text check (${e("email")} is null or length(${e("email")}) <= 320),
  ${e("jobTitle")} text check (${e("jobTitle")} is null or length(${e("jobTitle")}) <= 200),
  ${e("team")} uuid,
  ${e("manager")} uuid references ${t("employees")} (${e("id")}) on delete set null,
  ${e("employmentType")} text not null default 'employee',
  ${e("status")} text not null default 'preboarding' check (${e("status")} in (${statuses})),
  ${e("startDate")} date,
  ${e("endDate")} date,
  ${e("offboardReason")} text,
  ${e("originType")} text,
  ${e("originId")} text,
  ${e("createdBy")} uuid,
  ${e("createdAt")} timestamptz not null default now(),
  ${e("updatedAt")} timestamptz not null default now(),
  check (${e("manager")} is null or ${e("manager")} <> ${e("id")}),
  check (${e("endDate")} is null or ${e("startDate")} is null or ${e("endDate")} >= ${e("startDate")}),
  check ((${e("originType")} is null) = (${e("originId")} is null))
);
create unique index if not exists ${ctx.naming.rename("employees_user_idx")} on ${t("employees")} (${e("tenant")}, ${e("user")}) where ${e("user")} is not null;
create index if not exists ${ctx.naming.rename("employees_account_idx")} on ${t("employees")} (${e("user")}) where ${e("user")} is not null;
create unique index if not exists ${ctx.naming.rename("employees_origin_idx")} on ${t("employees")} (${e("tenant")}, ${e("originType")}, ${e("originId")}) where ${e("originId")} is not null;
create index if not exists ${ctx.naming.rename("employees_tenant_status_idx")} on ${t("employees")} (${e("tenant")}, ${e("status")});
create index if not exists ${ctx.naming.rename("employees_manager_idx")} on ${t("employees")} (${e("manager")}) where ${e("manager")} is not null;${addExtraColumns(t("employees"), ctx.extraColumns("employees", RESERVED))}
${lockTable(t("employees"), { read: true })}
drop policy if exists ${ctx.naming.rename("employees_read")} on ${t("employees")};
create policy ${ctx.naming.rename("employees_read")} on ${t("employees")} for select to authenticated
using (${ctx.scope.check(e("tenant"), n.read)} or ${e("user")} = (select auth.uid()));

-- Private details stay out of the directory: readable with
-- employees.view_sensitive and by the employee.
create table if not exists ${t("privateDetails")} (
  ${p("employee")} uuid primary key references ${t("employees")} (${e("id")}) on delete cascade,
  ${p("tenant")} ${ctx.idType} not null,
  ${p("user")} uuid,
  ${p("nationalId")} text check (${p("nationalId")} is null or length(${p("nationalId")}) <= 64),
${ctx.has("privateDetails", "iban") ? `  ${p("iban")} text check (${p("iban")} is null or ${p("iban")} ~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{8,30}$'),\n` : ""}  ${p("birthDate")} date,
  ${p("personalEmail")} text check (${p("personalEmail")} is null or length(${p("personalEmail")}) <= 320),
  ${p("phone")} text check (${p("phone")} is null or length(${p("phone")}) <= 40),
${ctx.has("privateDetails", "address") ? `  ${p("address")} jsonb check (${p("address")} is null or jsonb_typeof(${p("address")}) = 'object'),\n` : ""}${ctx.has("privateDetails", "emergencyContacts") ? `  ${p("emergencyContacts")} jsonb not null default '[]' check (jsonb_typeof(${p("emergencyContacts")}) = 'array'),\n` : ""}${
    flatDetails(ctx)
      ? FLAT_DETAILS.filter((logical) => ctx.has("privateDetails", logical))
          .map(
            (logical) =>
              `  ${p(logical)} text check (${p(logical)} is null or length(${p(logical)}) <= 200),\n`,
          )
          .join("")
      : ""
  }  ${p("offboardedAt")} timestamptz,
  ${p("anonymizedAt")} timestamptz,
  ${p("updatedAt")} timestamptz not null default now(),
  ${p("updatedBy")} uuid
);${addExtraColumns(t("privateDetails"), ctx.extraColumns("privateDetails", [], "privateDetailsExtraColumns"))}
create index if not exists ${ctx.naming.rename("employee_private_details_user_idx")} on ${t("privateDetails")} (${p("user")}) where ${p("user")} is not null;
${lockTable(t("privateDetails"), { read: true })}
drop policy if exists ${ctx.naming.rename("employee_private_details_read")} on ${t("privateDetails")};
create policy ${ctx.naming.rename("employee_private_details_read")} on ${t("privateDetails")} for select to authenticated
using (${ctx.scope.check(p("tenant"), n.sensitive)} or ${
    ctx.has("privateDetails", "user")
      ? `${p("user")} = (select auth.uid())`
      : `exists (
  select 1 from ${t("employees")} x where x.${e("id")} = ${p("employee")} and x.${e("user")} = (select auth.uid()))`
  });

-- Contract history: a new contract ends the one before it, and rows are
-- never edited. Salary is in minor units of its currency.
create table if not exists ${t("contracts")} (
  ${k("id")} uuid primary key default gen_random_uuid(),
  ${k("tenant")} ${ctx.idType} not null,
  ${k("employee")} uuid not null references ${t("employees")} (${e("id")}) on delete cascade,
  ${k("startsOn")} date not null,
  ${k("endsOn")} date,
  ${k("hoursPerWeek")} numeric(5, 2) check (${k("hoursPerWeek")} is null or (${k("hoursPerWeek")} > 0 and ${k("hoursPerWeek")} <= 168)),
  ${k("salary")} bigint check (${k("salary")} is null or ${k("salary")} >= 0),
  ${k("currency")} text check (${k("currency")} is null or ${k("currency")} ~ '^[A-Z]{3}$'),
  ${k("salaryPeriod")} text check (${k("salaryPeriod")} is null or ${k("salaryPeriod")} in ('hour', 'week', 'month', 'year')),
  ${k("note")} text,
  ${k("createdBy")} uuid,
  ${k("createdAt")} timestamptz not null default now(),
  check (${k("endsOn")} is null or ${k("endsOn")} >= ${k("startsOn")}),
  check ((${k("salary")} is null) = (${k("currency")} is null))
);${addExtraColumns(t("contracts"), ctx.extraColumns("contracts", [], "contractExtraColumns"))}
create index if not exists ${ctx.naming.rename("employee_contracts_employee_idx")} on ${t("contracts")} (${k("employee")}, ${k("startsOn")} desc);
${lockTable(t("contracts"), { read: true })}
drop policy if exists ${ctx.naming.rename("employee_contracts_read")} on ${t("contracts")};
create policy ${ctx.naming.rename("employee_contracts_read")} on ${t("contracts")} for select to authenticated
using (${ctx.scope.check(k("tenant"), n.sensitive)} or exists (
  select 1 from ${t("employees")} x where x.${e("id")} = ${k("employee")} and x.${e("user")} = (select auth.uid())));
`;
}

/** The manager guard, and the user id the private details mirror. */
function triggersSql(ctx: BlockSqlContext, n: EmployeeNames): string {
  const { t } = n;
  const e = (column: string): string => n.c("employees", column);
  const mirrorName = ctx.naming.rename("bsb_employee_user_mirror");
  const guardName = ctx.naming.rename("bsb_employee_manager_guard");

  const mirror =
    ctx.hasTable("privateDetails") && ctx.has("privateDetails", "user")
      ? `
-- The private details carry the employee's user, so the employee reads them.
create or replace function better_supabase.${mirrorName}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update ${t("privateDetails")} x set ${n.c("privateDetails", "user")} = new.${e("user")}
  where x.${n.c("privateDetails", "employee")} = new.${e("id")}
    and x.${n.c("privateDetails", "user")} is distinct from new.${e("user")};
  return null;
end;
$$;
${triggerGrant(`better_supabase.${mirrorName}()`)}
drop trigger if exists ${mirrorName} on ${t("employees")};
create trigger ${mirrorName} after update of ${e("user")} on ${t("employees")}
for each row execute function better_supabase.${mirrorName}();
`
      : "";

  return `
-- A manager is an employee of the same organization and never one of the
-- employee's own reports, so the org chart stays a tree.
create or replace function better_supabase.${guardName}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.${e("manager")} is null then
    return new;
  end if;
  if not exists (
    select 1 from ${t("employees")} m
    where m.${e("id")} = new.${e("manager")} and m.${e("tenant")} = new.${e("tenant")}
  ) then
    ${fail("EMPLOYEE_MANAGER_NOT_FOUND", "the manager is not an employee of this organization", "23503")}
  end if;
  if new.${e("manager")} = new.${e("id")} or exists (
    with recursive up (id) as (
      select m.${e("manager")} from ${t("employees")} m where m.${e("id")} = new.${e("manager")}
      union
      select m.${e("manager")} from ${t("employees")} m join up on m.${e("id")} = up.id
    )
    select 1 from up where up.id = new.${e("id")}
  ) then
    ${fail("EMPLOYEE_MANAGER_CYCLE", "an employee can't report to one of their own reports", "22023")}
  end if;
  return new;
end;
$$;
${triggerGrant(`better_supabase.${guardName}()`)}
drop trigger if exists ${guardName} on ${t("employees")};
create trigger ${guardName} before insert or update of ${e("manager")} on ${t("employees")}
for each row execute function better_supabase.${guardName}();
${mirror}`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const keys = moduleOperations("employees");
  const split = splitName(ctx);

  if (!split && !ctx.has("employees", "name")) {
    throw new TypeError(
      'blocks.employees.columns.employees.name can be null only with options.name "split"',
    );
  }

  if (split && !ctx.has("employees", "firstName")) {
    throw new TypeError(
      'blocks.employees.options.name "split" writes the first name, so columns.employees.firstName can\'t be null',
    );
  }

  const fullName = (alias: string): string => {
    if (ctx.has("employees", "name")) {
      return `${alias}.${ctx.col("employees", "name")}`;
    }

    const first = `${alias}.${ctx.col("employees", "firstName")}`;

    return ctx.has("employees", "lastName")
      ? `trim(${first} || coalesce(' ' || ${alias}.${ctx.col("employees", "lastName")}, ''))`
      : first;
  };

  const names: EmployeeNames = {
    fn: (name) => ctx.fn(name),
    t: (table) => ctx.table(table),
    c: (table, column) => ctx.col(table, column),
    read: ctx.permission("read", keys.read),
    write: ctx.permission("write", keys.write),
    sensitive: ctx.permission("viewSensitive", keys.viewSensitive),
    types: `array[${ctx.list("employmentTypes", EMPLOYMENT_TYPES).map(sqlString).join(", ")}]::text[]`,
    service: "(auth.role() = 'service_role')",
    extras: ctx.extraColumns("employees", RESERVED),
    name: fullName,
    json: (alias) =>
      ctx.has("employees", "name")
        ? `to_jsonb(${alias})`
        : `(to_jsonb(${alias}) || jsonb_build_object('name', ${fullName(alias)}))`,
  };

  return `${schemaPreamble(ctx)}
-- Employees: the people an organization employs, with or without an
-- account, their manager, team and status; private details and contracts
-- behind employees.view_sensitive.
${tablesSql(ctx, names)}${triggersSql(ctx, names)}${employeeFunctions(ctx, names)}${sensitiveFunctions(ctx, names)}${timeTrackingSql(ctx)}`;
}

const timeByEmployee = (ctx: BlockSqlContext): boolean =>
  ctx.installed("time-tracking") &&
  ctx.of("time-tracking").option("owner") === "employee";

function timeTrackingSql(ctx: BlockSqlContext): string {
  if (!ctx.installed("time-tracking")) {
    return "";
  }

  const time = ctx.of("time-tracking");

  if (!timeByEmployee(ctx)) {
    return employeeKeySql(ctx, { owner: time, table: "entries" });
  }

  return (["entries", "timesheets"] as const)
    .filter((table) => time.owns(table))
    .map(
      (table) =>
        `\n${addForeignKey({
          table: time.table(table),
          name: `${time.tableName(table).name}_employee_fkey`,
          column: time.col(table, "employee"),
          references: `${ctx.table("employees")} (${ctx.col("employees", "id")})`,
          onDelete: "restrict",
        })}\n`,
    )
    .join("");
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  const fromApplication =
    ctx.installed("hiring") && ctx.has("employees", "originId")
      ? [
          {
            name: "employee_from_application",
            args: ["uuid", "jsonb"],
            returns: "jsonb",
          },
        ]
      : [];

  const privateDetails = ctx.hasTable("privateDetails")
    ? [
        { name: "employee_private_details", args: ["uuid"], returns: "jsonb" },
        {
          name: "save_employee_private_details",
          args: ["uuid", "jsonb"],
          returns: "jsonb",
        },
      ]
    : [];

  const contracts = ctx.hasTable("contracts")
    ? [
        { name: "employee_contracts", args: ["uuid"], returns: "jsonb" },
        {
          name: "add_employee_contract",
          args: ["uuid", "jsonb"],
          returns: "jsonb",
        },
        ...(editableContracts(ctx)
          ? [
              {
                name: "update_employee_contract",
                args: ["uuid", "jsonb"],
                returns: "jsonb",
              },
              {
                name: "delete_employee_contract",
                args: ["uuid"],
                returns: "jsonb",
              },
            ]
          : []),
      ]
    : [];

  return [
    { name: "create_employee", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "update_employees", args: ["jsonb"], returns: "jsonb" },
    {
      name: "offboard_employee",
      args: ["uuid", "date", "text"],
      returns: "jsonb",
    },
    { name: "org_chart", args: ["{id}", "uuid"], returns: "jsonb" },
    { name: "reports_of", args: ["uuid", "boolean"], returns: "jsonb" },
    ...fromApplication,
    ...privateDetails,
    ...contracts,
  ];
}

export const EMPLOYEES: BlockSqlDefinition = {
  name: "employees",
  scopes: ["tenant"],
  title: "Employees",
  description:
    "Employees with or without an account, a manager, team, job title, employment type and status, an org chart, offboarding, and private details and contracts behind employees.view_sensitive. With time-tracking, time entries carry the employee_id of their member.",
  requires: ["memberships", "permissions"],
  integrates: ["outbox", "relations", "hiring", "time-tracking"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 2,
  upgrades: [
    {
      from: 1,
      description:
        "With time-tracking, time entries gain employee_id, backfilled and kept current by triggers.",
      sql: (ctx) =>
        ctx.installed("time-tracking") && !timeByEmployee(ctx)
          ? employeeKeyBackfillSql(ctx, {
              owner: ctx.of("time-tracking"),
              table: "entries",
              quiet: [
                ctx.of("time-tracking").naming.rename("bsb_time_entry_guard"),
              ],
            })
          : "",
    },
  ],
  names: NAMES,
  contract,
  build,
};
