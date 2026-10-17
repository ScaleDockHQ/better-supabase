import type { ReactionsEvents } from "../../blocks/reactions/events.ts";
import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { fail, schemaPreamble, SERVICE_CALLER, userGrant } from "../shared.ts";
import {
  subjectCascades,
  subjectReadable,
  subjectsOption,
} from "../subjects.ts";
import { OPERATIONS } from "./access-model.ts";

const PAYLOAD = [
  "organizationId",
  "subjectType",
  "subjectId",
  "emoji",
  "actor",
] as const;

const EVENTS: ModuleEvents<ReactionsEvents> = {
  "reaction.added": { subject: "reactions", payload: PAYLOAD },
  "reaction.removed": { subject: "reactions", payload: PAYLOAD },
};

const NAMES: ModuleNames = {
  events: EVENTS,
  hooks: ["before_react", "after_react"],
  options: ["subjects", "topic"],
  tables: {
    reactions: {
      name: "reactions",
      lifecycle: { tenant: "tenant", user: "user", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        actor: "actor",
        user: "user_id",
        emoji: "emoji",
        createdAt: "created_at",
      },
    },
    emoji: {
      name: "custom_emoji",
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        shortcode: "shortcode",
        attachment: "attachment_id",
        url: "url",
        createdBy: "created_by",
        createdAt: "created_at",
      },
    },
  },
};

/** The subject type of a comment from the `comments` module. */
const COMMENT_SUBJECT = "comment";
/** The subject type of an inbox message from the `inbox` module. */
const INBOX_MESSAGE_SUBJECT = "inbox_message";

const TOPIC = /^[a-z][a-z0-9_-]{0,30}$/;
const SHORTCODE = "^:[a-z0-9_+-]{1,32}:$";

function topicOf(ctx: ModuleContext): string {
  const topic = ctx.text("topic", "reactions");
  if (!TOPIC.test(topic)) {
    throw new TypeError(
      "blocks.reactions.options.topic must be a lowercase name of at most 31 characters",
    );
  }
  return topic;
}

/**
 * Whether the caller sees the subject, as a `case` on the subject type. The
 * function that wraps it runs as the caller, so the subject tables' own
 * policies apply.
 */
function visibleCase(
  ctx: ModuleContext,
  args: {
    readonly type: string;
    readonly id: string;
    readonly tenant: string;
  },
): string {
  const subjects = subjectsOption(ctx);
  const whens: string[] = [];
  if (ctx.installed("comments") && ctx.of("comments").mode !== "custom") {
    const comments = ctx.of("comments");
    const cc = (column: string): string => comments.col("comments", column);
    whens.push(
      `    when ${sqlString(COMMENT_SUBJECT)} then exists (select 1 from ${comments.table("comments")} c where c.${cc("id")}::text = ${args.id} and c.${cc("tenant")} = ${args.tenant} and c.${cc("deletedAt")} is null)`,
    );
  }
  if (ctx.installed("inbox") && ctx.of("inbox").mode !== "custom") {
    const inbox = ctx.of("inbox");
    const mc = (column: string): string => inbox.col("messages", column);
    whens.push(
      `    when ${sqlString(INBOX_MESSAGE_SUBJECT)} then exists (select 1 from ${inbox.table("messages")} m where m.${mc("id")}::text = ${args.id} and m.${mc("tenant")} = ${args.tenant})`,
    );
  }
  const rest = subjectReadable(ctx, subjects, args);
  if (whens.length === 0) {
    return rest;
  }
  return `case ${args.type}
${whens.join("\n")}
    else ${rest}
  end`;
}

