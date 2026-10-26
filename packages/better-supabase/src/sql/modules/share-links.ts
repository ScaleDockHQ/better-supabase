import type { ShareLinksEvents } from "../../blocks/share-links/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { ShareLinkSubjectSql } from "../contributions.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { uniqueContributions } from "../contributions.ts";
import {
  addExtraColumns,
  extraFieldsArg,
  extraFieldsJson,
  fail,
  lockTable,
  schemaPreamble,
  SERVICE_CALLER,
  sha256Hex,
  userGrant,
  withExtraFields,
  writeExtraColumns,
} from "../shared.ts";
import {
  subjectActionCheck,
  subjectReadable,
  subjectsOption,
} from "../subjects.ts";
import { OPERATIONS } from "./permissions-model.ts";

const EVENTS: BlockSqlEvents<ShareLinksEvents> = {
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

const NAMES: BlockSqlNames = {
  entities: { link: { table: "links", singular: "share_link", primary: true } },
  events: EVENTS,
  options: ["extraColumns", "tokenHash", "fullRows"],
  tables: {
    links: {
      name: "share_links",
      app: {},
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
        useCount: "use_count",
        createdBy: "created_by",
        leaf: "leaf_id",
        versionId: "version_id",
        createdAt: "created_at",
      },
      optional: ["leaf", "versionId", "useCount", "createdAt"],
    },
    views: {
      name: "subject_views",
      app: {},
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
      app: {},
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
 * The conditions a live link meets, for the functions that open a link of one
 * subject type: `links` is the share-links context, `alias` the table alias,
 * `token` the presented token (a text expression) and `subjectType` a SQL
 * expression. Every consumer checks the hash, the type, revocation, expiry and
 * the use limit through this, so none of them can drop one.
 */
export function liveShareLink(
  links: BlockSqlContext,
  alias: string,
  token: string,
  subjectType: string,
): string {
  const l = (column: string): string =>
    `${alias}.${links.col("links", column)}`;

  return `${l("tokenHash")} = ${sha256Hex(`convert_to(${token}, 'utf8')`)}
    and ${l("subjectType")} = ${subjectType}
    and ${unspentShareLink(links, alias)}`;
}

/** Not revoked, not expired and, with `use_count`, under `max_uses`. */
function unspentShareLink(links: BlockSqlContext, alias: string): string {
  const l = (column: string): string =>
    `${alias}.${links.col("links", column)}`;

  const uses = links.has("links", "useCount")
    ? `\n    and (${l("maxUses")} is null or ${l("useCount")} < ${l("maxUses")})`
    : "";

  return `${l("revokedAt")} is null
    and (${l("expiresAt")} is null or ${l("expiresAt")} > now())${uses}`;
}

/** The `create_share_link` arguments the subject check reads. */
const SUBJECT_ARGS = {
  type: "create_share_link.subject_type",
  id: "create_share_link.subject_id",
  tenant: "create_share_link.tenant",
} as const;

/**
 * `exists` for a subject that is a row of `table` in the contributing block,
 * found in the link's tenant.
 */
export function shareLinkRow(
  own: BlockSqlContext,
  table: string,
  subject: ShareLinkSubjectSql,
): string {
  const c = (column: string): string => `s.${own.col(table, column)}`;

  return `exists (select 1 from ${own.table(table)} s where ${c("id")}::text = ${subject.id} and ${c("tenant")}::text = ${subject.tenant}::text)`;
}

/**
 * The subject types other blocks own, each with the SQL that finds the subject
 * in the link's tenant.
 */
function blockSubjects(
  ctx: BlockSqlContext,
): readonly (readonly [string, string])[] {
  return uniqueContributions(
    "share-links",
    ctx.contributions("share-links"),
    (each) => each.subject,
  ).map((each) => [each.subject, each.exists(SUBJECT_ARGS)] as const);
}

/**
 * Whether the subject a new link names exists in the link's tenant and the
 * caller may share it. Block-owned types come first; registered subjects
 * (`config.subjects` or `on`) check the row's tenant and the subject's read
 * permission. Any other type fails.
 */
function subjectCheck(ctx: BlockSqlContext): string {
  const blocks = blockSubjects(ctx);
  const owned = new Set(blocks.map(([type]) => type));

  const registered = subjectsOption(ctx).filter(([type]) => !owned.has(type));

  const sharable = subjectActionCheck(ctx, registered, SUBJECT_ARGS, ["share"]);

  const readable =
    registered.length === 0
      ? "null"
      : subjectReadable(ctx, registered, SUBJECT_ARGS).replace(
          /else false\s+end$/,
          "else null\n  end",
        );

  const others =
    sharable === undefined || readable === "null"
      ? readable
      : `case when ${readable} then ${sharable} else ${readable} end`;

  const check =
    blocks.length === 0
      ? others
      : `case ${SUBJECT_ARGS.type}
${blocks.map(([type, sql]) => `    when ${sqlString(type)} then ${sql}`).join("\n")}
    else ${others}
  end`;

  if (check === "null") {
    return `if not (${SERVICE_CALLER}) then
    ${fail("SHARE_SUBJECT_UNKNOWN", "this subject type can't be shared", "22023")}
  end if;`;
  }

  return `if not (${SERVICE_CALLER}) then
    v_subject_ok := ${check};
    if v_subject_ok is null then
      ${fail("SHARE_SUBJECT_UNKNOWN", "this subject type can't be shared", "22023")}
    end if;
    if not v_subject_ok then
      ${fail("SHARE_SUBJECT_NOT_FOUND", "the subject does not exist in this organization", "P0002")}
    end if;
  end if;`;
}

/**
 * A link pinned to a version names one of the subject's versions; without the
 * versions module there is nothing to pin.
 */
function versionCheck(ctx: BlockSqlContext): string {
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

/**
 * `find_share_link(token_hash)`: the live link a hash names, without counting a
 * use, for a caller that keeps the hash of a token it made.
 */
function findShareLink(
  ctx: BlockSqlContext,
  links: string,
  pinned: boolean,
): string {
  const v = (column: string): string => `l.${ctx.col("links", column)}`;

  return `
-- The live link a token hash names, or null. It counts no use.
create or replace function ${ctx.fn("find_share_link")}(token_hash text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', ${v("id")}, 'organizationId', ${v("tenant")}, 'subjectType', ${v("subjectType")}, 'subjectId', ${v("subjectId")}, 'role', ${v("role")}, 'versionId', ${pinned ? v("versionId") : "null"}, 'expiresAt', ${v("expiresAt")}, 'maxUses', ${v("maxUses")}, 'createdBy', ${v("createdBy")})
  from ${links} l
  where ${v("tokenHash")} = find_share_link.token_hash
    and ${unspentShareLink(ctx, "l")}
$$;
revoke all on function ${ctx.fn("find_share_link")}(text) from public, anon, authenticated;
grant execute on function ${ctx.fn("find_share_link")}(text) to service_role;
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const links = ctx.table("links");
  const views = ctx.hasTable("views") ? ctx.table("views") : "";
  const state = ctx.hasTable("state") ? ctx.table("state") : "";
  const create = ctx.permission("create", OPERATIONS["share-links.create"]);
  const read = ctx.permission("read", OPERATIONS["share-links.read"]);
  const pinned = ctx.has("links", "versionId");
  const extras = ctx.extraColumns("links", RESERVED);
  const extra = extraFieldsArg(extras);
  const linkId = ctx.col("links", "id");
  const hashed = ctx.flag("tokenHash", false);
  const full = ctx.flag("fullRows", false);
  const subjects = subjectsOption(ctx);
  const l = (column: string): string => `l.${ctx.col("links", column)}`;

  const shareOn = (type: string, id: string): string | undefined =>
    subjectActionCheck(ctx, subjects, { type, id }, ["share"]);

  const listShare = shareOn(l("subjectType"), l("subjectId"));
  const revokeShare = shareOn("v_type", "v_subject");

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
${ctx.has("links", "versionId") ? `alter table ${links} add column if not exists ${ctx.col("links", "versionId")} uuid;\n` : ""}${full && ctx.has("links", "createdAt") ? `alter table ${links} add column if not exists ${ctx.col("links", "createdAt")} timestamptz not null default now();\n` : ""}${ctx.has("links", "useCount") ? `alter table ${links} add column if not exists ${ctx.col("links", "useCount")} integer not null default 0;\n` : ""}${lockTable(links, { read: true })}
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

  const contributed = ctx
    .contributions("share-links")
    .flatMap((each) => each.sql ?? [])
    .join("");

  return `${schemaPreamble(ctx)}
${tables}
drop function if exists ${ctx.fn("create_share_link")}(${ctx.idType}, text, text, text);
drop function if exists ${ctx.fn("create_share_link")}(${ctx.idType}, text, text, text, uuid);
drop function if exists ${ctx.fn("create_share_link")}(${ctx.idType}, text, text, text, uuid, timestamptz);
drop function if exists ${ctx.fn("create_share_link")}(${ctx.idType}, text, text, text, uuid, timestamptz, jsonb);
-- fields: the extra columns (blocks.share-links.options.extraColumns) to set.
${
  hashed
    ? ["", ", jsonb", extras.length === 0 ? ", text, jsonb" : ", text"]
        .map(
          (tail) =>
            `drop function if exists ${ctx.fn("create_share_link")}(${ctx.idType}, text, text, text, uuid, timestamptz, integer${tail});`,
        )
        .join("\n")
    : extra.drop(
        ctx.fn("create_share_link"),
        `${ctx.idType}, text, text, text, uuid, timestamptz, integer`,
      )
}${
    hashed
      ? `
-- token_hash: the sha256 hex of a token the caller made; the link then has no
-- token to return.`
      : ""
  }
create or replace function ${ctx.fn("create_share_link")}(tenant ${ctx.idType}, subject_type text, subject_id text, role text, version_id uuid default null, expires_at timestamptz default null, max_uses integer default null${hashed ? ", token_hash text default null" : ""}${extra.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text := ${hashed ? "case when create_share_link.token_hash is null then encode(extensions.gen_random_bytes(24), 'hex') end" : "encode(extensions.gen_random_bytes(24), 'hex')"};
  v_id uuid;
  v_subject_ok boolean;
begin
  if not (auth.role() = 'service_role' or ${ctx.scope.can("create_share_link.tenant", create)}) then
    ${fail("SHARE_FORBIDDEN", "not allowed to share")}
  end if;
  if create_share_link.expires_at is not null and create_share_link.expires_at <= now() then
    ${fail("SHARE_EXPIRY_INVALID", "expires_at must be in the future", "22023")}
  end if;
  if create_share_link.max_uses is not null and create_share_link.max_uses < 1 then
    ${fail("SHARE_MAX_USES_INVALID", "max_uses must be at least 1", "22023")}
  end if;${
    hashed
      ? `
  if create_share_link.token_hash is not null and create_share_link.token_hash !~ '^[0-9a-f]{64}$' then
    ${fail("SHARE_TOKEN_HASH_INVALID", "token_hash must be 64 lowercase hex characters", "22023")}
  end if;`
      : ""
  }
  ${subjectCheck(ctx)}
  ${versionCheck(ctx)}
  insert into ${links} (${ctx.col("links", "tenant")}, ${ctx.col("links", "subjectType")}, ${ctx.col("links", "subjectId")}, ${ctx.col("links", "tokenHash")}, ${ctx.col("links", "role")}, ${ctx.col("links", "expiresAt")}, ${ctx.col("links", "maxUses")}, ${ctx.col("links", "createdBy")}${pinned ? `, ${ctx.col("links", "versionId")}` : ""})
  values (create_share_link.tenant, create_share_link.subject_type, create_share_link.subject_id, ${hashed ? `coalesce(create_share_link.token_hash, ${sha256Hex("convert_to(v_token, 'utf8')")})` : sha256Hex("convert_to(v_token, 'utf8')")}, coalesce(create_share_link.role, 'view'), create_share_link.expires_at, create_share_link.max_uses, auth.uid()${pinned ? ", create_share_link.version_id" : ""})
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
${userGrant(`${ctx.fn("create_share_link")}(${ctx.idType}, text, text, text, uuid, timestamptz, integer${hashed ? ", text" : ""}${extra.type})`)}

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
  v_creator uuid;${revokeShare === undefined ? "" : "\n  v_type text;\n  v_subject text;"}
begin
  select ${ctx.col("links", "tenant")}, ${ctx.col("links", "createdBy")}${revokeShare === undefined ? "" : `, ${ctx.col("links", "subjectType")}, ${ctx.col("links", "subjectId")}`} into v_tenant, v_creator${revokeShare === undefined ? "" : ", v_type, v_subject"}
  from ${links}
  where ${ctx.col("links", "id")} = revoke_share_link.id and ${ctx.col("links", "revokedAt")} is null
  for update;
  if not found or not (
    auth.role() = 'service_role'
    or (v_creator is not null and v_creator = auth.uid())
    or ${revokeShare === undefined ? ctx.scope.can("v_tenant", create) : `(${ctx.scope.can("v_tenant", create)} and ${revokeShare})`}
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

-- Each resolve counts one use, so a link with max_uses stops resolving once
-- it is spent. The row lock keeps two concurrent resolves from both taking
-- the last use.
create or replace function ${ctx.fn("resolve_share_link")}(token text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_link ${links}%rowtype;
begin
  select * into v_link
  from ${links} l
  where l.${ctx.col("links", "tokenHash")} = ${sha256Hex("convert_to(resolve_share_link.token, 'utf8')")}
    and ${unspentShareLink(ctx, "l")}
  for update;
  if not found then
    return null;
  end if;${
    ctx.has("links", "useCount")
      ? `
  update ${links} set ${ctx.col("links", "useCount")} = ${ctx.col("links", "useCount")} + 1
  where ${ctx.col("links", "id")} = v_link.${ctx.col("links", "id")};`
      : ""
  }
  return jsonb_build_object('id', v_link.${ctx.col("links", "id")}, 'organizationId', v_link.${ctx.col("links", "tenant")}, 'subjectType', v_link.${ctx.col("links", "subjectType")}, 'subjectId', v_link.${ctx.col("links", "subjectId")}, 'role', v_link.${ctx.col("links", "role")}, 'versionId', ${pinned ? `v_link.${ctx.col("links", "versionId")}` : "null"}, 'expiresAt', v_link.${ctx.col("links", "expiresAt")}, 'maxUses', v_link.${ctx.col("links", "maxUses")});
end;
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

${full ? `drop function if exists ${ctx.fn("list_share_links")}(text, text);\n-- include_revoked: false leaves out revoked links.\n` : ""}create or replace function ${ctx.fn("list_share_links")}(subject_type text, subject_id text${full ? ", include_revoked boolean default true" : ""})
returns jsonb
language ${listShare === undefined ? "sql" : "plpgsql"}
stable
security definer
set search_path = ''
as $$
  ${listShare === undefined ? "" : "begin\n  return (\n  "}select coalesce(jsonb_agg(jsonb_build_object('id', l.${ctx.col("links", "id")}, 'role', l.${ctx.col("links", "role")}, 'expiresAt', l.${ctx.col("links", "expiresAt")}, 'revokedAt', l.${ctx.col("links", "revokedAt")}${full ? `, 'organizationId', ${l("tenant")}, 'subjectType', ${l("subjectType")}, 'subjectId', ${l("subjectId")}, 'createdBy', ${l("createdBy")}, 'createdAt', ${ctx.has("links", "createdAt") ? l("createdAt") : "null"}` : ""}${extraFieldsJson("l", extras)})${full && ctx.has("links", "createdAt") ? ` order by ${l("createdAt")} desc, ${l("id")}` : ""}), '[]'::jsonb)
  from ${links} l
  where l.${ctx.col("links", "subjectType")} = list_share_links.subject_type
    and l.${ctx.col("links", "subjectId")} = list_share_links.subject_id${full ? `\n    and (list_share_links.include_revoked or ${l("revokedAt")} is null)` : ""}
    and (
      auth.role() = 'service_role'
      or l.${ctx.col("links", "createdBy")} = (select auth.uid())
      or ${listShare === undefined ? ctx.scope.check(`l.${ctx.col("links", "tenant")}`, read) : `(${ctx.scope.check(`l.${ctx.col("links", "tenant")}`, read)} and ${listShare})`}
    )${listShare === undefined ? "" : ");\nend;"}
$$;
${userGrant(`${ctx.fn("list_share_links")}(text, text${full ? ", boolean" : ""})`)}${hashed ? findShareLink(ctx, links, pinned) : ""}

create or replace function ${ctx.fn("set_user_state")}(subject_type text, subject_id text, starred boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
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
${contributed}
`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  const extra = extraFieldsArg(ctx.extraColumns("links", RESERVED)).contract;

  return [
    {
      name: "create_share_link",
      args: [
        "{id}",
        "text",
        "text",
        "text",
        "uuid",
        "timestamptz",
        "integer",
        ...(ctx.flag("tokenHash", false) ? ["text"] : []),
        ...extra,
      ],
      returns: "jsonb",
    },
    { name: "revoke_share_link", args: ["uuid"], returns: "boolean" },
    { name: "resolve_share_link", args: ["text"], returns: "jsonb" },
    {
      name: "record_view",
      args: ["{id}", "text", "text", "text", "text"],
      returns: "boolean",
    },
    {
      name: "list_share_links",
      args: [
        "text",
        "text",
        ...(ctx.flag("fullRows", false) ? ["boolean"] : []),
      ],
      returns: "jsonb",
    },
    ...(ctx.flag("tokenHash", false)
      ? [{ name: "find_share_link", args: ["text"], returns: "jsonb" }]
      : []),
  ];
}

export const SHARE_LINKS: BlockSqlDefinition = {
  name: "share-links",
  scopes: ["tenant"],
  title: "Share links",
  description:
    "Hashed share links, view counts and per-user state. The token is returned once. Resolving a link hashes the token the caller presents, so a stored plaintext token keeps working after it is hashed.",
  requires: ["memberships", "permissions"],
  integrates: ["outbox", "versions", "subjects"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
