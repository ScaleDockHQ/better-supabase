import type { ShareLinksEvents } from "../../blocks/share-links/events.ts";
import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import {
  addExtraColumns,
  extraFieldsArg,
  extraFieldsJson,
  fail,
  lockTable,
  schemaPreamble,
  sha256Hex,
  userGrant,
  withExtraFields,
  writeExtraColumns,
} from "../shared.ts";
import { OPERATIONS } from "./access-model.ts";

const EVENTS: ModuleEvents<ShareLinksEvents> = {
  "share_link.created": {
    subject: "share-links",
    payload: ["organizationId", "id", "subjectType", "subjectId"],
  },
  "share_link.revoked": {
    subject: "share-links",
    payload: ["organizationId", "id"],
  },
  "subject.viewed": {
    subject: "views",
    payload: ["organizationId", "subjectType", "subjectId"],
  },
};

const NAMES: ModuleNames = {
  events: EVENTS,
  options: ["subjects", "extraColumns"],
  tables: {
    links: {
      name: "share_links",
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        tokenHash: "token_hash",
        role: "role",
        version: "version",
        expiresAt: "expires_at",
        revokedAt: "revoked_at",
        maxUses: "max_uses",
        createdBy: "created_by",
        leaf: "leaf_id",
        versionId: "version_id",
      },
      optional: ["leaf", "versionId"],
    },
    views: {
      name: "subject_views",
      optionalTable: true,
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        version: "version",
        viewerKind: "viewer_kind",
        viewer: "viewer",
        firstViewedAt: "first_viewed_at",
        lastViewedAt: "last_viewed_at",
        viewCount: "view_count",
      },
    },
    state: {
      name: "subject_user_state",
      optionalTable: true,
      columns: {
        subjectType: "subject_type",
        subjectId: "subject_id",
        user: "user_id",
        starredAt: "starred_at",
        lastOpenedAt: "last_opened_at",
      },
    },
  },
};

/** The keys the share link reads return next to the extra columns. */
const RESERVED = ["fields", "token"] as const;

/**
 * The conditions a live link meets, for the functions that open a link of
 * one subject type: `links` is the share-links context, `alias` the table
 * alias, `token` the presented token (a text expression) and `subjectType`
 * a SQL expression. Every consumer checks the hash, the type, revocation and
 * expiry through this, so none of them can drop one.
 */
export function liveShareLink(
  links: ModuleContext,
  alias: string,
  token: string,
  subjectType: string,
): string {
  const l = (column: string): string =>
    `${alias}.${links.col("links", column)}`;

  return `${l("tokenHash")} = ${sha256Hex(`convert_to(${token}, 'utf8')`)}
    and ${l("subjectType")} = ${subjectType}
    and ${l("revokedAt")} is null
    and (${l("expiresAt")} is null or ${l("expiresAt")} > now())`;
}

/**
 * A link pinned to a version names one of the subject's versions; without
 * the versions module there is nothing to pin.
 */