function inboxBackfill(ctx: ModuleContext): string {
  if (!ctx.manages || !ctx.installed("inbox")) {
    return "";
  }
  const inbox = ctx.of("inbox");
  if (inbox.mode === "custom") {
    return "";
  }
  const mc = (column: string): string => inbox.col("messages", column);
  const c = (column: string): string => ctx.col("reactions", column);
  return `-- Copies the reactions inbox messages kept in their jsonb column, without
-- recording them as new reactions.
select set_config('better_supabase.reactions_backfill', 'on', true);
insert into ${ctx.table("reactions")} (${c("tenant")}, ${c("subjectType")}, ${c("subjectId")}, ${c("actor")}, ${c("user")}, ${c("emoji")})
select m.${mc("tenant")}, ${sqlString(INBOX_MESSAGE_SUBJECT)}, m.${mc("id")}::text, a.actor,
  case when a.actor ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then a.actor::uuid end,
  e.key
from ${inbox.table("messages")} m
cross join lateral jsonb_each(case when jsonb_typeof(m.${mc("reactions")}) = 'object' then m.${mc("reactions")} else '{}'::jsonb end) e
cross join lateral jsonb_array_elements_text(case when jsonb_typeof(e.value) = 'array' then e.value else '[]'::jsonb end) a(actor)
where length(e.key) between 1 and 64 and e.key !~ '\\s' and e.key !~ ${sqlString(SHORTCODE)}
on conflict do nothing;
select set_config('better_supabase.reactions_backfill', '', true);
`;
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") {
    return "";
  }
  const reactions = ctx.table("reactions");
  const emojiTable = ctx.table("emoji");
  const c = (column: string): string => ctx.col("reactions", column);
  const e = (column: string): string => ctx.col("emoji", column);
  const read = ctx.permission("read", OPERATIONS["reactions.read"]);
  const create = ctx.permission("create", OPERATIONS["reactions.create"]);
  const manage = ctx.permission("manage", OPERATIONS["reactions.manage"]);
  const topic = topicOf(ctx);
  const subjects = subjectsOption(ctx);
  const fn = (name: string): string => ctx.fn(name);
  const visible = fn("reaction_subject_visible");
  const name = ctx.tableName("reactions").name;
  const forbidden = fail(
    "REACTION_FORBIDDEN",
    "not allowed to react to this record",
  );
  const event = (type: string, row: string): string =>
    ctx.emit({
      type,
      payload: `jsonb_build_object('organizationId', ${row}.${c("tenant")}, 'subjectType', ${row}.${c("subjectType")}, 'subjectId', ${row}.${c("subjectId")}, 'emoji', ${row}.${c("emoji")}, 'actor', ${row}.${c("actor")})`,
      subject: `'reactions/' || ${row}.${c("id")}::text`,
      tenant: `${row}.${c("tenant")}`,
    });
  const inboxReact = ctx.installed("inbox")
    ? `
  if react.subject_type = ${sqlString(INBOX_MESSAGE_SUBJECT)} then
    perform ${ctx.of("inbox").fn("react_to_message")}(react.subject_id::uuid, react.emoji, coalesce(react.present, true), react.actor);
    return ${fn("reaction_list")}(react.tenant, react.subject_type, react.subject_id);
  end if;`
    : "";
  const insertCheck = ctx.installed("inbox")
    ? ` and ${c("subjectType")} <> ${sqlString(INBOX_MESSAGE_SUBJECT)}`
    : "";
  const tables = ctx.manages
    ? `create table if not exists ${reactions} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType} not null,
  ${c("subjectType")} text not null,
  ${c("subjectId")} text not null,
  ${c("actor")} text not null,
  ${c("user")} uuid,
  ${c("emoji")} text not null check (length(${c("emoji")}) between 1 and 64 and ${c("emoji")} !~ '\\s'),
  ${c("createdAt")} timestamptz not null default now(),
  unique (${c("subjectType")}, ${c("subjectId")}, ${c("actor")}, ${c("emoji")})
);
create index if not exists ${sqlIdent(`${name}_tenant_idx`)} on ${reactions} (${c("tenant")}, ${c("subjectType")}, ${c("subjectId")});
create index if not exists ${sqlIdent(`${name}_user_idx`)} on ${reactions} (${c("user")});
alter table ${reactions} enable row level security;
revoke all on ${reactions} from anon;
grant select, insert, delete on ${reactions} to authenticated;
grant all on ${reactions} to service_role;

create table if not exists ${emojiTable} (
  ${e("id")} uuid primary key default gen_random_uuid(),
  ${e("tenant")} ${ctx.idType} not null,
  ${e("shortcode")} text not null check (${e("shortcode")} ~ '^[a-z0-9_+-]{1,32}$'),
  ${e("attachment")} uuid,
  ${e("url")} text check (${e("url")} ~ '^https://'),
  ${e("createdBy")} uuid,
  ${e("createdAt")} timestamptz not null default now(),
  unique (${e("tenant")}, ${e("shortcode")}),
  check (${e("attachment")} is not null or ${e("url")} is not null)
);
alter table ${emojiTable} enable row level security;
revoke all on ${emojiTable} from anon, authenticated;
grant select on ${emojiTable} to authenticated;
grant all on ${emojiTable} to service_role;
drop policy if exists "custom_emoji_read" on ${emojiTable};
create policy "custom_emoji_read" on ${emojiTable} for select to authenticated
  using (${ctx.scope.check(e("tenant"), read)});
`
    : "";
  return `${schemaPreamble(ctx)}
${tables}
-- Whether the caller sees the subject. It runs as the caller, so the subject
-- tables' policies apply.
create or replace function ${visible}(subject_type text, subject_id text, tenant ${ctx.idType})
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select ${visibleCase(ctx, { type: "reaction_subject_visible.subject_type", id: "reaction_subject_visible.subject_id", tenant: "reaction_subject_visible.tenant" })}
$$;
revoke execute on function ${visible}(text, text, ${ctx.idType}) from public, anon;
grant execute on function ${visible}(text, text, ${ctx.idType}) to authenticated, service_role;

drop policy if exists "reactions_read" on ${reactions};
create policy "reactions_read" on ${reactions} for select to authenticated
  using (${ctx.scope.check(c("tenant"), read)} and ${visible}(${c("subjectType")}, ${c("subjectId")}, ${c("tenant")}));
drop policy if exists "reactions_insert" on ${reactions};
create policy "reactions_insert" on ${reactions} for insert to authenticated
  with check (
    ${c("user")} = (select auth.uid())
    and ${c("actor")} = (select auth.uid())::text
    and ${ctx.scope.check(c("tenant"), create)}${insertCheck}
    and ${visible}(${c("subjectType")}, ${c("subjectId")}, ${c("tenant")})
  );
drop policy if exists "reactions_delete" on ${reactions};
create policy "reactions_delete" on ${reactions} for delete to authenticated
  using (${c("user")} = (select auth.uid())${insertCheck});

drop trigger if exists ${ctx.trigger("reactions_check")} on ${reactions};
drop trigger if exists ${ctx.trigger("reactions_changed")} on ${reactions};

-- A custom emoji's :shortcode: must exist in the reaction's tenant.
create or replace function ${fn("reactions_check")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.${c("emoji")} ~ ${sqlString(SHORTCODE)} and not exists (
    select 1 from ${emojiTable} x
    where x.${e("tenant")} = new.${c("tenant")} and x.${e("shortcode")} = trim(both ':' from new.${c("emoji")})
  ) then
    ${fail("REACTION_INVALID", "unknown custom emoji", "22023")}
  end if;
  return new;
end;
$$;
revoke execute on function ${fn("reactions_check")}() from public, anon, authenticated;
create trigger ${ctx.trigger("reactions_check")}
  before insert on ${reactions}
  for each row execute function ${fn("reactions_check")}();

-- Records reaction.added and reaction.removed, then tells the tenant's topic
-- which subject changed. The payload carries ids only.
create or replace function ${fn("reactions_changed")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${reactions}%rowtype;
begin
  if current_setting('better_supabase.reactions_backfill', true) = 'on' then
    return null;
  end if;
  if tg_op = 'INSERT' then
    v_row := new;
    ${event("reaction.added", "v_row")}
  else
    v_row := old;
    ${event("reaction.removed", "v_row")}
  end if;
  ${ctx.broadcast(`${sqlString(`${topic}:`)} || v_row.${c("tenant")}::text`, "'changed'", `jsonb_build_object('subjectType', v_row.${c("subjectType")}, 'subjectId', v_row.${c("subjectId")})`)}
  return null;
end;
$$;
revoke execute on function ${fn("reactions_changed")}() from public, anon, authenticated;
create trigger ${ctx.trigger("reactions_changed")}
  after insert or delete on ${reactions}
  for each row execute function ${fn("reactions_changed")}();

-- One subject's reactions under the read policy: emoji, count, whether the
-- caller reacted and the first ten actors, most used first.
create or replace function ${fn("reaction_list")}(tenant ${ctx.idType}, subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('emoji', g.emoji, 'count', g.n, 'reacted', g.mine, 'actors', g.actors) order by g.n desc, g.first, g.emoji), '[]'::jsonb)
  from (
    select r.${c("emoji")} as emoji, count(*)::integer as n, min(r.${c("createdAt")}) as first,
      coalesce(bool_or(r.${c("user")} = (select auth.uid())), false) as mine,
      (array_agg(r.${c("actor")} order by r.${c("createdAt")}))[1:10] as actors
    from ${reactions} r
    where r.${c("tenant")} = reaction_list.tenant
      and r.${c("subjectType")} = reaction_list.subject_type
      and r.${c("subjectId")} = reaction_list.subject_id
    group by r.${c("emoji")}
  ) g
$$;
${userGrant(`${fn("reaction_list")}(${ctx.idType}, text, text)`)}

-- Adds (present) or removes the caller's reaction, then returns the
-- subject's reactions. It runs as the caller: the insert and delete
-- policies check the permission and that the caller sees the subject.
-- The service role passes the actor (default 'service').
create or replace function ${fn("react")}(tenant ${ctx.idType}, subject_type text, subject_id text, emoji text, present boolean default true, actor text default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_actor text;
  v_user uuid;
begin${inboxReact}
  if ${SERVICE_CALLER} then
    v_actor := coalesce(react.actor, 'service');
  elsif react.actor is not null then
    ${fail("REACTION_FORBIDDEN", "only the service role reacts for another actor")}
  elsif not (${ctx.can("tenant", "react.tenant", create)} and ${visible}(react.subject_type, react.subject_id, react.tenant)) then
    ${forbidden}
  else
    v_user := (select auth.uid());
    v_actor := v_user::text;
  end if;
  if react.emoji is null or length(react.emoji) not between 1 and 64 or react.emoji ~ '\\s' then
    ${fail("REACTION_INVALID", "emoji must be 1 to 64 characters without spaces", "22023")}
  end if;
  ${ctx.hook("before_react", [
    [ctx.idType, "react.tenant"],
    ["text", "react.subject_type"],
    ["text", "react.subject_id"],
    ["text", "react.emoji"],
    ["boolean", "coalesce(react.present, true)"],
  ])}
  if coalesce(react.present, true) then
    insert into ${reactions} (${c("tenant")}, ${c("subjectType")}, ${c("subjectId")}, ${c("actor")}, ${c("user")}, ${c("emoji")})
    values (react.tenant, react.subject_type, react.subject_id, v_actor, v_user, react.emoji)
    on conflict do nothing;
  else
    delete from ${reactions} r
    where r.${c("subjectType")} = react.subject_type
      and r.${c("subjectId")} = react.subject_id
      and r.${c("tenant")} = react.tenant
      and r.${c("actor")} = v_actor
      and r.${c("emoji")} = react.emoji;
  end if;
  ${ctx.hook("after_react", [
    [ctx.idType, "react.tenant"],
    ["text", "react.subject_type"],
    ["text", "react.subject_id"],
    ["text", "react.emoji"],
    ["boolean", "coalesce(react.present, true)"],
  ])}
  return ${fn("reaction_list")}(react.tenant, react.subject_type, react.subject_id);
end;
$$;
${userGrant(`${fn("react")}(${ctx.idType}, text, text, text, boolean, text)`)}

-- The reactions of many subjects of one type, as { subjectId: [...] }.
create or replace function ${fn("reaction_summary")}(tenant ${ctx.idType}, subject_type text, subject_ids text[])
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(s.id, ${fn("reaction_list")}(reaction_summary.tenant, reaction_summary.subject_type, s.id)), '{}'::jsonb)
  from (select distinct unnest(reaction_summary.subject_ids[1:200]) as id) s
$$;
${userGrant(`${fn("reaction_summary")}(${ctx.idType}, text, text[])`)}

create or replace function ${fn("save_custom_emoji")}(tenant ${ctx.idType}, shortcode text, attachment_id uuid default null, url text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${emojiTable}%rowtype;
begin
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", "save_custom_emoji.tenant", manage)}) then
    ${fail("REACTION_FORBIDDEN", "not allowed to manage custom emoji")}
  end if;
  insert into ${emojiTable} (${e("tenant")}, ${e("shortcode")}, ${e("attachment")}, ${e("url")}, ${e("createdBy")})
  values (save_custom_emoji.tenant, lower(trim(both ':' from save_custom_emoji.shortcode)), save_custom_emoji.attachment_id, save_custom_emoji.url, auth.uid())
  on conflict (${e("tenant")}, ${e("shortcode")}) do update
    set ${e("attachment")} = excluded.${e("attachment")}, ${e("url")} = excluded.${e("url")}
  returning * into v_row;
  return jsonb_build_object('id', v_row.${e("id")}, 'shortcode', v_row.${e("shortcode")}, 'attachmentId', v_row.${e("attachment")}, 'url', v_row.${e("url")}, 'createdAt', v_row.${e("createdAt")});
end;
$$;
${userGrant(`${fn("save_custom_emoji")}(${ctx.idType}, text, uuid, text)`)}

-- Deletes a custom emoji and the reactions that used it.
create or replace function ${fn("delete_custom_emoji")}(emoji_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${emojiTable}%rowtype;
begin
  select * into v_row from ${emojiTable} x where x.${e("id")} = delete_custom_emoji.emoji_id;
  if not found then
    return false;
  end if;
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", `v_row.${e("tenant")}`, manage)}) then
    ${fail("REACTION_FORBIDDEN", "not allowed to manage custom emoji")}
  end if;
  delete from ${reactions} r
    where r.${c("tenant")} = v_row.${e("tenant")} and r.${c("emoji")} = ':' || v_row.${e("shortcode")} || ':';
  delete from ${emojiTable} x where x.${e("id")} = v_row.${e("id")};
  return true;
end;
$$;
${userGrant(`${fn("delete_custom_emoji")}(uuid)`)}

create or replace function ${fn("list_custom_emoji")}(tenant ${ctx.idType})
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x.${e("id")}, 'shortcode', x.${e("shortcode")}, 'attachmentId', x.${e("attachment")}, 'url', x.${e("url")}, 'createdAt', x.${e("createdAt")}) order by x.${e("shortcode")}), '[]'::jsonb)
  from ${emojiTable} x
  where x.${e("tenant")} = list_custom_emoji.tenant
$$;
${userGrant(`${fn("list_custom_emoji")}(${ctx.idType})`)}

-- Members join ${topic}:{tenant}; payloads name the subject that changed.
do $do$
begin
  if to_regclass('realtime.messages') is not null then
    drop policy if exists ${ctx.trigger("reactions_receive")} on realtime.messages;
    create policy ${ctx.trigger("reactions_receive")} on realtime.messages for select to authenticated
      using (
        realtime.messages.extension = 'broadcast'
        and (select realtime.topic()) like ${sqlString(`${topic}:%`)}
        and substr((select realtime.topic()), ${String(topic.length + 2)}) in (select x::text from ${ctx.scope.ids(read)} x)
      );
  end if;
end;
$do$;
${subjectCascades(ctx, subjects, `delete from ${reactions} r where r.${c("subjectType")} = v_type and r.${c("subjectId")} = v_id;`)}
`;
}

function contract(): readonly ModuleContractFunction[] {
  return [
    {
      name: "react",
      args: ["{id}", "text", "text", "text", "boolean", "text"],
      returns: "jsonb",
    },
    {
      name: "reaction_summary",
      args: ["{id}", "text", "text[]"],
      returns: "jsonb",
    },
  ];
}

export const REACTIONS: ModuleDefinition = {
  internal: ["reaction_subject_visible"],
  name: "reactions",
  scopes: ["tenant"],
  title: "Reactions",
  description:
    "Emoji reactions on any subject, comments and inbox messages, with per-tenant custom emoji, counts per subject under the subject's own read rules and a realtime topic per tenant.",
  requires: ["tenant", "access"],
  integrates: ["outbox", "comments", "inbox"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  topics: (ctx) => [`${topicOf(ctx)}:{tenant}`],
  contract,
  build,
  data: inboxBackfill,
};
