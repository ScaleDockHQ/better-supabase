import type { BlockSqlContext } from "../context.ts";

import { userGrant } from "../shared.ts";

export function ownerIsEmployee(ctx: BlockSqlContext, where: string): boolean {
  const raw = ctx.option("owner") ?? "user";

  if (raw !== "user" && raw !== "employee") {
    throw new TypeError(`${where}.owner must be "user" or "employee"`);
  }

  return raw === "employee";
}

export interface RecordOwner {
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

export function recordOwner(
  ctx: BlockSqlContext,
  spec: {
    readonly block: string;
    readonly table: string;
    readonly noun: string;
    readonly helper: string;
  },
): RecordOwner {
  const where = `blocks.${spec.block}.options`;
  const employee = ownerIsEmployee(ctx, where);
  const q = (column: string): string => ctx.col(spec.table, column);

  if (employee && !ctx.installed("employees")) {
    throw new TypeError(`${where}.owner "employee" needs the employees block`);
  }

  if (employee && !ctx.has(spec.table, "employee")) {
    throw new TypeError(
      `${where}.owner "employee" keeps the employee on every ${spec.noun}, so columns.${spec.table}.employee can't be null`,
    );
  }

  if (!employee && !ctx.has(spec.table, "user")) {
    throw new TypeError(
      `blocks.${spec.block}.columns.${spec.table}.user can be null only with ${where}.owner "employee"`,
    );
  }

  const staff = employee ? ctx.of("employees") : undefined;
  const y = (column: string): string => staff?.col("employees", column) ?? "";
  const employees = staff?.table("employees") ?? "";
  const manager = staff?.has("employees", "manager") === true;
  const fn = ctx.fn(spec.helper);
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
    where e.${y("id")} = ${spec.helper}.employee and e.${y("tenant")} = ${spec.helper}.tenant
      and (e.${y("user")} = auth.uid()${manager ? ` or b.${y("user")} = auth.uid()` : ""})
  )
$$;
${userGrant(`${fn}(${ctx.idType}, uuid)`)}
`
      : "",
  };
}
