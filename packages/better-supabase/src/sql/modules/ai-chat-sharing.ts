import type { BlockSqlContext } from "../context.ts";
import type { AiChatNames } from "./ai-chat.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  raise,
  replaceColumnCheck,
  sha256HexSql,
  SERVICE_CALLER,
  userGrant,
} from "../shared.ts";
import { markShared, participantJson } from "./ai-chat-participants.ts";
import {
  asText,
  columnOr,
  variableConflict,
  writtenPairs,
} from "./ai-chat-tables.ts";

const UUID = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";

const VISIBILITIES = ["private", "organization", "shared"]
  .map(sqlString)
  .join(", ");

/**
 * The party kinds `add_ai_chat_party` writes, with the participant column that
 * holds each and the SQL type of the target.
 */
const PARTIES = [
  { kind: "team", column: "team", cast: "uuid" },
  { kind: "customer", column: "customerUser", cast: "uuid" },
  { kind: "external", column: "email", cast: "text" },
] as const;

/**
 * Teams, customers and external emails as participants, the share summaries and
 * the rotatable live link of a chat.
 */
export function aiChatSharing(
  ctx: BlockSqlContext,
  names: AiChatNames,
): string {
  const fn = (name: string): string => ctx.fn(name);
  const { t, perm } = names;
  const ch = names.c.chats;
  const pa = names.c.participants;
  const lk = names.c.links;
  const kinds = ctx.has("participants", "kind");

  const owns = `not found or not (${SERVICE_CALLER} or coalesce(v_chat.owner = (select auth.uid()), false))`;

  const mayShare = `  if not ${SERVICE_CALLER} and ${names.tenantless ? "v_chat.tenant is not null and " : ""}not ${ctx.scope.can("v_chat.tenant", perm.share)} then
    ${raise("You may not share chats here", "42501", "AI_CHAT_FORBIDDEN")}
  end if;`;

  const loadChat = (name: string, chat: string): string =>
    `select x.${ch.id} as id, x.${ch.owner} as owner, x.${ch.tenant} as tenant into v_chat
  from ${t.chats} x where x.${ch.id} = ${name}.${chat} for update;
  if ${owns} then
    ${raise("No chat %", "P0002", "AI_CHAT_NOT_FOUND", `${name}.${chat}`)}
  end if;`;

  const token = (chat: string, salt: string): string =>
    `${chat}::text || '.' || ${sha256HexSql(`convert_to(${salt} || ${chat}::text, 'utf8')`)}`;

  const party = (): string => {
    if (!kinds) {
      return "";
    }

    const branches = PARTIES.filter(({ column }) =>
      ctx.has("participants", column),
    );

    const inserts = branches
      .map(({ kind, column, cast }, index) => {
        const [columns, values] = writtenPairs(ctx, "participants", [
          ["chat", "v_chat.id"],
          ["kind", ctx.cast("participants", "kind", sqlString(kind))],
          [
            column,
            kind === "external"
              ? "lower(btrim(add_ai_chat_party.party))"
              : `add_ai_chat_party.party::${cast}`,
          ],
          ["role", ctx.cast("participants", "role", "v_role")],
          ["addedBy", "auth.uid()"],
        ]);

        const target = kind === "external" ? `lower(${pa.email})` : pa[column];

        return `${index === 0 ? "if" : "elsif"} add_ai_chat_party.party_kind = ${sqlString(kind)} then
    insert into ${t.participants} (${columns})
    values (${values})
    on conflict (${pa.chat}, ${target}) where ${pa.kind} = ${sqlString(kind)} do update set ${pa.role} = excluded.${pa.role}
    returning * into v_row;`;
      })
      .join("\n  ");

    const team = names.teamMember("v_team", "auth.uid()");

    return `-- Adds a team (every member reads the chat), a customer (a user with guest
-- access to the chat) or an external email (reads only through the live
-- link) to a chat, or changes its role. party_kind is team, customer or
-- external; party is the team id, the customer's user id or the email. The
-- chat becomes shared.
create or replace function ${fn("add_ai_chat_party")}(chat uuid, party_kind text, party text, participant_role text default 'viewer')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
${variableConflict(ctx, "participants", "chats")}
declare
  v_chat record;
  v_role text := coalesce(add_ai_chat_party.participant_role, 'viewer');
  v_team uuid;
  v_row ${t.participants};
begin
  ${loadChat("add_ai_chat_party", "chat")}
${mayShare}
  if v_role not in ('viewer', 'editor') then
    ${raise("A participant is a viewer or an editor, not %", "22023", "AI_CHAT_INVALID", "v_role")}
  end if;
  if add_ai_chat_party.party_kind not in (${branches.map(({ kind }) => sqlString(kind)).join(", ")}) or add_ai_chat_party.party is null then
    ${raise("A party is a team, a customer or an external email, not %", "22023", "AI_CHAT_INVALID", "add_ai_chat_party.party_kind")}
  end if;
  if add_ai_chat_party.party_kind = 'team' then
${
  team === undefined
    ? `    ${raise("Team participants need the teams module or options.teamMembership", "22023", "AI_CHAT_INVALID")}`
    : `    v_team := add_ai_chat_party.party::uuid;
    if v_chat.tenant is null then
      ${raise("A chat outside an organization has no teams", "22023", "AI_CHAT_INVALID")}
    end if;`
}
  elsif add_ai_chat_party.party_kind = 'customer' then
    if v_chat.tenant is null then
      ${raise("A customer needs a chat in an organization", "22023", "AI_CHAT_INVALID")}
    end if;
    if add_ai_chat_party.party::uuid = v_chat.owner then
      ${raise("The owner already takes part in chat %", "22023", "AI_CHAT_INVALID", "add_ai_chat_party.chat")}
    end if;
  elsif add_ai_chat_party.party !~* '^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$' then
    ${raise("% is not an email address", "22023", "AI_CHAT_INVALID", "add_ai_chat_party.party")}
  end if;
  ${inserts}
  end if;
  ${markShared(ctx, names, "v_chat.id")}
  perform ${fn("ai_chat_notify")}(v_chat.id, v_chat.owner, 'participant.added', jsonb_build_object('kind', add_ai_chat_party.party_kind, 'role', v_role), true);
  return ${participantJson(ctx, "v_row")};
end;
$$;
${userGrant(`${fn("add_ai_chat_party")}(uuid, text, text, text)`)}

-- Removes a team, customer or external email from a chat: its owner or the
-- service role. Returns whether the party took part.
create or replace function ${fn("remove_ai_chat_party")}(chat uuid, party_kind text, party text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
${variableConflict(ctx, "participants", "chats")}
declare
  v_chat record;
  v_count integer;
begin
  ${loadChat("remove_ai_chat_party", "chat")}
  delete from ${t.participants} x
  where x.${pa.chat} = v_chat.id and x.${pa.kind}::text = remove_ai_chat_party.party_kind
    and (${branches.map(({ kind, column, cast }) => `(remove_ai_chat_party.party_kind = ${sqlString(kind)} and ${kind === "external" ? `lower(x.${pa[column]}) = lower(btrim(remove_ai_chat_party.party))` : `x.${pa[column]} = remove_ai_chat_party.party::${cast}`})`).join(" or ")});
  get diagnostics v_count = row_count;
  if v_count > 0 then
    perform ${fn("ai_chat_notify")}(v_chat.id, v_chat.owner, 'participant.removed', jsonb_build_object('kind', remove_ai_chat_party.party_kind), true);
  end if;
  return v_count > 0;
end;
$$;
${userGrant(`${fn("remove_ai_chat_party")}(uuid, text, text)`)}

`;
  };

  const users = `select c.${ch.owner} as id, 'owner' as role, 0 as ord from ${t.chats} c where c.${ch.id} = x.${ch.id}
        union all
        select pa.${pa.user}, pa.${pa.role}::text, 1 from ${t.participants} pa
        where pa.${pa.chat} = x.${ch.id}${kinds ? ` and pa.${pa.kind}::text = 'user'` : ""}`;

  const teamCount = kinds
    ? `(select count(*) from ${t.participants} pa where pa.${pa.chat} = x.${ch.id} and pa.${pa.kind}::text = 'team')`
    : "0";

  return `${party()}-- For each chat the caller reads: its people with the owner first, how many
-- teams take part and whether it has a live link.
create or replace function ${fn("ai_chat_share_summaries")}(chats uuid[])
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'chat_id', x.${ch.id},
    'users', (
      select coalesce(jsonb_agg(jsonb_build_object('user_id', u.id, 'role', u.role) order by u.ord), '[]'::jsonb)
      from (
        ${users}
      ) u
    ),
    'team_count', ${teamCount},
    'has_link', exists (select 1 from ${t.links} l where l.${lk.chat} = x.${ch.id})
  )), '[]'::jsonb)
  from ${t.chats} x
  where x.${ch.id} = any (coalesce(ai_chat_share_summaries.chats, '{}'::uuid[]))
    and ${fn("ai_chat_can_read")}(x.${ch.id});
$$;
${userGrant(`${fn("ai_chat_share_summaries")}(uuid[])`)}

-- The live link of a chat: its owner, or the service role, creates it once
-- and gets { chat_id, token } again on every call. Anyone holding the token
-- reads the chat's active branch through get_ai_chat_by_link. The chat
-- becomes shared; making it private again turns the link off.
create or replace function ${fn("create_ai_chat_link")}(chat uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
${variableConflict(ctx, "links", "chats")}
declare
  v_chat record;
  v_salt text;
begin
  ${loadChat("create_ai_chat_link", "chat")}
${mayShare}
  insert into ${t.links} (${lk.chat}, ${lk.salt}, ${lk.createdBy})
  values (v_chat.id, encode(extensions.gen_random_bytes(16), 'hex'), coalesce(auth.uid(), v_chat.owner))
  on conflict (${lk.chat}) do nothing;
  select l.${lk.salt} into v_salt from ${t.links} l where l.${lk.chat} = v_chat.id;
  ${markShared(ctx, names, "v_chat.id")}
  return jsonb_build_object('chat_id', v_chat.id, 'token', ${token("v_chat.id", "v_salt")});
end;
$$;
${userGrant(`${fn("create_ai_chat_link")}(uuid)`)}

-- Gives the link a new salt, so every token handed out before fails, and
-- returns the new one.
create or replace function ${fn("rotate_ai_chat_link")}(chat uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
${variableConflict(ctx, "links", "chats")}
declare
  v_chat record;
  v_salt text := encode(extensions.gen_random_bytes(16), 'hex');
begin
  ${loadChat("rotate_ai_chat_link", "chat")}
${mayShare}
  update ${t.links} l set ${lk.salt} = v_salt${ctx.has("links", "rotatedAt") ? `, ${lk.rotatedAt} = now()` : ""}
  where l.${lk.chat} = v_chat.id;
  if not found then
    ${raise("Chat % has no link", "P0002", "AI_CHAT_NO_LINK", "v_chat.id")}
  end if;
  return jsonb_build_object('chat_id', v_chat.id, 'token', ${token("v_chat.id", "v_salt")});
end;
$$;
${userGrant(`${fn("rotate_ai_chat_link")}(uuid)`)}

-- Removes the link. Returns whether the chat had one.
create or replace function ${fn("revoke_ai_chat_link")}(chat uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
${variableConflict(ctx, "links", "chats")}
declare
  v_chat record;
begin
  ${loadChat("revoke_ai_chat_link", "chat")}
  delete from ${t.links} l where l.${lk.chat} = v_chat.id;
  return found;
end;
$$;
${userGrant(`${fn("revoke_ai_chat_link")}(uuid)`)}

-- The chat and its active branch for a live link token, for anyone holding
-- it: { chat, leaf_id, messages }, or null when the token is unknown, was
-- rotated or revoked, or the chat is private again.
create or replace function ${fn("get_ai_chat_by_link")}(token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
${variableConflict(ctx, "links", "chats")}
declare
  v_chat ${t.chats};
  v_id uuid;
  v_salt text;
begin
  if get_ai_chat_by_link.token is null or get_ai_chat_by_link.token !~ '^${UUID}\\.[0-9a-f]{64}$' then
    return null;
  end if;
  v_id := split_part(get_ai_chat_by_link.token, '.', 1)::uuid;
  select l.${lk.salt} into v_salt from ${t.links} l where l.${lk.chat} = v_id;
  if not found
    or ${token("v_id", "v_salt")} <> get_ai_chat_by_link.token then
    return null;
  end if;
  select * into v_chat from ${t.chats} x where x.${ch.id} = v_id and ${asText(ctx, "chats", `x.${ch.visibility}`)} <> 'private';
  if not found then
    return null;
  end if;
  return jsonb_build_object(
    'chat', jsonb_build_object('id', v_chat.${ch.id}, 'title', v_chat.${ch.title}, 'model', v_chat.${ch.model}, 'mode', ${columnOr(ctx, "chats", "v_chat", "mode")}, 'created_at', ${columnOr(ctx, "chats", "v_chat", "createdAt")}),
    'leaf_id', v_chat.${ch.leaf},
    'messages', case when v_chat.${ch.leaf} is null then '[]'::jsonb else ${fn("ai_message_path_of")}(v_chat.${ch.id}, v_chat.${ch.leaf}${names.messages.uuid ? "::text" : ""}, false) end
  );
end;
$$;
revoke execute on function ${fn("get_ai_chat_by_link")}(text) from public;
grant execute on function ${fn("get_ai_chat_by_link")}(text) to anon, authenticated, service_role;`;
}

