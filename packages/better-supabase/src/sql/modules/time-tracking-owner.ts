import type { BlockSqlContext } from "../context.ts";
import type { Subject } from "../subjects.ts";
import type { StatusTimesheetOwner } from "./time-tracking-status.ts";

import { sqlIdent } from "../../core/template.ts";
import { userGrant } from "../shared.ts";
import {
  boundRowSubject,
  boundSubjects,
  boundSubjectValues,
} from "../subject-columns.ts";

const WHERE = "blocks.time-tracking.options";

export interface EntrySubjects {
  readonly bound: boolean;
  readonly rowSubject: (row: string) => {
    readonly type: string;
    readonly id: string;
  };
  readonly subjectColumns: readonly string[];
  readonly setSubject: (type: string, id: string, indent: string) => string;
  readonly subjectInsert: string;
  readonly subjectInsertValues: string;
}

export function entrySubjects(
  ctx: BlockSqlContext,
  subjects: readonly (readonly [string, Subject])[],
): EntrySubjects {
  const bound = boundSubjects(subjects, "blocks.time-tracking.on");

  const poly =
    ctx.has("entries", "subjectType") && ctx.has("entries", "subjectId");

  if (bound.length > 0 && ctx.owns("entries")) {
    throw new TypeError(
      "blocks.time-tracking.on.<type>.column names a column of your own entries table; map tables.entries to it",
    );
  }

  if (
    !poly &&
    (ctx.has("entries", "subjectType") ||
      ctx.has("entries", "subjectId") ||
      bound.length === 0 ||
      bound.length !== subjects.length)
  ) {
    throw new TypeError(
      "blocks.time-tracking.columns.entries.subjectType and subjectId can be null only together, with a column in every blocks.time-tracking.on.<type>",
    );
  }

  const entriesName = ctx.tableName("entries");
  const entriesQualified = `${sqlIdent(entriesName.schema)}.${sqlIdent(entriesName.name)}`;

  const polyColumns = poly
    ? {
        type: ctx.col("entries", "subjectType"),
        id: ctx.col("entries", "subjectId"),
      }
    : undefined;

  const rowSubject = (
    row: string,
  ): { readonly type: string; readonly id: string } =>
    bound.length === 0
      ? {
          type: `${row}.${ctx.col("entries", "subjectType")}`,
          id: `${row}.${ctx.col("entries", "subjectId")}`,
        }
      : boundRowSubject(bound, polyColumns, row);

  const subjectColumns = [
    ...(polyColumns ? [polyColumns.type, polyColumns.id] : []),
    ...bound.map((subject) => sqlIdent(subject.column)),
  ];

  const setSubject = (type: string, id: string, indent: string): string =>
    [
      ...(polyColumns
        ? [
            `v_row.${polyColumns.type} := ${type};`,
            `v_row.${polyColumns.id} := ${id};`,
          ]
        : []),
      ...boundSubjectValues(bound, entriesQualified, type, id).map(
        ([column, value]) => `v_row.${column} := ${value};`,
      ),
    ].join(`\n${indent}`);

  const subjectInsert = subjectColumns.join(", ");

  const subjectInsertValues = subjectColumns
    .map((column) => `v_row.${column}`)
    .join(", ");

  return {
    bound: bound.length > 0,
    rowSubject,
    subjectColumns,
    setSubject,
    subjectInsert,
    subjectInsertValues,
  };
}

/**
 * Whether the entries table keeps a duration (`seconds` and `runningSince`)
 * instead of `endedAt`.
 */
export const durationEntries = (ctx: BlockSqlContext): boolean =>
  !ctx.has("entries", "endedAt");

/** When entry row `alias` ended, null while it runs. */
export function entryEnded(ctx: BlockSqlContext, alias: string): string {
  return durationEntries(ctx)
    ? `(case when ${alias}.${ctx.col("entries", "runningSince")} is null then ${alias}.${ctx.col("entries", "startedAt")} + make_interval(secs => coalesce(${alias}.${ctx.col("entries", "seconds")}, 0)) end)`
    : `${alias}.${ctx.col("entries", "endedAt")}`;
}

export function byEmployee(ctx: BlockSqlContext): boolean {
  const raw = ctx.option("owner") ?? "user";

  if (raw !== "user" && raw !== "employee") {
    throw new TypeError(`${WHERE}.owner must be "user" or "employee"`);
  }

  return raw === "employee";
}

export interface TimeOwner {
  readonly employeeMode: boolean;
  readonly staff: BlockSqlContext | undefined;
  readonly eOwner: string;
  readonly tOwner: string;
  readonly ownerVar: string;
  readonly sheetUser: boolean;
  readonly myEmployee: (tenant: string) => string;
  readonly employeeOf: (tenant: string, employee: string) => string;
  readonly employeeOfUser: (tenant: string, user: string) => string;
  readonly ownedByMe: (row: string) => string;
  readonly sheetUserJson: (row: string) => string;
  readonly status: StatusTimesheetOwner;
  readonly helper: string;
}