function versionCheck(ctx: ModuleContext): string {
  const refuse = (message: string): string =>
    fail("SHARE_VERSION_INVALID", message, "22023");

  if (!ctx.installed("versions") || !ctx.has("links", "versionId")) {
    return `if create_share_link.version_id is not null then
    ${refuse("install the versions module to share a version")}
  end if;`;
  }

  return `if create_share_link.version_id is not null then
    declare
      v_version jsonb := ${ctx.fn("get_version")}(create_share_link.version_id);
    begin
      if v_version ->> 'subjectType' is distinct from create_share_link.subject_type
        or v_version ->> 'subjectId' is distinct from create_share_link.subject_id then
        ${refuse("the version belongs to another subject")}
      end if;
    end;
  end if;`;
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const links = ctx.table("links");
  const views = ctx.table("views");
  const state = ctx.table("state");
  const create = ctx.permission("create", OPERATIONS["share-links.create"]);
  const read = ctx.permission("read", OPERATIONS["share-links.read"]);
  const pinned = ctx.has("links", "versionId");
  const extras = ctx.extraColumns("links", RESERVED);
  const extra = extraFieldsArg(extras);
  const linkId = ctx.col("links", "id");

  const tables = ctx.manages
    ? `create table if not exists ${links} (
  ${ctx.col("links", "id")} uuid primary key default gen_random_uuid(),
  ${ctx.col("links", "tenant")} ${ctx.idType} not null,
  ${ctx.col("links", "subjectType")} text not null,
  ${ctx.col("links", "subjectId")} text not null,
  ${ctx.col("links", "tokenHash")} text not null unique,
  ${ctx.col("links", "role")} text not null default 'view',
  ${ctx.col("links", "version")} integer not null default 1,
  ${ctx.col("links", "expiresAt")} timestamptz,
  ${ctx.col("links", "revokedAt")} timestamptz,
  ${ctx.col("links", "maxUses")} integer,
  ${ctx.col("links", "createdBy")} uuid${ctx.has("links", "leaf") ? `,` : ""}
  ${ctx.has("links", "leaf") ? `${ctx.col("links", "leaf")} text` : ""}
);${addExtraColumns(links, extras)}
${ctx.has("links", "versionId") ? `alter table ${links} add column if not exists ${ctx.col("links", "versionId")} uuid;\n` : ""}${lockTable(links, { read: true })}
create index if not exists ${sqlIdent(`${ctx.tableName("links").name}_subject_idx`)} on ${links} (${ctx.col("links", "tenant")}, ${ctx.col("links", "subjectType")}, ${ctx.col("links", "subjectId")});
${
  ctx.hasTable("views")
    ? `create table if not exists ${views} (
  ${ctx.col("views", "id")} uuid primary key default gen_random_uuid(),
  ${ctx.col("views", "tenant")} ${ctx.idType} not null,
  ${ctx.col("views", "subjectType")} text not null,
  ${ctx.col("views", "subjectId")} text not null,
  ${ctx.col("views", "version")} integer not null default 1,
  ${ctx.col("views", "viewerKind")} text not null,
  ${ctx.col("views", "viewer")} text,
  ${ctx.col("views", "firstViewedAt")} timestamptz not null default now(),
  ${ctx.col("views", "lastViewedAt")} timestamptz not null default now(),
  ${ctx.col("views", "viewCount")} integer not null default 1,
  unique (${ctx.col("views", "tenant")}, ${ctx.col("views", "subjectType")}, ${ctx.col("views", "subjectId")}, ${ctx.col("views", "viewerKind")}, ${ctx.col("views", "viewer")})
);
${lockTable(views, { read: true })}
`
    : ""
}
${
  ctx.hasTable("state")
    ? `create table if not exists ${state} (
  ${ctx.col("state", "subjectType")} text not null,
  ${ctx.col("state", "subjectId")} text not null,
  ${ctx.col("state", "user")} uuid not null,
  ${ctx.col("state", "starredAt")} timestamptz,
  ${ctx.col("state", "lastOpenedAt")} timestamptz,
  primary key (${ctx.col("state", "subjectType")}, ${ctx.col("state", "subjectId")}, ${ctx.col("state", "user")})
);
${lockTable(state, { read: true })}
`
    : ""
}
`
    : "";

  const chat = ctx.installed("ai-chat")
    ? `
-- ai-chat sharing is this block. The old functions stay callable and write
-- share_links instead of ai_chat_shares.
do $$
begin
  if to_regclass('${ctx.schema}.ai_chat_shares') is not null then
    insert into ${links} (${ctx.col("links", "tenant")}, ${ctx.col("links", "subjectType")}, ${ctx.col("links", "subjectId")}, ${ctx.col("links", "tokenHash")}, ${ctx.col("links", "createdBy")}${ctx.has("links", "leaf") ? `, ${ctx.col("links", "leaf")}` : ""})
    select c.${ctx.naming.rename("organization_id")}, 'ai-chat', s.chat_id::text, s.token_hash, s.created_by${ctx.has("links", "leaf") ? ", s.leaf_id" : ""}
    from ${ctx.schema}.ai_chat_shares s
    join ${ctx.schema}.ai_chats c on c.id = s.chat_id
    on conflict (${ctx.col("links", "tokenHash")}) do nothing;
  end if;
end;
$$;
create or replace function ${ctx.fn("share_ai_chat")}(chat uuid, leaf text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_tenant ${ctx.idType};
  v_owner uuid;
  v_leaf text;
  v_token text := encode(extensions.gen_random_bytes(32), 'hex');
  v_id uuid;
begin
  select ${ctx.naming.rename("organization_id")}, owner_id, current_leaf_id into v_tenant, v_owner, v_leaf
  from ${ctx.schema}.ai_chats where id = share_ai_chat.chat;
  if not found or v_owner is distinct from auth.uid() then
    ${fail("AI_CHAT_NOT_FOUND", "no chat", "P0002")}
  end if;
  v_leaf := coalesce(share_ai_chat.leaf, v_leaf);
  insert into ${links} (${ctx.col("links", "tenant")}, ${ctx.col("links", "subjectType")}, ${ctx.col("links", "subjectId")}, ${ctx.col("links", "tokenHash")}, ${ctx.col("links", "role")}, ${ctx.col("links", "createdBy")}${ctx.has("links", "leaf") ? `, ${ctx.col("links", "leaf")}` : ""})
  values (v_tenant, 'ai-chat', share_ai_chat.chat::text, ${sha256Hex("convert_to(v_token, 'utf8')")}, 'view', auth.uid()${ctx.has("links", "leaf") ? ", v_leaf" : ""})
  returning ${ctx.col("links", "id")} into v_id;
  return jsonb_build_object('id', v_id, 'token', v_token, 'leaf_id', v_leaf);
end;
$$;
${userGrant(`${ctx.fn("share_ai_chat")}(uuid, text)`)}
create or replace function ${ctx.fn("revoke_ai_chat_share")}(id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  return ${ctx.fn("revoke_share_link")}(revoke_ai_chat_share.id);
end;
$$;
create or replace function ${ctx.fn("list_ai_chat_shares")}(chat uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select ${ctx.fn("list_share_links")}('ai-chat', list_ai_chat_shares.chat::text)
$$;
create or replace function ${ctx.fn("get_shared_ai_chat")}(token text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_subject text;
  v_leaf text;
  v_chat_id uuid;
begin
  if get_shared_ai_chat.token is null or get_shared_ai_chat.token !~ '^[0-9a-f]{64}$' then
    return null;
  end if;
  select l.${ctx.col("links", "subjectId")}, ${ctx.has("links", "leaf") ? `l.${ctx.col("links", "leaf")}` : "null"}
    into v_subject, v_leaf
  from ${links} l
  where ${liveShareLink(ctx, "l", "get_shared_ai_chat.token", "'ai-chat'")};
  if not found then
    return null;
  end if;
  v_chat_id := v_subject::uuid;
  return jsonb_build_object(
    'chat', (select jsonb_build_object('id', id, 'title', title, 'model', model, 'created_at', created_at) from ${ctx.schema}.ai_chats where id = v_chat_id),
    'leaf_id', v_leaf,
    'messages', ${ctx.fn("ai_message_path_of")}(v_chat_id, v_leaf, false)
  );
end;
$$;
`
    : "";

  return `${schemaPreamble(ctx)}
${tables}
drop function if exists ${ctx.fn("create_share_link")}(${ctx.idType}, text, text, text);
drop function if exists ${ctx.fn("create_share_link")}(${ctx.idType}, text, text, text, uuid);
-- fields: the extra columns (blocks.share-links.options.extraColumns) to set.
${extra.drop(ctx.fn("create_share_link"), `${ctx.idType}, text, text, text, uuid, timestamptz`)}
create or replace function ${ctx.fn("create_share_link")}(tenant ${ctx.idType}, subject_type text, subject_id text, role text, version_id uuid default null, expires_at timestamptz default null${extra.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_id uuid;
begin
  if not (auth.role() = 'service_role' or ${ctx.scope.can("create_share_link.tenant", create)}) then
    ${fail("SHARE_FORBIDDEN", "not allowed to share")}
  end if;
  if create_share_link.expires_at is not null and create_share_link.expires_at <= now() then
    ${fail("SHARE_EXPIRY_INVALID", "expires_at must be in the future", "22023")}
  end if;
  ${versionCheck(ctx)}
  insert into ${links} (${ctx.col("links", "tenant")}, ${ctx.col("links", "subjectType")}, ${ctx.col("links", "subjectId")}, ${ctx.col("links", "tokenHash")}, ${ctx.col("links", "role")}, ${ctx.col("links", "expiresAt")}, ${ctx.col("links", "createdBy")}${pinned ? `, ${ctx.col("links", "versionId")}` : ""})
  values (create_share_link.tenant, create_share_link.subject_type, create_share_link.subject_id, ${sha256Hex("convert_to(v_token, 'utf8')")}, coalesce(create_share_link.role, 'view'), create_share_link.expires_at, auth.uid()${pinned ? ", create_share_link.version_id" : ""})
  returning ${ctx.col("links", "id")} into v_id;${writeExtraColumns(links, extras, "create_share_link.fields", `x.${linkId} = v_id`)}
  ${ctx.record({
    type: "share_link.created",
    payload: `jsonb_build_object('organizationId', create_share_link.tenant, 'id', v_id, 'subjectType', create_share_link.subject_type, 'subjectId', create_share_link.subject_id)`,
    subject: `'share-links/' || v_id::text`,
    tenant: "create_share_link.tenant",
    audit: false,
  })}
  return ${extras.length === 0 ? "jsonb_build_object('id', v_id, 'token', v_token)" : `(select ${withExtraFields("jsonb_build_object('id', v_id, 'token', v_token)", "x", extras)} from ${links} x where x.${linkId} = v_id)`};
end;
$$;
${userGrant(`${ctx.fn("create_share_link")}(${ctx.idType}, text, text, text, uuid, timestamptz${extra.type})`)}

-- The link's creator, or a caller who may create links in its tenant, may
-- revoke it. Anyone else gets SHARE_NOT_FOUND, so ids can't be probed.
create or replace function ${ctx.fn("revoke_share_link")}(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${ctx.idType};
  v_creator uuid;
begin
  select ${ctx.col("links", "tenant")}, ${ctx.col("links", "createdBy")} into v_tenant, v_creator
  from ${links}
  where ${ctx.col("links", "id")} = revoke_share_link.id and ${ctx.col("links", "revokedAt")} is null
  for update;
  if not found or not (
    auth.role() = 'service_role'
    or (v_creator is not null and v_creator = auth.uid())
    or ${ctx.scope.can("v_tenant", create)}
  ) then
    ${fail("SHARE_NOT_FOUND", "share link not found", "P0002")}
  end if;
  update ${links} set ${ctx.col("links", "revokedAt")} = now()
  where ${ctx.col("links", "id")} = revoke_share_link.id;
  ${ctx.record({
    type: "share_link.revoked",
    payload: `jsonb_build_object('organizationId', v_tenant, 'id', revoke_share_link.id)`,
    subject: `'share-links/' || revoke_share_link.id::text`,
    tenant: "v_tenant",
    audit: false,
  })}
  return true;
end;
$$;
${userGrant(`${ctx.fn("revoke_share_link")}(uuid)`)}

create or replace function ${ctx.fn("resolve_share_link")}(token text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', ${ctx.col("links", "id")}, 'organizationId', ${ctx.col("links", "tenant")}, 'subjectType', ${ctx.col("links", "subjectType")}, 'subjectId', ${ctx.col("links", "subjectId")}, 'role', ${ctx.col("links", "role")}, 'versionId', ${pinned ? ctx.col("links", "versionId") : "null"}, 'expiresAt', ${ctx.col("links", "expiresAt")})
  from ${links}
  where ${ctx.col("links", "tokenHash")} = ${sha256Hex("convert_to(resolve_share_link.token, 'utf8')")}
    and ${ctx.col("links", "revokedAt")} is null
    and (${ctx.col("links", "expiresAt")} is null or ${ctx.col("links", "expiresAt")} > now())
$$;
revoke all on function ${ctx.fn("resolve_share_link")}(text) from public, anon, authenticated;
grant execute on function ${ctx.fn("resolve_share_link")}(text) to anon, authenticated, service_role;

create or replace function ${ctx.fn("record_view")}(tenant ${ctx.idType}, subject_type text, subject_id text, viewer_kind text, viewer text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (auth.role() = 'service_role' or record_view.tenant in (select ${ctx.scope.members()})) then
    ${fail("SHARE_FORBIDDEN", "not a member of this organization")}
  end if;
  ${
    ctx.hasTable("views")
      ? `insert into ${views} (${ctx.col("views", "tenant")}, ${ctx.col("views", "subjectType")}, ${ctx.col("views", "subjectId")}, ${ctx.col("views", "viewerKind")}, ${ctx.col("views", "viewer")})
  values (record_view.tenant, record_view.subject_type, record_view.subject_id, record_view.viewer_kind, record_view.viewer)
  on conflict (${ctx.col("views", "tenant")}, ${ctx.col("views", "subjectType")}, ${ctx.col("views", "subjectId")}, ${ctx.col("views", "viewerKind")}, ${ctx.col("views", "viewer")})
  do update set ${ctx.col("views", "lastViewedAt")} = now(), ${ctx.col("views", "viewCount")} = ${views}.${ctx.col("views", "viewCount")} + 1;`
      : "null;"
  }
  ${ctx.record({
    type: "subject.viewed",
    payload: `jsonb_build_object('organizationId', record_view.tenant, 'subjectType', record_view.subject_type, 'subjectId', record_view.subject_id)`,
    subject: `'views/' || record_view.subject_type || '/' || record_view.subject_id`,
    tenant: "record_view.tenant",
    audit: false,
  })}
  return true;
end;
$$;
${userGrant(`${ctx.fn("record_view")}(${ctx.idType}, text, text, text, text)`)}

create or replace function ${ctx.fn("list_share_links")}(subject_type text, subject_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', l.${ctx.col("links", "id")}, 'role', l.${ctx.col("links", "role")}, 'expiresAt', l.${ctx.col("links", "expiresAt")}, 'revokedAt', l.${ctx.col("links", "revokedAt")}${extraFieldsJson("l", extras)})), '[]'::jsonb)
  from ${links} l
  where l.${ctx.col("links", "subjectType")} = list_share_links.subject_type
    and l.${ctx.col("links", "subjectId")} = list_share_links.subject_id
    and (
      auth.role() = 'service_role'
      or l.${ctx.col("links", "createdBy")} = (select auth.uid())
      or ${ctx.scope.check(`l.${ctx.col("links", "tenant")}`, read)}
    )
$$;
${userGrant(`${ctx.fn("list_share_links")}(text, text)`)}

create or replace function ${ctx.fn("set_user_state")}(subject_type text, subject_id text, starred boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  ${
    ctx.hasTable("state")
      ? `insert into ${state} (${ctx.col("state", "subjectType")}, ${ctx.col("state", "subjectId")}, ${ctx.col("state", "user")}, ${ctx.col("state", "starredAt")}, ${ctx.col("state", "lastOpenedAt")})
  values (set_user_state.subject_type, set_user_state.subject_id, auth.uid(), case when set_user_state.starred then now() else null end, now())
  on conflict (${ctx.col("state", "subjectType")}, ${ctx.col("state", "subjectId")}, ${ctx.col("state", "user")})
  do update set ${ctx.col("state", "starredAt")} = excluded.${ctx.col("state", "starredAt")}, ${ctx.col("state", "lastOpenedAt")} = now();`
      : "null;"
  }
  return true;
end;
$$;
${userGrant(`${ctx.fn("set_user_state")}(text, text, boolean)`)}
${chat}
`;
}

function contract(ctx: ModuleContext): readonly ModuleContractFunction[] {
  const extra = extraFieldsArg(ctx.extraColumns("links", RESERVED)).contract;

  return [
    {
      name: "create_share_link",
      args: ["{id}", "text", "text", "text", "uuid", "timestamptz", ...extra],
      returns: "jsonb",
    },
    { name: "revoke_share_link", args: ["uuid"], returns: "boolean" },
    { name: "resolve_share_link", args: ["text"], returns: "jsonb" },
    {
      name: "record_view",
      args: ["{id}", "text", "text", "text", "text"],
      returns: "boolean",
    },
    { name: "list_share_links", args: ["text", "text"], returns: "jsonb" },
  ];
}

export const SHARE_LINKS: ModuleDefinition = {
  name: "share-links",
  scopes: ["tenant"],
  title: "Share links",
  description:
    "Hashed share links, view counts and per-user state. The token is returned once. Resolving a link hashes the token the caller presents, so a stored plaintext token keeps working after it is hashed.",
  requires: ["tenant", "access"],
  integrates: ["ai-chat", "outbox", "versions"],
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
