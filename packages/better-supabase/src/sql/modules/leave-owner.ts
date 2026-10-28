import type { BlockSqlContext } from "../context.ts";

import { userGrant } from "../shared.ts";

const WHERE = "blocks.leave.options";

export function leaveByEmployee(ctx: BlockSqlContext): boolean {
  const raw = ctx.option("owner") ?? "user";

  if (raw !== "user" && raw !== "employee") {
    throw new TypeError(`${WHERE}.owner must be "user" or "employee"`);
  }

  return raw === "employee";
}

const mapped = (ctx: BlockSqlContext, table: string, column: string): boolean =>
  typeof ctx.config.columns[table]?.[column] === "string";

export function leaveParts(ctx: BlockSqlContext): boolean {
  const start = mapped(ctx, "requests", "startPart");

  if (start !== mapped(ctx, "requests", "endPart")) {
    throw new TypeError(
      "blocks.leave.columns.requests.startPart and endPart are mapped together",
    );
  }

  if (start && ctx.owns("requests")) {
    throw new TypeError(
      "blocks.leave.columns.requests.startPart and endPart name columns of your own requests table; map tables.requests to it",
    );
  }

  return start;
}

export function leavePartsMapped(ctx: BlockSqlContext): boolean {
  return mapped(ctx, "requests", "startPart");
}

export function leaveBalancesTable(ctx: BlockSqlContext): boolean {
  if (typeof ctx.config.tables["balances"] !== "string") {
    return false;
  }

  if (!ctx.appOwned.includes("balances")) {
    throw new TypeError(
      "blocks.leave.tables.balances names a table the schema doesn't declare; the block reads and adds rows to your table and never creates it",
    );
  }

  return true;
}

export interface LeaveOwner {
  readonly employee: boolean;
  readonly staff: BlockSqlContext | undefined;
  readonly column: string;
  readonly variable: string;
  readonly declare: string;
  readonly resolve: (tenant: string, user: string, employee: string) => string;
  readonly manages: (tenant: string, employee: string) => string;
  readonly exists: (tenant: string, owner: string) => string;
  readonly userOf: (owner: string) => string;
  readonly requester: (row: string) => string;
  readonly mine: string;
  readonly json: (row: string) => string;
  readonly helper: string;
}

export function leaveOwner(ctx: BlockSqlContext): LeaveOwner {
  const employee = leaveByEmployee(ctx);
  const q = (column: string): string => ctx.col("requests", column);

  if (employee && !ctx.installed("employees")) {
    throw new TypeError(`${WHERE}.owner "employee" needs the employees block`);
  }

  if (employee && !ctx.has("requests", "employee")) {
    throw new TypeError(
      `${WHERE}.owner "employee" keeps the employee on every request, so columns.requests.employee can't be null`,
    );
  }

  if (!employee && !ctx.has("requests", "user")) {
    throw new TypeError(
      `blocks.leave.columns.requests.user can be null only with ${WHERE}.owner "employee"`,
    );
  }

  const staff = employee ? ctx.of("employees") : undefined;
  const y = (column: string): string => staff?.col("employees", column) ?? "";
  const employees = staff?.table("employees") ?? "";
  const manager = staff?.has("employees", "manager") === true;
  const fn = ctx.fn("leave_is_mine");
  const members = ctx.of("memberships");

  const userOf = (owner: string): string =>
    employee
      ? `(select lo.${y("user")} from ${employees} lo where lo.${y("id")} = ${owner})`
      : owner;

  return {
    employee,
    staff,
    column: employee ? q("employee") : q("user"),
    variable: employee ? "v_owner" : "v_me",
    declare: employee ? "\n  v_owner uuid;\n  v_user uuid;" : "",
    resolve: (tenant, user, employeeArg) =>
      employee
        ? `if ${employeeArg} is not null then
    select y.${y("id")}, y.${y("user")} into v_owner, v_user from ${employees} y where y.${y("id")} = ${employeeArg} and y.${y("tenant")} = ${tenant};
  else
    select y.${y("id")}, y.${y("user")} into v_owner, v_user from ${employees} y where y.${y("tenant")} = ${tenant} and y.${y("user")} = coalesce(${user}, auth.uid());
  end if;`
        : "",
    manages: (tenant, employeeId) =>
      manager
        ? `exists (select 1 from ${employees} lm join ${employees} lb on lb.${y("id")} = lm.${y("manager")} where lm.${y("id")} = ${employeeId} and lm.${y("tenant")} = ${tenant} and lb.${y("user")} = auth.uid())`
        : "false",
    exists: (tenant, owner) =>
      employee
        ? `exists (select 1 from ${employees} le where le.${y("id")} = ${owner} and le.${y("tenant")} = ${tenant})`
        : `exists (select 1 from ${members.table("memberships")} m where m.${members.col("memberships", "tenant")} = ${tenant} and m.${members.col("memberships", "user")} = ${owner})`,
    userOf,
    requester: (row) =>
      employee ? userOf(`${row}.${q("employee")}`) : `${row}.${q("user")}`,
    mine: employee
      ? `${fn}(${q("tenant")}, ${q("employee")})`
      : `${q("user")} = (select auth.uid())`,
    json: (row) => (employee ? `, 'employeeId', ${row}.${q("employee")}` : ""),
    helper: employee
      ? `
create or replace function ${fn}(tenant ${ctx.idType}, employee uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from ${employees} e${manager ? `\n    left join ${employees} b on b.${y("id")} = e.${y("manager")}` : ""}
    where e.${y("id")} = leave_is_mine.employee and e.${y("tenant")} = leave_is_mine.tenant
      and (e.${y("user")} = auth.uid()${manager ? ` or b.${y("user")} = auth.uid()` : ""})
  )
$$;
${userGrant(`${fn}(${ctx.idType}, uuid)`)}
`
      : "",
  };
}

export function halfDays(
  startsOn: string,
  endsOn: string,
  startPart: string,
  endPart: string,
): { readonly first: string; readonly last: string } {
  return {
    first: `((${startsOn} - date '2000-01-01') * 2 + case when ${startPart} = 'afternoon' then 1 else 0 end)`,
    last: `((${endsOn} - date '2000-01-01') * 2 + case when ${endPart} = 'morning' then 0 else 1 end)`,
  };
}

export function dropSignatures(name: string, types: string): string {
  return `drop function if exists ${name}(${types});
drop function if exists ${name}(${types}, jsonb);`;
}
