import type { DoctorContext, FindingInput } from "./rules.ts";

import { catalogOf } from "./shared.ts";

/**
 * An app's own `team_members` table that has the employee column while its user
 * column is `not null` (BS631). The teams block then clears the user of a row
 * whose employee stays, and adds an employee without an account with no user,
 * and both fail.
 */
export function requiredTeamMemberUser(context: DoctorContext): FindingInput[] {
  const { blocks, sql } = context.config;
  const teams = blocks["teams"];
  const employees = blocks["employees"];

  if (
    teams === undefined ||
    employees === undefined ||
    teams.mode === "custom" ||
    employees.mode === "custom"
  ) {
    return [];
  }

  const mapped = teams.tables?.["members"];
  const columns = teams.columns?.["members"];
  const employee = columns?.["employee"];

  if (typeof mapped !== "string" || employee === null) {
    return [];
  }

  const schema = teams.schema ?? sql.blockDefaults?.schema ?? "better_supabase";
  const table = mapped.includes(".") ? mapped : `${schema}.${mapped}`;
  const userColumn = columns?.["user"] ?? "user_id";
  const employeeColumn = employee ?? "employee_id";

  const found = catalogOf(context).tables.find(
    (entry) => `${entry.schema}.${entry.name}` === table,
  );

  const user = found?.columns.find((column) => column.name === userColumn);

  if (
    user === undefined ||
    user.nullable ||
    !found?.columns.some((column) => column.name === employeeColumn)
  ) {
    return [];
  }

  return [
    {
      message: `${table} has ${employeeColumn}, so teams keeps employees on it, but ${userColumn} is not null. Removing a member or a user who has an employee record, and adding an employee without an account, then fail. Drop ${employeeColumn} (or map blocks.teams.columns.members.employee to null) to keep user-only members, or give the table its own primary key, drop the not null on ${userColumn} and add unique indexes on (team, ${userColumn}) and (team, ${employeeColumn}).`,
      target: `${table}.${userColumn}`,
    },
  ];
}
