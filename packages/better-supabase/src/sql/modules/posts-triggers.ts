import type { ModuleContext } from "../context.ts";

import { SERVICE_CALLER, triggerGrant } from "../shared.ts";
import { postsSql } from "./posts-sql.ts";

/** The trigger functions of the posts module, listed as internal. */
export const POST_TRIGGERS = [
  "posts_moderated",
  "posts_removed",
  "posts_reply_guard",
  "posts_replied",
] as const;

/**
 * Keeps posts in step with the blocks they sit on: the moderation item's
 * status, the moderation item's removal, and the reply count and lock of the
 * post's comment thread.
 */
export function postTriggers(ctx: ModuleContext): string {
  const q = postsSql(ctx);
  const { fn, p, posts, subject, moderation, messaging } = q;
  const items = moderation.table("items");
  const mi = (column: string): string => moderation.col("items", column);
  const conversations = messaging.table("conversations");

  const mc = (column: string): string => messaging.col("conversations", column);

  const messages = messaging.table("messages");
  const mm = (column: string): string => messaging.col("messages", column);

  return `-- Projects a post's moderation item onto the post. A moderator's decision
-- records post.moderated.
create or replace function ${fn("posts_moderated")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${posts}%rowtype;
begin
  update ${posts} x set ${p("moderation")} = new.${mi("status")}
  where x.${p("id")}::text = new.${mi("subjectId")} and x.${p("tenant")} = new.${mi("tenant")}
    and x.${p("moderation")} is distinct from new.${mi("status")}
  returning * into v_row;
  if v_row.${p("id")} is not null and new.${mi("decidedAt")} is not null then
    ${q.record("post.moderated", "v_row", false)}
  end if;
  return null;
end;
$$;
${triggerGrant(`${fn("posts_moderated")}()`)}
drop trigger if exists ${ctx.trigger("posts_moderated")} on ${items};
create trigger ${ctx.trigger("posts_moderated")}
  after update of ${mi("status")}, ${mi("decidedAt")} on ${items}
  for each row when (new.${mi("subjectType")} = ${subject})
  execute function ${fn("posts_moderated")}();

-- A deleted post takes its moderation item with it.
create or replace function ${fn("posts_removed")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from ${items} x
  where x.${mi("tenant")} = old.${p("tenant")} and x.${mi("subjectType")} = ${subject} and x.${mi("subjectId")} = old.${p("id")}::text;
  return null;
end;
$$;
${triggerGrant(`${fn("posts_removed")}()`)}
drop trigger if exists ${ctx.trigger("posts_removed")} on ${posts};
create trigger ${ctx.trigger("posts_removed")}
  after delete on ${posts}
  for each row execute function ${fn("posts_removed")}();

-- Refuses a reply on a locked, merged or hidden post, unless a moderator
-- writes it.
create or replace function ${fn("posts_reply_guard")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_post ${posts}%rowtype;
begin
  select x.* into v_post
  from ${conversations} c
  join ${posts} x on x.${p("id")}::text = c.${mc("subjectId")} and x.${p("tenant")} = c.${mc("tenant")}
  where c.${mc("id")} = new.${mm("conversation")} and c.${mc("subjectType")} = ${subject};
  if v_post.${p("id")} is null then
    return new;
  end if;
  if (v_post.${p("lockedAt")} is not null or v_post.${p("mergedInto")} is not null or v_post.${p("moderation")} <> 'visible')
    and not (${SERVICE_CALLER} or ${ctx.can("tenant", `v_post.${p("tenant")}`, q.moderate)}) then
    ${q.forbidden("the post is locked")}
  end if;
  return new;
end;
$$;
${triggerGrant(`${fn("posts_reply_guard")}()`)}
drop trigger if exists ${ctx.trigger("posts_reply_guard")} on ${messages};
create trigger ${ctx.trigger("posts_reply_guard")}
  before insert on ${messages}
  for each row execute function ${fn("posts_reply_guard")}();

-- Counts a post's sent, undeleted replies and moves its last activity.
create or replace function ${fn("posts_replied")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update ${posts} x set
    ${p("replyCount")} = (
      select count(*) from ${messages} m
      where m.${mm("conversation")} = new.${mm("conversation")}
        and m.${mm("sentAt")} is not null and m.${mm("deletedAt")} is null
    ),
    ${p("lastActivityAt")} = greatest(x.${p("lastActivityAt")}, coalesce(new.${mm("sentAt")}, x.${p("lastActivityAt")}))
  from ${conversations} c
  where c.${mc("id")} = new.${mm("conversation")} and c.${mc("subjectType")} = ${subject}
    and x.${p("id")}::text = c.${mc("subjectId")} and x.${p("tenant")} = c.${mc("tenant")};
  return null;
end;
$$;
${triggerGrant(`${fn("posts_replied")}()`)}
drop trigger if exists ${ctx.trigger("posts_replied")} on ${messages};
create trigger ${ctx.trigger("posts_replied")}
  after insert or update of ${mm("sentAt")}, ${mm("deletedAt")} on ${messages}
  for each row execute function ${fn("posts_replied")}();
`;
}