export function timeOwner(
  ctx: BlockSqlContext,
  statusMode: boolean,
): TimeOwner {
  const fn = (name: string): string => ctx.fn(name);
  const employeeMode = byEmployee(ctx);

  if (employeeMode && !statusMode) {
    throw new TypeError(
      `${WHERE}.owner "employee" keeps timesheets in a status column, so it needs ${WHERE}.approvals: false`,
    );
  }

  if (employeeMode && !ctx.installed("employees")) {
    throw new TypeError(`${WHERE}.owner "employee" needs the employees block`);
  }

  if (
    employeeMode &&
    (!ctx.has("entries", "employee") || !ctx.has("timesheets", "employee"))
  ) {
    throw new TypeError(
      `${WHERE}.owner "employee" keeps the employee on every row, so columns.entries.employee and columns.timesheets.employee can't be null`,
    );
  }

  if (!employeeMode && !ctx.has("timesheets", "user")) {
    throw new TypeError(
      `blocks.time-tracking.columns.timesheets.user can be null only with ${WHERE}.owner "employee"`,
    );
  }

  const staff = employeeMode ? ctx.of("employees") : undefined;

  const eOwner = employeeMode
    ? ctx.col("entries", "employee")
    : ctx.col("entries", "user");

  const tOwner = employeeMode
    ? ctx.col("timesheets", "employee")
    : ctx.col("timesheets", "user");

  const ownerVar = employeeMode ? "v_owner" : "v_me";
  const sheetUser = ctx.has("timesheets", "user");

  const myEmployee = (tenant: string): string =>
    staff === undefined
      ? "null::uuid"
      : `(select y.${staff.col("employees", "id")} from ${staff.table("employees")} y where y.${staff.col("employees", "tenant")} = ${tenant} and y.${staff.col("employees", "user")} = auth.uid())`;

  const employeeOf = (tenant: string, employee: string): string =>
    staff === undefined
      ? ""
      : `select y.${staff.col("employees", "id")}, y.${staff.col("employees", "user")} into v_owner, v_user from ${staff.table("employees")} y where y.${staff.col("employees", "id")} = ${employee} and y.${staff.col("employees", "tenant")} = ${tenant};`;

  const employeeOfUser = (tenant: string, user: string): string =>
    staff === undefined
      ? ""
      : `select y.${staff.col("employees", "id")}, y.${staff.col("employees", "user")} into v_owner, v_user from ${staff.table("employees")} y where y.${staff.col("employees", "tenant")} = ${tenant} and y.${staff.col("employees", "user")} = ${user};`;

  const ownedByMe = (row: string): string =>
    employeeMode
      ? `(coalesce(${row}.${ctx.col("entries", "user")} = auth.uid(), false) or ${row}.${ctx.col("entries", "employee")} = ${myEmployee(`${row}.${ctx.col("entries", "tenant")}`)})`
      : `coalesce(${row}.${ctx.col("entries", "user")} = auth.uid(), false)`;

  const sheetUserJson = (row: string): string =>
    `'userId', ${sheetUser ? `${row}.${ctx.col("timesheets", "user")}` : "null::uuid"}${employeeMode ? `, 'employeeId', ${row}.${ctx.col("timesheets", "employee")}` : ""}`;

  const status: StatusTimesheetOwner = {
    employee: employeeMode,
    entries: eOwner,
    timesheets: tOwner,
    sheetUser,
    mine: myEmployee,
    ofUser: (tenant: string, user: string) =>
      staff === undefined
        ? "null::uuid"
        : `(select y.${staff.col("employees", "id")} from ${staff.table("employees")} y where y.${staff.col("employees", "tenant")} = ${tenant} and y.${staff.col("employees", "user")} = ${user})`,
    userOf: (employee: string) =>
      staff === undefined
        ? "null::uuid"
        : `(select y.${staff.col("employees", "user")} from ${staff.table("employees")} y where y.${staff.col("employees", "id")} = ${employee})`,
    exists: (tenant: string, employee: string) =>
      staff === undefined
        ? "false"
        : `exists (select 1 from ${staff.table("employees")} y where y.${staff.col("employees", "id")} = ${employee} and y.${staff.col("employees", "tenant")} = ${tenant})`,
    json: sheetUserJson,
  };

  const helper = employeeMode
    ? `
create or replace function ${fn("time_is_my_employee")}(tenant ${ctx.idType}, employee uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return time_is_my_employee.employee is not null and time_is_my_employee.employee = ${myEmployee("time_is_my_employee.tenant")};
end;
$$;
${userGrant(`${fn("time_is_my_employee")}(${ctx.idType}, uuid)`)}
`
    : "";

  return {
    employeeMode,
    staff,
    eOwner,
    tOwner,
    ownerVar,
    sheetUser,
    myEmployee,
    employeeOf,
    employeeOfUser,
    ownedByMe,
    sheetUserJson,
    status,
    helper,
  };
}

const IDENT = /^[a-z_][a-z0-9_$]*$/u;

/**
 * `options.lockedColumns`: the entry columns a submitted or approved week
 * refuses to change, as logical names or the table's own column names. By
 * default the ones that change logged time: start, end or duration, subject,
 * owner and rate.
 */
export function lockedColumns(
  ctx: BlockSqlContext,
  subjectColumns: readonly string[],
  employeeMode: boolean,
  logical: readonly string[],
): readonly string[] {
  const raw = ctx.option("lockedColumns");
  const e = (column: string): string => ctx.col("entries", column);

  if (raw === undefined) {
    return [
      ...new Set([
        e("startedAt"),
        ...(durationEntries(ctx)
          ? [e("seconds"), e("runningSince")]
          : [e("endedAt")]),
        ...subjectColumns,
        e("user"),
        ...(employeeMode ? [e("employee")] : []),
        e("rate"),
        e("rateCurrency"),
      ]),
    ];
  }

  if (
    !Array.isArray(raw) ||
    !raw.every(
      (column) =>
        typeof column === "string" &&
        ((logical.includes(column) && ctx.has("entries", column)) ||
          IDENT.test(column)),
    )
  ) {
    throw new TypeError(
      `${WHERE}.lockedColumns takes entry columns: logical names such as startedAt, or the table's own column names`,
    );
  }

  return [
    ...new Set(
      raw.map((column: string) =>
        logical.includes(column) ? e(column) : sqlIdent(column),
      ),
    ),
  ];
}
