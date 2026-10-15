import type { ModuleContext } from "../context.ts";
import type { EmployeeNames } from "./employees-functions.ts";

import { sqlString } from "../../core/template.ts";
import { canIn, fail, userGrant } from "../shared.ts";

interface Detail {
  /** The camelCase key of `attrs`. */
  readonly key: string;
  /** The logical column. */
  readonly column: string;
  /** The value from the text expression `v` (`attrs ->> key`) or the jsonb `j` (`attrs -> key`). */
  readonly value: (v: string, j: string) => string;
}

const DETAILS: readonly Detail[] = [
  {
    key: "nationalId",
    column: "nationalId",
    value: (v) => `nullif(trim(${v}), '')`,
  },
  {
    key: "iban",
    column: "iban",
    value: (v) => `nullif(upper(replace(${v}, ' ', '')), '')`,
  },
  { key: "birthDate", column: "birthDate", value: (v) => `(${v})::date` },
  {
    key: "personalEmail",
    column: "personalEmail",
    value: (v) => `nullif(trim(${v}), '')`,
  },
  { key: "phone", column: "phone", value: (v) => `nullif(trim(${v}), '')` },
  {
    key: "address",
    column: "address",
    value: (_v, j) =>
      `case when jsonb_typeof(${j}) = 'null' then null else ${j} end`,
  },
  {
    key: "emergencyContacts",
    column: "emergencyContacts",
    value: (_v, j) =>
      `coalesce(case when jsonb_typeof(${j}) = 'null' then null else ${j} end, '[]'::jsonb)`,
  },
];

/**
 * Private details and the contract history, when their tables exist: the
 * employee and holders of employees.view_sensitive read them.
 */
export function sensitiveFunctions(
  ctx: ModuleContext,
  n: EmployeeNames,
): string {
  const e = (column: string): string => n.c("employees", column);
  const employees = n.t("employees");
  const reader = (alias: string): string =>
    `(${n.service} or ${canIn(`${alias}.${e("tenant")}`, n.sensitive)} or ${alias}.${e("user")} = auth.uid())`;
  const load = (fnName: string, arg: string, allowed: string): string => `
  select * into v_employee from ${employees} x where x.${e("id")} = ${fnName}.${arg};
  if v_employee.${e("id")} is null or not ${allowed} then
    ${fail("EMPLOYEE_NOT_FOUND", "no such employee whose details you can see", "P0002")}
  end if;`;
  return `${privateSql(ctx, n, reader, load)}${contractsSql(ctx, n, reader, load)}`;
}

type Reader = (alias: string) => string;
type Loader = (fnName: string, arg: string, allowed: string) => string;

function privateSql(
  ctx: ModuleContext,
  n: EmployeeNames,
  reader: Reader,
  load: Loader,
): string {
  if (!ctx.hasTable("privateDetails")) return "";
  const p = (column: string): string => n.c("privateDetails", column);
  const has = (column: string): boolean => ctx.has("privateDetails", column);
  const e = (column: string): string => n.c("employees", column);
  const table = n.t("privateDetails");
  const sets = [
    ...DETAILS.filter((detail) => has(detail.column)).map((detail) => {
      const key = sqlString(detail.key);
      return `${p(detail.column)} = case when save_employee_private_details.attrs ? ${key} then ${detail.value(`save_employee_private_details.attrs ->> ${key}`, `save_employee_private_details.attrs -> ${key}`)} else x.${p(detail.column)} end`;
    }),
    ...(has("updatedAt") ? [`${p("updatedAt")} = now()`] : []),
    ...(has("updatedBy") ? [`${p("updatedBy")} = auth.uid()`] : []),
  ];
  const user = has("user");
  return `
-- An employee's private details, or null when none are saved.
create or replace function ${n.fn("employee_private_details")}(employee uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_employee ${n.t("employees")};
  v_row ${table};
begin${load("employee_private_details", "employee", reader("v_employee"))}
  select * into v_row from ${table} x where x.${p("employee")} = v_employee.${e("id")};
  if v_row.${p("employee")} is null then
    return null;
  end if;
  return to_jsonb(v_row);
end;
$$;
${userGrant(`${n.fn("employee_private_details")}(uuid)`)}

-- Saves the keys attrs sets: nationalId, iban, birthDate, personalEmail,
-- phone, address (an object) and emergencyContacts (a list); null clears
-- one. The employee edits their own details too.
create or replace function ${n.fn("save_employee_private_details")}(employee uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_employee ${n.t("employees")};
  v_row ${table};
begin${load("save_employee_private_details", "employee", reader("v_employee"))}
  if jsonb_typeof(coalesce(save_employee_private_details.attrs, '{}')) <> 'object' then
    ${fail("EMPLOYEE_PRIVATE_INVALID", "attrs must be an object", "22023")}
  end if;
  insert into ${table} (${p("employee")}, ${p("tenant")}${user ? `, ${p("user")}` : ""})
  values (v_employee.${e("id")}, v_employee.${e("tenant")}${user ? `, v_employee.${e("user")}` : ""})
  on conflict (${p("employee")}) do nothing;
  begin
    update ${table} x set ${sets.join(",\n      ")}
    where x.${p("employee")} = v_employee.${e("id")}
    returning * into v_row;
  exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    ${fail("EMPLOYEE_PRIVATE_INVALID", "a private detail has an invalid value", "22023")}
  end;
  return to_jsonb(v_row);
end;
$$;
${userGrant(`${n.fn("save_employee_private_details")}(uuid, jsonb)`)}
`;
}

