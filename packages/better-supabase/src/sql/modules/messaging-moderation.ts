import type { BlockSqlContext } from "../context.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { fail, triggerGrant } from "../shared.ts";
import { moduleOperations } from "./permissions-model.ts";

/**
 * The subject type moderation reports messages under, when both modules are
 * managed: the message entity's name (`message` by default).
 */
export function moderatedMessageType(ctx: BlockSqlContext): string | undefined {
  if (!ctx.installed("messaging") || !ctx.installed("moderation")) {
    return undefined;
  }

  const messaging = ctx.of("messaging");

  if (!messaging.manages || !ctx.of("moderation").manages) {
    return undefined;
  }

  return messaging.resolved.entities["message"]?.to.singular ?? "message";
}

/**
 * On the messages table, with the moderation module: hidden, removed and
 * pending messages stay readable only to their author and moderators, and
 * banned members can't send.
 */
export function messagingModeration(ctx: BlockSqlContext): string {
  const type = moderatedMessageType(ctx);

  if (type === undefined) {
    return "";
  }

  const moderation = ctx.of("moderation");
  const table = ctx.table("messages");
  const c = (column: string): string => ctx.col("messages", column);

  const read = moderation.permission(
    "read",
    moduleOperations("moderation").read,
  );

  const policy = sqlIdent(`${ctx.tableName("messages").name}_moderation`);
  const guard = ctx.fn("messages_moderation_guard");

  return `
drop policy if exists ${policy} on ${table};
create policy ${policy} on ${table} as restrictive for select to authenticated
  using (
    ${c("author")} = (select auth.uid())
    or not ${moderation.fn("moderation_hidden")}(${sqlString(type)}, ${table}.${c("id")}::text)
    or ${moderation.scope.check(`${table}.${c("tenant")}`, read)}
  );

-- Refuses messages from members banned in the organization.
create or replace function ${guard}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if ${moderation.fn("moderation_banned")}(new.${c("tenant")}, new.${c("author")}) then
    ${fail("MODERATION_BANNED", "you are banned in this organization")}
  end if;
  return new;
end;
$$;
${triggerGrant(`${guard}()`)}
drop trigger if exists ${ctx.trigger("messages_moderation_guard")} on ${table};
create trigger ${ctx.trigger("messages_moderation_guard")}
  before insert on ${table}
  for each row execute function ${guard}();
`;
}
