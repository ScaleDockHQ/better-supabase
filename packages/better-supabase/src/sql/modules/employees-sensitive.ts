import type { BlockSqlContext } from "../context.ts";
import type { EmployeeNames } from "./employees-functions.ts";

import { ISO_4217_MINOR_UNITS } from "../../commerce/iso4217.ts";
import { sqlString } from "../../core/template.ts";
import { int8Text } from "../money-sql.ts";
import {
  fail,
  insertExtraColumns,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import {
  denyOverlaps,
  editableContracts,
  FLAT_DETAILS,
  flatDetails,
  majorSalary,
  overlappingContracts,
} from "./employees-options.ts";

function minorUnits(code: string): string {
  const whens = Object.entries(ISO_4217_MINOR_UNITS)
    .filter(([, units]) => units !== 2)
    .map(
      ([currency, units]) =>
        `when ${sqlString(currency)} then ${String(units)}`,
    )
    .join(" ");

  return `(case ${code} ${whens} else 2 end)`;
}

interface Detail {
  /** The camelCase key of `attrs`. */
  readonly key: string;
  /** The logical column. */
  readonly column: string;
  /**
   * The value from the text expression `v` (`attrs ->> key`) or the jsonb `j`
   * (`attrs -> key`).
   */
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

const NESTED: Readonly<
  Record<(typeof FLAT_DETAILS)[number], readonly [string, string]>
> = {
  addressLine1: ["address", "{address,line1}"],
  addressLine2: ["address", "{address,line2}"],
  postalCode: ["address", "{address,postalCode}"],
  city: ["address", "{address,city}"],
  region: ["address", "{address,region}"],
  country: ["address", "{address,country}"],
  emergencyName: ["emergencyContacts", "{emergencyContacts,0,name}"],
  emergencyPhone: ["emergencyContacts", "{emergencyContacts,0,phone}"],
  emergencyRelation: ["emergencyContacts", "{emergencyContacts,0,relation}"],
};

const ADDRESS_KEYS: Readonly<Record<string, string>> = {
  addressLine1: "line1",
  addressLine2: "line2",
  postalCode: "postalCode",
  city: "city",
  region: "region",
  country: "country",
};

const CONTACT_KEYS: Readonly<Record<string, string>> = {
  emergencyName: "name",
  emergencyPhone: "phone",
  emergencyRelation: "relation",
};

/**
 * Private details and the contract history, when their tables exist: the
 * employee and holders of employees.view_sensitive read them.
 */
export function sensitiveFunctions(
  ctx: BlockSqlContext,
  n: EmployeeNames,
): string {
  const e = (column: string): string => n.c("employees", column);
  const employees = n.t("employees");

  const reader = (alias: string): string =>
    `(${n.service} or ${ctx.scope.can(`${alias}.${e("tenant")}`, n.sensitive)} or coalesce(${alias}.${e("user")} = auth.uid(), false))`;

  const load = (fnName: string, arg: string, allowed: string): string => `
  select * into v_employee from ${employees} x where x.${e("id")} = ${fnName}.${arg};
  if v_employee.${e("id")} is null or not ${allowed} then
    ${fail("EMPLOYEE_NOT_FOUND", "no such employee whose details you can see", "P0002")}
  end if;`;

  const contractReader = (alias: string): string =>
    `(${n.service} or ${ctx.scope.can(`${alias}.${e("tenant")}`, n.contractsRead)} or coalesce(${alias}.${e("user")} = auth.uid(), false))`;

  return `${privateSql(ctx, n, reader, load)}${contractsSql(ctx, n, contractReader, load)}`;
}

type Reader = (alias: string) => string;

type Loader = (fnName: string, arg: string, allowed: string) => string;

function privateSql(
  ctx: BlockSqlContext,
  n: EmployeeNames,
  reader: Reader,
  load: Loader,
): string {
  if (!ctx.hasTable("privateDetails")) {
    return "";
  }

  const p = (column: string): string => n.c("privateDetails", column);
  const has = (column: string): boolean => ctx.has("privateDetails", column);
  const e = (column: string): string => n.c("employees", column);
  const table = n.t("privateDetails");

  const flat = flatDetails(ctx)
    ? FLAT_DETAILS.filter((logical) => has(logical))
    : [];

  const pairs = (
    keys: Readonly<Record<string, string>>,
    alias: string,
  ): string =>
    flat
      .filter((logical) => Object.hasOwn(keys, logical))
      .map(
        (logical) =>
          `${sqlString(keys[logical] ?? logical)}, ${alias}.${p(logical)}`,
      )
      .join(", ");

  const json = (alias: string): string => {
    const address = pairs(ADDRESS_KEYS, alias);
    const contact = pairs(CONTACT_KEYS, alias);

    const parts = [
      ...(address === "" || has("address")
        ? []
        : [
            `'address', nullif(jsonb_strip_nulls(jsonb_build_object(${address})), '{}'::jsonb)`,
          ]),
      ...(contact === "" || has("emergencyContacts")
        ? []
        : [
            `'emergency_contacts', case when ${flat.includes("emergencyName") ? `${alias}.${p("emergencyName")} is null` : "true"} then '[]'::jsonb else jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(${contact}))) end`,
          ]),
    ];

    return parts.length === 0
      ? ctx.rowJson("privateDetails", alias)
      : `(${ctx.rowJson("privateDetails", alias)} || jsonb_build_object(${parts.join(", ")}))`;
  };

  const sets = [
    ...DETAILS.filter((detail) => has(detail.column)).map((detail) => {
      const key = sqlString(detail.key);

      return `${p(detail.column)} = case when save_employee_private_details.attrs ? ${key} then ${detail.value(`save_employee_private_details.attrs ->> ${key}`, `save_employee_private_details.attrs -> ${key}`)} else x.${p(detail.column)} end`;
    }),
    ...flat.map((logical) => {
      const [parent, path] = NESTED[logical];
      const attrs = "save_employee_private_details.attrs";

      const nested = has(parent)
        ? ""
        : ` when ${attrs} ? ${sqlString(parent)} then nullif(trim(${attrs} #>> ${sqlString(path)}), '')`;

      return `${p(logical)} = case when ${attrs} ? ${sqlString(logical)} then nullif(trim(${attrs} ->> ${sqlString(logical)}), '')${nested} else x.${p(logical)} end`;
    }),
    ...(has("updatedAt") ? [`${p("updatedAt")} = now()`] : []),
    ...(has("updatedBy") ? [`${p("updatedBy")} = auth.uid()`] : []),
  ];

  const user = has("user");

  const extras = ctx.extraColumns(
    "privateDetails",
    [],
    "privateDetailsExtraColumns",
  );

  const fields = "(save_employee_private_details.attrs -> 'fields')";
  const required = insertExtraColumns(table, extras, fields);

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
  return ${json("v_row")};
end;
$$;
${userGrant(`${n.fn("employee_private_details")}(uuid)`)}

-- Saves the keys attrs sets: nationalId, iban, birthDate, personalEmail,
-- phone, address (an object) and emergencyContacts (a list); null clears
-- one.${extras.length === 0 ? "" : " fields sets the extra columns."} The employee edits their own details too.
create or replace function ${n.fn("save_employee_private_details")}(employee uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_employee ${n.t("employees")};
  v_row ${table};
begin${load("save_employee_private_details", "employee", n.privateDetailsWrite === undefined ? reader("v_employee") : `(${n.service} or (${ctx.scope.can(`v_employee.${e("tenant")}`, n.sensitive)} and ${ctx.scope.can(`v_employee.${e("tenant")}`, n.privateDetailsWrite)}) or coalesce(v_employee.${e("user")} = auth.uid(), false))`)}
  if jsonb_typeof(coalesce(save_employee_private_details.attrs, '{}')) <> 'object' then
    ${fail("EMPLOYEE_PRIVATE_INVALID", "attrs must be an object", "22023")}
  end if;
  insert into ${table} (${p("employee")}, ${p("tenant")}${user ? `, ${p("user")}` : ""}${required.columns})
  values (v_employee.${e("id")}, v_employee.${e("tenant")}${user ? `, v_employee.${e("user")}` : ""}${required.values})
  on conflict (${p("employee")}) do nothing;
  begin
    update ${table} x set ${sets.join(",\n      ")}
    where x.${p("employee")} = v_employee.${e("id")}
    returning * into v_row;${writeExtraColumns(table, extras, fields, `x.${p("employee")} = v_employee.${e("id")}`, "v_row").replaceAll("\n  ", "\n    ")}
  exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    ${fail("EMPLOYEE_PRIVATE_INVALID", "a private detail has an invalid value", "22023")}
  end;
  return ${json("v_row")};
end;
$$;
${userGrant(`${n.fn("save_employee_private_details")}(uuid, jsonb)`)}
`;
}

function contractsSql(
  ctx: BlockSqlContext,
  n: EmployeeNames,
  reader: Reader,
  load: Loader,
): string {
  if (!ctx.hasTable("contracts")) {
    return "";
  }

  const k = (column: string): string => n.c("contracts", column);
  const has = (column: string): boolean => ctx.has("contracts", column);
  const e = (column: string): string => n.c("employees", column);
  const table = n.t("contracts");

  const salary = has("salary");
  const currency = has("currency");
  const major = majorSalary(ctx);

  const exponent = (code: string): string =>
    currency ? minorUnits(code) : "2";

  const minorText = (alias: string, value: string): string =>
    major
      ? `(${value} * power(10, ${exponent(currency ? `${alias}.${k("currency")}` : "null")}))::bigint::text`
      : `${value}::text`;

  const json = (alias: string): string =>
    ctx.rowJson("contracts", alias, {
      as: { salary: (value) => minorText(alias, value) },
    });

  const row = (alias: string): string =>
    salary
      ? major
        ? `${json(alias)} || jsonb_build_object(${sqlString(k("salary").replaceAll('"', ""))}, ${minorText(alias, `${alias}.${k("salary")}`)})`
        : `${json(alias)} || ${int8Text(alias, [k("salary")])}`
      : json(alias);

  const salaryValue = (minor: string, code: string): string =>
    major
      ? `(${minor})::numeric / power(10, ${exponent(code)})`
      : `(${minor})::bigint`;

  const arg = (key: string): string =>
    `add_employee_contract.attrs ->> ${sqlString(key)}`;

  const extras = ctx.extraColumns("contracts", [], "contractExtraColumns");
  const fields = "(add_employee_contract.attrs -> 'fields')";
  const required = insertExtraColumns(table, extras, fields);

  const columns = [
    k("tenant"),
    k("employee"),
    k("startsOn"),
    k("endsOn"),
    k("hoursPerWeek"),
    ...(salary ? [k("salary")] : []),
    ...(currency ? [k("currency")] : []),
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
    ...(salary
      ? [salaryValue(arg("salary"), `upper(${arg("currency")})`)]
      : []),
    ...(currency ? [`upper(${arg("currency")})`] : []),
    ...(has("salaryPeriod")
      ? [ctx.cast("contracts", "salaryPeriod", arg("salaryPeriod"))]
      : []),
    ...(has("note") ? [`nullif(trim(${arg("note")}), '')`] : []),
    ...(has("createdBy") ? ["auth.uid()"] : []),
  ];

  const insertWith = (skip: string | undefined): string =>
    `insert into ${table} (${columns.filter((column) => column !== skip).join(", ")}${required.columns})
    values (${values.filter((_, index) => columns[index] !== skip).join(", ")}${required.values})
    returning * into v_row;`;

  const insert =
    currency && !ctx.owns("contracts")
      ? `if add_employee_contract.attrs ? 'currency' then
      ${insertWith(undefined).replaceAll("\n    ", "\n      ")}
    else
      ${insertWith(k("currency")).replaceAll("\n    ", "\n      ")}
    end if;`
      : insertWith(undefined);

  const updated = ctx.record({
    type: "employee.updated",
    payload: `jsonb_build_object('organizationId', v_employee.${e("tenant")}, 'employeeId', v_employee.${e("id")}, 'subjectType', 'employee', 'subjectId', v_employee.${e("id")}::text, 'name', ${n.name("v_employee")}, 'userId', v_employee.${e("user")}, 'fields', jsonb_build_array('contract'))`,
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
begin${load("add_employee_contract", "employee", contractWriter(ctx, n, "v_employee"))}${denyOverlaps(ctx) ? lockEmployee(n, "v_employee") : ""}
  begin
    v_starts := (${arg("startsOn")})::date;
    if v_starts is null then
      ${fail("EMPLOYEE_CONTRACT_INVALID", "a contract needs a start date", "22023")}
    end if;${
      overlappingContracts(ctx) || denyOverlaps(ctx)
        ? ""
        : `
    if exists (select 1 from ${table} x where x.${k("employee")} = v_employee.${e("id")} and x.${k("startsOn")} >= v_starts) then
      ${fail("EMPLOYEE_CONTRACT_OVERLAP", "a new contract starts after the latest one", "22023")}
    end if;
    update ${table} x set ${k("endsOn")} = v_starts - 1
    where x.${k("employee")} = v_employee.${e("id")} and (x.${k("endsOn")} is null or x.${k("endsOn")} >= v_starts);`
    }
    ${insert}${writeExtraColumns(table, extras, fields, `x.${k("id")} = v_row.${k("id")}`, "v_row").replaceAll("\n  ", "\n    ")}${overlapCheck(ctx, n, table, "v_row")}
  exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
    ${fail("EMPLOYEE_CONTRACT_INVALID", "a contract field has an invalid value", "22023")}
  end;
  ${updated}
  return ${row("v_row")};
end;
$$;
${userGrant(`${n.fn("add_employee_contract")}(uuid, jsonb)`)}
${editableContracts(ctx) ? editContractsSql(ctx, n, { table, k, has, row, updated, extras, salaryValue }) : ""}`;
}

/**
 * With contractOverlap "deny": locks the employee, then fails when the contract
 * in alias overlaps another of theirs.
 */
function overlapCheck(
  ctx: BlockSqlContext,
  n: EmployeeNames,
  table: string,
  alias: string,
): string {
  if (!denyOverlaps(ctx)) {
    return "";
  }

  const k = (column: string): string => n.c("contracts", column);

  const range = (row: string): string =>
    `daterange(${row}.${k("startsOn")}, ${row}.${k("endsOn")}, '[]')`;

  return `
    if exists (select 1 from ${table} x where x.${k("employee")} = ${alias}.${k("employee")} and x.${k("id")} <> ${alias}.${k("id")} and ${range("x")} && ${range(alias)}) then
      ${fail("EMPLOYEE_CONTRACT_OVERLAP", "the contract overlaps another one", "22023")}
    end if;`;
}

const lockEmployee = (n: EmployeeNames, alias: string): string =>
  `
  perform 1 from ${n.t("employees")} x where x.${n.c("employees", "id")} = ${alias}.${n.c("employees", "id")} for update;`;

function contractWriter(
  ctx: BlockSqlContext,
  n: EmployeeNames,
  alias: string,
): string {
  const tenant = `${alias}.${n.c("employees", "tenant")}`;

  return n.contractsWrite === undefined
    ? `(${n.service} or (${ctx.scope.can(tenant, n.write)} and ${ctx.scope.can(tenant, n.sensitive)}))`
    : `(${n.service} or ${ctx.scope.can(tenant, n.contractsWrite)})`;
}

interface ContractNames {
  readonly table: string;
  readonly k: (column: string) => string;
  readonly has: (column: string) => boolean;
  readonly row: (alias: string) => string;
  readonly updated: string;
  readonly extras: ReturnType<BlockSqlContext["extraColumns"]>;
  readonly salaryValue: (minor: string, code: string) => string;
}

function editContractsSql(
  ctx: BlockSqlContext,
  n: EmployeeNames,
  names: ContractNames,
): string {
  const { table, k, has, row, updated, extras, salaryValue } = names;
  const e = (column: string): string => n.c("employees", column);
  const attrs = "update_employee_contract.attrs";

  const patch = (logical: string, key: string, value: string): string =>
    `${k(logical)} = case when ${attrs} ? ${sqlString(key)} then ${value} else x.${k(logical)} end`;

  const text = (key: string): string => `${attrs} ->> ${sqlString(key)}`;

  const sets = [
    patch("startsOn", "startsOn", `(${text("startsOn")})::date`),
    patch("endsOn", "endsOn", `(${text("endsOn")})::date`),
    patch("hoursPerWeek", "hoursPerWeek", `(${text("hoursPerWeek")})::numeric`),
    ...(has("salary")
      ? [
          patch(
            "salary",
            "salary",
            salaryValue(
              text("salary"),
              has("currency")
                ? `coalesce(upper(${text("currency")}), x.${k("currency")})`
                : "null",
            ),
          ),
        ]
      : []),
    ...(has("currency")
      ? [
          `${k("currency")} = case when ${attrs} ? 'currency' then upper(${text("currency")})${ctx.owns("contracts") ? ` when ${attrs} ? 'salary' and ${text("salary")} is null then null` : ""} else x.${k("currency")} end`,
        ]
      : []),
    ...(has("salaryPeriod")
      ? [
          patch(
            "salaryPeriod",
            "salaryPeriod",
            ctx.cast("contracts", "salaryPeriod", text("salaryPeriod")),
          ),
        ]
      : []),
    ...(has("note")
      ? [patch("note", "note", `nullif(trim(${text("note")}), '')`)]
      : []),
  ];

  const allowed = (alias: string): string => contractWriter(ctx, n, alias);

  const load = (fnName: string): string => `
  select * into v_row from ${table} x where x.${k("id")} = ${fnName}.contract;
  select * into v_employee from ${n.t("employees")} x where x.${e("id")} = v_row.${k("employee")};
  if v_row.${k("id")} is null or v_employee.${e("id")} is null or not ${allowed("v_employee")} then
    ${fail("EMPLOYEE_CONTRACT_NOT_FOUND", "no such contract you can change", "P0002")}
  end if;`;

  return `
-- Changes the keys attrs sets on a contract: startsOn, endsOn, hoursPerWeek,
-- salary with currency, salaryPeriod, note and fields. Needs
-- employees.write and employees.view_sensitive.
create or replace function ${n.fn("update_employee_contract")}(contract uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_employee ${n.t("employees")};
  v_row ${table};
begin${load("update_employee_contract")}${denyOverlaps(ctx) ? lockEmployee(n, "v_employee") : ""}
  if jsonb_typeof(coalesce(${attrs}, '{}')) <> 'object' then
    ${fail("EMPLOYEE_CONTRACT_INVALID", "attrs must be an object", "22023")}
  end if;
  if ${attrs} ? 'startsOn' and ${text("startsOn")} is null then
    ${fail("EMPLOYEE_CONTRACT_INVALID", "a contract needs a start date", "22023")}
  end if;
  begin
    update ${table} x set ${sets.join(",\n      ")}
    where x.${k("id")} = v_row.${k("id")}
    returning * into v_row;${writeExtraColumns(table, extras, `(${attrs} -> 'fields')`, `x.${k("id")} = v_row.${k("id")}`, "v_row").replaceAll("\n  ", "\n    ")}${overlapCheck(ctx, n, table, "v_row")}
  exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
    ${fail("EMPLOYEE_CONTRACT_INVALID", "a contract field has an invalid value", "22023")}
  end;
  ${updated}
  return ${row("v_row")};
end;
$$;
${userGrant(`${n.fn("update_employee_contract")}(uuid, jsonb)`)}

-- Deletes a contract. Needs employees.write and employees.view_sensitive.
create or replace function ${n.fn("delete_employee_contract")}(contract uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_employee ${n.t("employees")};
  v_row ${table};
begin${load("delete_employee_contract")}
  delete from ${table} x where x.${k("id")} = v_row.${k("id")};
  ${updated}
  return ${row("v_row")};
end;
$$;
${userGrant(`${n.fn("delete_employee_contract")}(uuid)`)}
`;
}