function contractsSql(
  ctx: ModuleContext,
  n: EmployeeNames,
  reader: Reader,
  load: Loader,
): string {
  if (!ctx.hasTable("contracts")) return "";
  const k = (column: string): string => n.c("contracts", column);
  const has = (column: string): boolean => ctx.has("contracts", column);
  const e = (column: string): string => n.c("employees", column);
  const table = n.t("contracts");
  const salaryKey = sqlString(k("salary").replaceAll('"', ""));
  const row = (alias: string): string =>
    `to_jsonb(${alias}) || jsonb_build_object(${salaryKey}, ${alias}.${k("salary")}::text)`;
  const arg = (key: string): string =>
    `add_employee_contract.attrs ->> ${sqlString(key)}`;
  const columns = [
    k("tenant"),
    k("employee"),
    k("startsOn"),
    k("endsOn"),
    k("hoursPerWeek"),
    k("salary"),
    k("currency"),
    ...(has("salaryPeriod") ? [k("salaryPeriod")] : []),
    ...(has("note") ? [k("note")] : []),
    ...(has("createdBy") ? [k("createdBy")] : []),
  ];
  const values = [
    `v_employee.${e("tenant")}`,
    `v_employee.${e("id")}`,
    "v_starts",
    `(${arg("endsOn")})::date`,
    `(${arg("hoursPerWeek")})::numeric`,
    `(${arg("salary")})::bigint`,
    `upper(${arg("currency")})`,
    ...(has("salaryPeriod") ? [arg("salaryPeriod")] : []),
    ...(has("note") ? [`nullif(trim(${arg("note")}), '')`] : []),
    ...(has("createdBy") ? ["auth.uid()"] : []),
  ];
  const updated = ctx.record({
    type: "employee.updated",
    payload: `jsonb_build_object('organizationId', v_employee.${e("tenant")}, 'employeeId', v_employee.${e("id")}, 'subjectType', 'employee', 'subjectId', v_employee.${e("id")}::text, 'name', v_employee.${e("name")}, 'fields', jsonb_build_array('contract'))`,
    subject: `'employees/' || v_employee.${e("id")}::text`,
    tenant: `v_employee.${e("tenant")}::text`,
    audit: false,
  });
  return `
-- An employee's contracts, the newest first. Salaries are minor units as
-- text.
create or replace function ${n.fn("employee_contracts")}(employee uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_employee ${n.t("employees")};
begin${load("employee_contracts", "employee", reader("v_employee"))}
  return (select coalesce(jsonb_agg(${row("x")} order by x.${k("startsOn")} desc), '[]'::jsonb)
    from ${table} x where x.${k("employee")} = v_employee.${e("id")});
end;
$$;
${userGrant(`${n.fn("employee_contracts")}(uuid)`)}

-- Adds a contract: startsOn (required), endsOn, hoursPerWeek, salary
-- (minor units) with currency, salaryPeriod (hour, week, month or year)
-- and note. It starts after the latest contract, which ends the day
-- before. Needs employees.write and employees.view_sensitive.
create or replace function ${n.fn("add_employee_contract")}(employee uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_employee ${n.t("employees")};
  v_row ${table};
  v_starts date;
begin${load("add_employee_contract", "employee", `(${n.service} or (${canIn(`v_employee.${e("tenant")}`, n.write)} and ${canIn(`v_employee.${e("tenant")}`, n.sensitive)}))`)}
  begin
    v_starts := (${arg("startsOn")})::date;
    if v_starts is null then
      ${fail("EMPLOYEE_CONTRACT_INVALID", "a contract needs a start date", "22023")}
    end if;
    if exists (select 1 from ${table} x where x.${k("employee")} = v_employee.${e("id")} and x.${k("startsOn")} >= v_starts) then
      ${fail("EMPLOYEE_CONTRACT_OVERLAP", "a new contract starts after the latest one", "22023")}
    end if;
    update ${table} x set ${k("endsOn")} = v_starts - 1
    where x.${k("employee")} = v_employee.${e("id")} and (x.${k("endsOn")} is null or x.${k("endsOn")} >= v_starts);
    insert into ${table} (${columns.join(", ")})
    values (${values.join(", ")})
    returning * into v_row;
  exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
    ${fail("EMPLOYEE_CONTRACT_INVALID", "a contract field has an invalid value", "22023")}
  end;
  ${updated}
  return ${row("v_row")};
end;
$$;
${userGrant(`${n.fn("add_employee_contract")}(uuid, jsonb)`)}
`;
}
