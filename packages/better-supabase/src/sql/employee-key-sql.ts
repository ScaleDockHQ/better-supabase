import type { BlockSqlContext } from "./context.ts";

import { sqlIdent } from "../core/template.ts";
import { triggerGrant } from "./shared.ts";

/** A table keyed by tenant and user that gains an `employee_id`. */
export interface EmployeeKeyed {
  /** The context of the module that owns the table. */
  readonly owner: BlockSqlContext;
  /** The table's logical name in that module. */
  readonly table: string;
}

/**
 * Adds `employee_id` to a table of rows that belong to a member, keyed by
 * tenant and user: the employee of that organization with that account, or
 * null. A trigger fills it on insert and when the row's user changes, and a
 * trigger on employees keeps it current when an employee's account changes.
 * Existing rows are backfilled. The owning module must be managed, because the
 * column is added to its table.
 */
export function employeeKeySql(
  employees: BlockSqlContext,
  keyed: EmployeeKeyed,
): string {
  const { owner, table } = keyed;

  if (!owner.owns(table)) {
    return "";
  }

  const target = owner.table(table);
  const name = owner.tableName(table).name;
  const r = (column: string): string => owner.col(table, column);
  const e = (column: string): string => employees.col("employees", column);
  const emp = employees.table("employees");
  const fill = `bsb_${name}_employee`;
  const sync = `bsb_${name}_employee_sync`;

  return `
-- ${name}.employee_id: the employee behind the row's user, kept in step with
-- employees by the two triggers below.
alter table ${target} add column if not exists employee_id uuid references ${emp} (${e("id")}) on delete set null;
create index if not exists ${sqlIdent(`${name}_employee_idx`)} on ${target} (employee_id) where employee_id is not null;

create or replace function better_supabase.${fill}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.employee_id := (
    select x.${e("id")} from ${emp} x
    where x.${e("tenant")} = new.${r("tenant")} and x.${e("user")} = new.${r("user")}
  );
  return new;
end;
$$;
${triggerGrant(`better_supabase.${fill}()`)}
drop trigger if exists ${fill} on ${target};
create trigger ${fill} before insert or update of ${r("user")} on ${target}
for each row execute function better_supabase.${fill}();

create or replace function better_supabase.${sync}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and old.${e("user")} is not null then
    update ${target} set employee_id = null
    where employee_id = old.${e("id")} and ${r("user")} is distinct from new.${e("user")};
  end if;
  if new.${e("user")} is not null then
    update ${target} set employee_id = new.${e("id")}
    where ${r("tenant")} = new.${e("tenant")} and ${r("user")} = new.${e("user")}
      and employee_id is distinct from new.${e("id")};
  end if;
  return null;
end;
$$;
${triggerGrant(`better_supabase.${sync}()`)}
drop trigger if exists ${sync} on ${emp};
create trigger ${sync} after insert or update of ${e("user")} on ${emp}
for each row execute function better_supabase.${sync}();
`;
}

/**
 * The upgrade step that adds `employee_id` to rows that exist already and fills
 * it. It runs before the module files, so the column is added here too; `quiet`
 * names triggers of the table to hold off during the backfill.
 */
export function employeeKeyBackfillSql(
  employees: BlockSqlContext,
  keyed: EmployeeKeyed & { readonly quiet?: readonly string[] },
): string {
  const { owner, table } = keyed;

  if (!owner.owns(table)) {
    return "";
  }

  const target = owner.table(table);
  const r = (column: string): string => owner.col(table, column);
  const e = (column: string): string => employees.col("employees", column);
  const emp = employees.table("employees");
  const quiet = keyed.quiet ?? [];

  const toggle = (state: "disable" | "enable"): string =>
    quiet
      .map((trigger) => `alter table ${target} ${state} trigger ${trigger};\n`)
      .join("");

  return `alter table ${target} add column if not exists employee_id uuid references ${emp} (${e("id")}) on delete set null;
${toggle("disable")}update ${target} t set employee_id = x.${e("id")}
from ${emp} x
where x.${e("tenant")} = t.${r("tenant")} and x.${e("user")} = t.${r("user")}
  and t.employee_id is distinct from x.${e("id")};
${toggle("enable")}`;
}
