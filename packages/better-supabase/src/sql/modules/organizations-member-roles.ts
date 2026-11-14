import type { BlockSqlContext } from "../context.ts";

import { fail } from "../shared.ts";

/**
 * `update_member_roles` (ADR 0853): the role change for many members in one
 * call. Each member goes through `update_member_role` in its own
 * subtransaction, so the checks, event and audit row of the single call apply
 * per member.
 */
export function memberRolesSql(ctx: BlockSqlContext): string {
  const id = ctx.idType;

  return `
-- The role change for many members in one call (ADR 0853). It runs as the
-- caller: update_member_role is the security definer and does the checking,
-- once per distinct member in its own subtransaction, so every check and event
-- of the single call still runs. Returns { succeeded: [id], failed: [{ id,
-- code, message }] }; more than 500 members fail with BULK_TOO_MANY.
create or replace function ${ctx.fn("update_member_roles")}(organization ${id}, members uuid[], role text)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  one uuid;
  succeeded jsonb := '[]'::jsonb;
  failed jsonb := '[]'::jsonb;
  failure_hint text;
  failure_message text;
begin
  if coalesce(cardinality(members), 0) > 500 then
    ${fail("BULK_TOO_MANY", "A bulk call takes at most 500 members", "22023")}
  end if;
  for one in select distinct m from unnest(members) m loop
    begin
      perform ${ctx.fn("update_member_role")}(organization, one, role);
      succeeded := succeeded || to_jsonb(one::text);
    exception when others then
      get stacked diagnostics failure_hint = pg_exception_hint, failure_message = message_text;
      failed := failed || jsonb_build_object('id', one::text, 'code', failure_hint, 'message', failure_message);
    end;
  end loop;
  return jsonb_build_object('succeeded', succeeded, 'failed', failed);
end;
$$;
`;
}
