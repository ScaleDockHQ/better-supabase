import type { BlockSqlContext } from "../context.ts";
import type { Machine } from "./state-machine-options.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { fail } from "../shared.ts";

/** Postgres roles a client request runs as; any other role is trusted SQL. */
const CLIENT_ROLES = ["anon", "authenticated"] as const;

/**
 * A new row starts in the initial status or one it moves to in one step, or in
 * a status `insertStatuses` lists (`*` for any). The check runs as the invoker,
 * so a client role is held to it while trusted SQL (a migration, the service
 * role, or a security definer function a signed-in user calls) is not, and an
 * import run may insert any status.
 */
export function insertCheckFunction(
  ctx: BlockSqlContext,
  item: Machine,
): string {
  if (
    item.workflow !== undefined ||
    item.insertStatuses?.includes("*") === true
  ) {
    return "";
  }

  const allowed = [
    ...new Set([
      item.initial,
      ...(item.transitions[item.initial] ?? []),
      ...(item.insertStatuses ?? []),
    ]),
  ];

  return `
create or replace function better_supabase.bsb_insert_status_${item.name}()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if current_user::text = any (array[${CLIENT_ROLES.map(sqlString).join(", ")}])
    and new.${sqlIdent(item.column)}::text not in (${allowed.map(sqlString).join(", ")})
    and not (${ctx.importing()}) then
    ${fail("STATE_TRANSITION_INVALID", "a new record can't start in that status", "22023")}
  end if;
  return new;
end;
$$;
revoke execute on function better_supabase.bsb_insert_status_${item.name}() from public, anon, authenticated;`;
}

/** Attaches the insert check when the machine has one. */
export function insertCheckTrigger(
  item: {
    readonly name: string;
    readonly insertCheck?: boolean;
    readonly insertStatuses?: readonly string[];
  },
  target: string,
): string {
  if (
    item.insertCheck !== true ||
    item.insertStatuses?.includes("*") === true
  ) {
    return "";
  }

  return `
drop trigger if exists bsb_insert_status_${item.name} on ${target};
create trigger bsb_insert_status_${item.name} before insert on ${target}
for each row execute function better_supabase.bsb_insert_status_${item.name}();`;
}
