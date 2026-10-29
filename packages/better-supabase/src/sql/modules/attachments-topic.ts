import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";

const TOPIC = /^[a-z][a-z0-9_-]{0,30}$/;

/** `blocks.attachments.options.topic`, checked. */
export function attachmentsTopicOf(ctx: BlockSqlContext): string {
  const topic = ctx.text("topic", "attachments");

  if (!TOPIC.test(topic)) {
    throw new TypeError(
      "blocks.attachments.options.topic must be a lowercase name of at most 31 characters",
    );
  }

  return topic;
}

/**
 * The trigger that tells `<topic>:<tenant>` which subject's files changed, and
 * the `realtime.messages` policy that lets the tenant's readers join it.
 */
export function attachmentsTopicSql(
  ctx: BlockSqlContext,
  parts: {
    readonly t: string;
    readonly c: (logical: string) => string;
    readonly read: string;
  },
): string {
  const { t, c } = parts;
  const topic = attachmentsTopicOf(ctx);
  const fn = ctx.fn("attachments_changed");

  return `
-- Tells the tenant's topic which subject's files changed. The payload carries
-- ids only; files without a tenant broadcast nothing.
create or replace function ${fn}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t}%rowtype;
begin
  if tg_op = 'DELETE' then
    v_row := old;
  else
    v_row := new;
  end if;
  if v_row.${c("tenant")} is null then
    return null;
  end if;
  ${ctx.broadcast(`${sqlString(`${topic}:`)} || v_row.${c("tenant")}::text`, "'changed'", `jsonb_build_object('subjectType', v_row.${c("subjectType")}, 'subjectId', v_row.${c("subjectId")})`)}
  return null;
end;
$$;
revoke execute on function ${fn}() from public, anon, authenticated;
drop trigger if exists ${ctx.trigger("attachments_changed")} on ${t};
create trigger ${ctx.trigger("attachments_changed")}
  after insert or update or delete on ${t}
  for each row execute function ${fn}();

-- Members join ${topic}:{tenant}; payloads name the subject whose files changed.
do $do$
begin
  if to_regclass('realtime.messages') is not null then
        ${renderPolicy(
          makePolicy({
            table: "realtime.messages",
            name: ctx.trigger("attachments_receive"),
            command: "select",
            roles: ["authenticated"],
            using: `realtime.messages.extension = 'broadcast'
        and (select realtime.topic()) like ${sqlString(`${topic}:%`)}
        and substr((select realtime.topic()), ${String(topic.length + 2)}) in (select x::text from ${ctx.scope.ids(parts.read)} x)`,
          }),
          { drop: true, target: "realtime.messages" },
        )}
  end if;
end;
$do$;
`;
}
