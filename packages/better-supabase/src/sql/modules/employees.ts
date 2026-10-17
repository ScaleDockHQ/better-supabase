import type { EmployeesEvents } from "../../blocks/employees/events.ts";
import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import { sqlString } from "../../core/template.ts";
import { addExtraColumns, fail, lockTable, schemaPreamble } from "../shared.ts";
import { moduleOperations } from "./access-model.ts";
import {
  employeeFunctions,
  type EmployeeNames,
} from "./employees-functions.ts";
import { sensitiveFunctions } from "./employees-sensitive.ts";

const EMPLOYEE = [
  "organizationId",
  "employeeId",
  "subjectType",
  "subjectId",
  "name",
] as const;

const EVENTS: ModuleEvents<EmployeesEvents> = {
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

const NAMES: ModuleNames = {
  events: EVENTS,
  hooks: [
    "before_employee_create",
    "after_employee_create",
    "before_employee_update",
    "after_employee_update",
    "before_employee_offboard",
    "after_employee_offboard",
  ],
  options: ["employmentTypes", "extraColumns"],
  tables: {
    employees: {
      name: "employees",
      lifecycle: { tenant: "tenant", user: "user", export: true },
      optional: [
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
      },
    },
    privateDetails: {
      name: "employee_private_details",
      optionalTable: true,
      lifecycle: { tenant: "tenant", user: "user", export: true },
      optional: [
        "user",
        "nationalId",
        "birthDate",
        "personalEmail",
        "phone",
        "address",
        "emergencyContacts",
        "offboardedAt",
        "anonymizedAt",
        "updatedAt",
        "updatedBy",
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
      },
    },
    contracts: {
      name: "employee_contracts",
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
    },
  },
};

/** The keys the employee reads return next to the table's columns. */
const RESERVED = ["depth", "direct_reports"];

function tablesSql(ctx: ModuleContext, n: EmployeeNames): string {
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
  ${e("name")} text not null check (length(trim(${e("name")})) between 1 and 200),
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
create unique index if not exists employees_user_idx on ${t("employees")} (${e("tenant")}, ${e("user")}) where ${e("user")} is not null;
create index if not exists employees_account_idx on ${t("employees")} (${e("user")}) where ${e("user")} is not null;
create unique index if not exists employees_origin_idx on ${t("employees")} (${e("tenant")}, ${e("originType")}, ${e("originId")}) where ${e("originId")} is not null;
create index if not exists employees_tenant_status_idx on ${t("employees")} (${e("tenant")}, ${e("status")});
create index if not exists employees_manager_idx on ${t("employees")} (${e("manager")}) where ${e("manager")} is not null;${addExtraColumns(t("employees"), ctx.extraColumns("employees", RESERVED))}
${lockTable(t("employees"), { read: true })}
drop policy if exists employees_read on ${t("employees")};
create policy employees_read on ${t("employees")} for select to authenticated
using (${ctx.scope.check(e("tenant"), n.read)} or ${e("user")} = (select auth.uid()));

-- Private details stay out of the directory: readable with
-- employees.view_sensitive and by the employee.
create table if not exists ${t("privateDetails")} (
  ${p("employee")} uuid primary key references ${t("employees")} (${e("id")}) on delete cascade,
  ${p("tenant")} ${ctx.idType} not null,
  ${p("user")} uuid,
  ${p("nationalId")} text check (${p("nationalId")} is null or length(${p("nationalId")}) <= 64),
  ${p("iban")} text check (${p("iban")} is null or ${p("iban")} ~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{8,30}$'),
  ${p("birthDate")} date,
  ${p("personalEmail")} text check (${p("personalEmail")} is null or length(${p("personalEmail")}) <= 320),
  ${p("phone")} text check (${p("phone")} is null or length(${p("phone")}) <= 40),
  ${p("address")} jsonb check (${p("address")} is null or jsonb_typeof(${p("address")}) = 'object'),
  ${p("emergencyContacts")} jsonb not null default '[]' check (jsonb_typeof(${p("emergencyContacts")}) = 'array'),
  ${p("offboardedAt")} timestamptz,
  ${p("anonymizedAt")} timestamptz,
  ${p("updatedAt")} timestamptz not null default now(),
  ${p("updatedBy")} uuid
);
create index if not exists employee_private_details_user_idx on ${t("privateDetails")} (${p("user")}) where ${p("user")} is not null;
${lockTable(t("privateDetails"), { read: true })}
drop policy if exists employee_private_details_read on ${t("privateDetails")};
create policy employee_private_details_read on ${t("privateDetails")} for select to authenticated
using (${ctx.scope.check(p("tenant"), n.sensitive)} or ${p("user")} = (select auth.uid()));

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
);
create index if not exists employee_contracts_employee_idx on ${t("contracts")} (${k("employee")}, ${k("startsOn")} desc);
${lockTable(t("contracts"), { read: true })}
drop policy if exists employee_contracts_read on ${t("contracts")};
create policy employee_contracts_read on ${t("contracts")} for select to authenticated
using (${ctx.scope.check(k("tenant"), n.sensitive)} or exists (
  select 1 from ${t("employees")} x where x.${e("id")} = ${k("employee")} and x.${e("user")} = (select auth.uid())));
`;
}

/** The manager guard, and the user id the private details mirror. */
function triggersSql(ctx: ModuleContext, n: EmployeeNames): string {
  const { t } = n;
  const e = (column: string): string => n.c("employees", column);
  const mirror =
    ctx.hasTable("privateDetails") && ctx.has("privateDetails", "user")
      ? `
-- The private details carry the employee's user, so the employee reads them.
create or replace function better_supabase.bs_employee_user_mirror()
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
drop trigger if exists bs_employee_user_mirror on ${t("employees")};
create trigger bs_employee_user_mirror after update of ${e("user")} on ${t("employees")}
for each row execute function better_supabase.bs_employee_user_mirror();
`
      : "";
  return `
-- A manager is an employee of the same organization and never one of the
-- employee's own reports, so the org chart stays a tree.
create or replace function better_supabase.bs_employee_manager_guard()
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
drop trigger if exists bs_employee_manager_guard on ${t("employees")};
create trigger bs_employee_manager_guard before insert or update of ${e("manager")} on ${t("employees")}
for each row execute function better_supabase.bs_employee_manager_guard();
${mirror}`;
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") {
    return "";
  }
  const keys = moduleOperations("employees");
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
  };
  return `${schemaPreamble(ctx)}
-- Employees: the people an organization employs, with or without an
-- account, their manager, team and status; private details and contracts
-- behind employees.view_sensitive.
${tablesSql(ctx, names)}${triggersSql(ctx, names)}${employeeFunctions(ctx, names)}${sensitiveFunctions(ctx, names)}`;
}

function contract(ctx: ModuleContext): readonly ModuleContractFunction[] {
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

export const EMPLOYEES: ModuleDefinition = {
  name: "employees",
  scopes: ["tenant"],
  title: "Employees",
  description:
    "Employees with or without an account, a manager, team, job title, employment type and status, an org chart, offboarding, and private details and contracts behind employees.view_sensitive.",
  requires: ["tenant", "access"],
  integrates: ["outbox", "relations", "hiring"],
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