/**
 * Version 5 to 6: chats may be shared, participants have a kind and a surrogate
 * key, and chats take a mode. A private chat with participants becomes shared.
 * Tables the app owns are left to the app.
 */
export function upgradeSharing(
  ctx: BlockSqlContext,
  names: AiChatNames,
): string {
  const { t } = names;
  const ch = names.c.chats;
  const pa = names.c.participants;
  const parts: string[] = [];

  if (ctx.owns("chats")) {
    parts.push(
      replaceColumnCheck({
        table: t.chats,
        column: ch.visibility,
        name: "ai_chats_visibility_check",
        expression: `${ch.visibility} in (${VISIBILITIES})`,
      }),
      `alter table ${t.chats} add column if not exists ${ch.mode} text check (length(${ch.mode}) <= 100);`,
    );
  }

  if (ctx.owns("participants")) {
    const name = sqlString("ai_chat_participants_shape_check");

    parts.push(
      `alter table ${t.participants} add column if not exists ${pa.id} uuid default gen_random_uuid();
alter table ${t.participants} add column if not exists ${pa.kind} text not null default 'user' check (${pa.kind} in ('user', 'team', 'customer', 'external'));
alter table ${t.participants} add column if not exists ${pa.team} uuid;
alter table ${t.participants} add column if not exists ${pa.customerUser} uuid references auth.users (id) on delete cascade;
alter table ${t.participants} add column if not exists ${pa.email} text check (length(${pa.email}) <= 320);
alter table ${t.participants} alter column ${pa.id} set not null;
alter table ${t.participants} alter column ${pa.user} drop not null;
do $$
declare
  v_key name;
begin
  select c.conname into v_key from pg_catalog.pg_constraint c
  where c.conrelid = ${sqlString(t.participants)}::regclass and c.contype = 'p'
    and not exists (
      select 1 from pg_catalog.pg_attribute a
      where a.attrelid = c.conrelid and a.attnum = any (c.conkey) and a.attname = ${sqlString(unquote(pa.id))}
    );
  if v_key is not null then
    execute format('alter table %s drop constraint %I', ${sqlString(t.participants)}, v_key);
  end if;
  if not exists (select 1 from pg_catalog.pg_constraint where conrelid = ${sqlString(t.participants)}::regclass and contype = 'p') then
    alter table ${t.participants} add primary key (${pa.id});
  end if;
  if not exists (select 1 from pg_catalog.pg_constraint where conrelid = ${sqlString(t.participants)}::regclass and conname = ${name}) then
    alter table ${t.participants} add constraint ${sqlIdent("ai_chat_participants_shape_check")} check (
      (${pa.kind} = 'user' and ${pa.user} is not null)
      or (${pa.kind} = 'team' and ${pa.team} is not null)
      or (${pa.kind} = 'customer' and ${pa.customerUser} is not null)
      or (${pa.kind} = 'external' and ${pa.email} is not null)
    );
  end if;
end;
$$;`,
    );
  }

  parts.push(
    `update ${t.chats} x set ${ch.visibility} = ${ctx.cast("chats", "visibility", "'shared'")}
where ${asText(ctx, "chats", `x.${ch.visibility}`)} = 'private'
  and exists (select 1 from ${t.participants} p where p.${pa.chat} = x.${ch.id});`,
  );

  return parts.join("\n");
}

function unquote(identifier: string): string {
  return identifier.replace(/^"(.*)"$/s, "$1").replaceAll('""', '"');
}
