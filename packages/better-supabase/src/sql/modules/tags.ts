import type { TagsEvents } from "../../blocks/tags/events.ts";
import type {
  ExtraColumn,
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockContributes } from "../contributions.ts";
import type { BlockSqlDefinition } from "../module-types.ts";
import type { SubjectTableBinding } from "../subjects.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { RANK_KEY_PATTERN, rankAfter, rankBackfill } from "../rank-sql.ts";
import {
  addExtraColumns,
  extraFieldsArg,
  extraFieldsJson,
  fail,
  insertExtraColumns,
  lockTable,
  schemaPreamble,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import { moveSubjectRows, subjectMergeHandler } from "../subject-merge-sql.ts";
import {
  andSubjectAction,
  subjectActionCheck,
  subjectReadable,
  subjectTableBindings,
  subjectsOption,
} from "../subjects.ts";
import { driveSubjectGuard } from "./drive-kit.ts";
import { OPERATIONS } from "./permissions-model.ts";

const EVENTS: BlockSqlEvents<TagsEvents> = {
  "tag.created": {
    subject: "tags",
    payload: ["organizationId", "id", "kind", "name"],
  },
  "tag.updated": { subject: "tags", payload: ["organizationId", "id", "name"] },
  "tag.deleted": { subject: "tags", payload: ["organizationId", "id"] },
  "subject.tagged": {
    subject: "subjects",
    payload: ["organizationId", "subjectType", "subjectId", "id"],
  },
  "subject.untagged": {
    subject: "subjects",
    payload: ["organizationId", "subjectType", "subjectId", "id"],
  },
};

const NAMES: BlockSqlNames = {
  entities: { tag: { table: "tags", singular: "tag", primary: true } },
  events: EVENTS,
  hooks: ["before_tag_apply", "after_tag_apply"],
  options: ["extraColumns"],
  tables: {
    tags: {
      name: "tags",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        kind: "kind",
        name: "name",
        slug: "slug",
        color: "color",
        description: "description",
        rank: "rank",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["rank"],
      typed: ["kind"],
    },
    taggings: {
      name: "taggings",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      optionalTable: true,
      columns: {
        tenant: "tenant_id",
        tag: "tag_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        createdAt: "created_at",
      },
      typed: ["subjectType"],
    },
  },
};

const LINK_COLUMNS = ["subject", "tag"] as const;

const SLUG = "'^[a-z0-9]+(-[a-z0-9]+)*$'";

/** The keys the tag reads return next to the extra columns. */
const RESERVED = ["fields"] as const;

function subjects(ctx: BlockSqlContext) {
  return subjectsOption(ctx, ["links", "kinds"]);
}

function links(ctx: BlockSqlContext) {
  return subjectTableBindings(ctx, subjects(ctx), "links", {
    columns: [...LINK_COLUMNS],
    optional: ["tenant", "createdAt"],
  });
}

function kindsOf(extra: Readonly<Record<string, unknown>>): readonly string[] {
  const value = extra["kinds"];

  if (value === undefined) {
    return [];
  }

  if (!Array.isArray(value)) {
    throw new TypeError(
      "blocks.tags.on.<type>.kinds must be a list of strings",
    );
  }

  const kinds: string[] = [];

  for (const item of value) {
    if (typeof item !== "string" || item.length === 0) {
      throw new TypeError(
        "blocks.tags.on.<type>.kinds must be a list of strings",
      );
    }

    kinds.push(item);
  }

  return kinds;
}

function untagBody(
  ctx: BlockSqlContext,
  bound: readonly SubjectTableBinding[],
  taggings: string,
): string {
  const polymorphic =
    taggings === ""
      ? fail("TAG_SUBJECT_UNKNOWN", "this subject has no link table", "22023")
      : `delete from ${taggings} g
      where ${ctx.scope.eq(`g.${ctx.col("taggings", "tenant")}`, "untag.tenant")}
        and g.${ctx.col("taggings", "tag")} = untag.tag_id
        and g.${ctx.col("taggings", "subjectType")} = ${ctx.cast("taggings", "subjectType", "untag.subject_type")}
        and g.${ctx.col("taggings", "subjectId")} = untag.subject_id;`;

  if (bound.length === 0) {
    return polymorphic;
  }

  const whens = bound
    .map((link) => {
      const subject = link.columns["subject"] ?? "subject";
      const tagCol = link.columns["tag"] ?? "tag";

      return `    when ${sqlString(link.type)} then
      delete from ${link.qualified} l where l.${sqlIdent(subject)}::text = untag.subject_id and l.${sqlIdent(tagCol)} = untag.tag_id;`;
    })
    .join("\n");

  return `case untag.subject_type
${whens}
    else
      ${polymorphic}
  end case;`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const tags = ctx.table("tags");
  const taggings = ctx.hasTable("taggings") ? ctx.table("taggings") : "";
  const id = ctx.col("tags", "id");
  const tenant = ctx.col("tags", "tenant");
  const kind = ctx.col("tags", "kind");
  const name = ctx.col("tags", "name");
  const slug = ctx.col("tags", "slug");
  const color = ctx.col("tags", "color");
  const description = ctx.col("tags", "description");
  const ranked = ctx.has("tags", "rank");
  const rank = ranked ? ctx.col("tags", "rank") : "";
  const createdAt = ctx.col("tags", "createdAt");
  const updatedAt = ctx.col("tags", "updatedAt");
  const manage = ctx.permission("manage", OPERATIONS["tags.manage"]);
  const manageKey = ctx.permissionKey("manage", OPERATIONS["tags.manage"]);
  const create = sqlString(ctx.config.permissions["create"] ?? manageKey);
  const update = sqlString(ctx.config.permissions["update"] ?? manageKey);
  const remove = sqlString(ctx.config.permissions["delete"] ?? manageKey);
  const read = ctx.permission("read", OPERATIONS["tags.read"]);
  const applyKey = ctx.permission("apply", OPERATIONS["tags.apply"]);

  const mayApply = (tenantArg: string): string =>
    `auth.role() = 'service_role' or ${ctx.scope.can(tenantArg, applyKey)} or ${ctx.scope.can(tenantArg, manage)}`;

  const bound = links(ctx);
  const list = subjects(ctx);
  const drive = driveSubjectGuard(ctx);

  const readable = (
    args: {
      readonly type: string;
      readonly id: string;
      readonly tenant: string;
    },
    access: "read" | "write",
  ): string => {
    const declared = andSubjectAction(
      subjectReadable(ctx, list, args),
      access === "write"
        ? subjectActionCheck(ctx, list, args, ["write"])
        : undefined,
    );

    return drive === undefined
      ? declared
      : drive.guard(args.type, args.id, access, declared);
  };

  // Outside tenant scope the scope column can be null, and a null tenant
  // still names one set of tags.
  const shared = ctx.scope.kind !== "tenant";
  const extras = ctx.extraColumns("tags", RESERVED);
  const extra = extraFieldsArg(extras);
  const required = insertExtraColumns(tags, extras, "create_tag.fields");

  const tables = ctx.manages
    ? `create table if not exists ${tags} (
  ${id} uuid primary key default gen_random_uuid(),
  ${tenant} ${ctx.scope.column()},
  ${kind} text not null,
  ${name} text not null check (length(${name}) between 1 and 80),
  ${slug} text not null,
  ${color} text,
  ${description} text,
${ranked ? `  ${rank} text collate "C" not null default 'V',\n` : ""}  ${createdAt} timestamptz not null default now(),
  ${updatedAt} timestamptz not null default now(),
  unique${shared ? " nulls not distinct" : ""} (${tenant}, ${kind}, ${slug})
);${addExtraColumns(tags, extras)}
${lockTable(tags, { read: true })}
${
  taggings === ""
    ? ""
    : `create table if not exists ${taggings} (
  ${ctx.col("taggings", "tenant")} ${ctx.scope.column()},
  ${ctx.col("taggings", "tag")} uuid not null references ${tags} (${id}) on delete cascade,
  ${ctx.col("taggings", "subjectType")} text not null,
  ${ctx.col("taggings", "subjectId")} text not null,
  ${ctx.col("taggings", "createdAt")} timestamptz not null default now(),
  primary key (${ctx.col("taggings", "tag")}, ${ctx.col("taggings", "subjectType")}, ${ctx.col("taggings", "subjectId")})
);
create index if not exists ${sqlIdent(`${ctx.tableName("taggings").name}_subject_idx`)} on ${taggings} (${ctx.col("taggings", "tenant")}, ${ctx.col("taggings", "subjectType")}, ${ctx.col("taggings", "subjectId")});
${lockTable(taggings, { read: true })}
`
}`
    : "";

  const apply = bound
    .map((link) => {
      const subject = list.find(([type]) => type === link.type)?.[1];
      const tenantCol = link.columns["tenant"];
      const created = link.columns["createdAt"];

      return `    when ${sqlString(link.type)} then
      insert into ${link.qualified} (${sqlIdent(link.columns["subject"] ?? "subject")}, ${sqlIdent(link.columns["tag"] ?? "tag")}${tenantCol ? `, ${sqlIdent(tenantCol)}` : ""}${created ? `, ${sqlIdent(created)}` : ""})
      values (tag.subject_id${subject?.idType ? `::${subject.idType}` : ""}, tag.tag_id${tenantCol ? ", tag.tenant" : ""}${created ? ", now()" : ""})
      on conflict do nothing;`;
    })
    .join("\n");

  const kindCase = list
    .map(([type, subject]) => {
      const allowed = kindsOf(subject.extra);

      const check =
        allowed.length === 0
          ? "true"
          : `v_kind = any (${sqlString(`{${allowed.join(",")}}`)}::text[])`;

      return `    when ${sqlString(type)} then ${check}`;
    })
    .join("\n");

  const fn = (value: string): string => ctx.fn(value);

  return `${schemaPreamble(ctx)}
${tables}
-- fields: the extra columns (blocks.tags.options.extraColumns) to set.
${["", ", jsonb", extras.length === 0 ? ", text, jsonb" : ", text"]
  .map(
    (tail) =>
      `drop function if exists ${fn("create_tag")}(${ctx.idType}, text, text, text, text${tail});`,
  )
  .join("\n")}
create or replace function ${fn("create_tag")}(tenant ${ctx.idType}, kind text, name text, color text, description text, slug text default null${extra.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_slug text := coalesce(create_tag.slug, trim(both '-' from regexp_replace(lower(create_tag.name), '[^a-z0-9]+', '-', 'g')));
  v_last text;
  v_rank text;
begin
  ${ctx.scope.bind("create_tag.tenant")}if not (auth.role() = 'service_role' or ${ctx.scope.can("create_tag.tenant", create)}) then
    ${fail("TAG_FORBIDDEN", "not allowed to manage tags")}
  end if;
  if create_tag.slug is not null and create_tag.slug !~ ${SLUG} then
    ${fail("TAG_SLUG_INVALID", "a slug is lowercase letters and digits joined by single hyphens", "22023")}
  end if;
${
  ranked
    ? `  select max(t.${rank} collate "C") into v_last from ${tags} t
    where ${ctx.scope.eq(`t.${tenant}`, "create_tag.tenant")} and t.${kind} = ${ctx.cast("tags", "kind", "create_tag.kind")};
  v_rank := ${rankAfter("v_last")};
  insert into ${tags} (${tenant}, ${kind}, ${name}, ${slug}, ${color}, ${description}, ${rank}, ${createdAt}${required.columns})
  values (create_tag.tenant, ${ctx.cast("tags", "kind", "create_tag.kind")}, create_tag.name, v_slug, create_tag.color, create_tag.description, v_rank, now()${required.values})`
    : `  insert into ${tags} (${tenant}, ${kind}, ${name}, ${slug}, ${color}, ${description}, ${createdAt}${required.columns})
  values (create_tag.tenant, ${ctx.cast("tags", "kind", "create_tag.kind")}, create_tag.name, v_slug, create_tag.color, create_tag.description, now()${required.values})`
}
  returning ${id} into v_id;${writeExtraColumns(tags, extras, "create_tag.fields", `x.${id} = v_id`)}
  ${ctx.record({
    type: "tag.created",
    payload: `jsonb_build_object('organizationId', create_tag.tenant, 'id', v_id, 'kind', create_tag.kind, 'name', create_tag.name)`,
    subject: `'tags/' || v_id::text`,
    tenant: "create_tag.tenant",
    audit: false,
  })}
  return ${extras.length === 0 ? "jsonb_build_object('id', v_id, 'slug', v_slug, 'rank', v_rank)" : `(select jsonb_build_object('id', v_id, 'slug', v_slug, 'rank', v_rank${extraFieldsJson("x", extras)}) from ${tags} x where x.${id} = v_id)`};
end;
$$;
${userGrant(`${fn("create_tag")}(${ctx.idType}, text, text, text, text, text${extra.type})`)}

create or replace function ${fn("tag")}(tenant ${ctx.idType}, subject_type text, subject_id text, tag_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_kind text;
begin
  ${ctx.scope.bind("tag.tenant")}if not (${mayApply("tag.tenant")}) then
    ${fail("TAG_FORBIDDEN", "not allowed to apply tags")}
  end if;
  if not (${readable({ type: "tag.subject_type", id: "tag.subject_id", tenant: "tag.tenant" }, "write")}) then
    ${fail("TAG_SUBJECT_FORBIDDEN", "not allowed to tag this record")}
  end if;
  select ${kind} into v_kind from ${tags} where ${id} = tag.tag_id and ${ctx.scope.eq(tenant, "tag.tenant")};
  if v_kind is null then
    ${fail("TAG_NOT_FOUND", "tag not found", "P0002")}
  end if;
  if not (case tag.subject_type
${kindCase === "" ? "    when '' then true" : kindCase}
    else true
  end) then
    ${fail("TAG_KIND_MISMATCH", "tag kind is not allowed on this subject", "22023")}
  end if;
  ${ctx.hook("before_tag_apply", [
    [ctx.idType, "tag.tenant"],
    ["text", "tag.subject_type"],
    ["text", "tag.subject_id"],
    ["uuid", "tag.tag_id"],
  ])}
  case tag.subject_type
${apply === "" ? "    when '' then null;" : apply}
    else
      ${
        ctx.hasTable("taggings")
          ? `insert into ${taggings} (${ctx.col("taggings", "tenant")}, ${ctx.col("taggings", "tag")}, ${ctx.col("taggings", "subjectType")}, ${ctx.col("taggings", "subjectId")})
      values (tag.tenant, tag.tag_id, ${ctx.cast("taggings", "subjectType", "tag.subject_type")}, tag.subject_id)
      on conflict do nothing;`
          : fail(
              "TAG_SUBJECT_UNKNOWN",
              "this subject has no link table",
              "22023",
            )
      }
  end case;
  ${ctx.record({
    type: "subject.tagged",
    payload: `jsonb_build_object('organizationId', tag.tenant, 'subjectType', tag.subject_type, 'subjectId', tag.subject_id, 'id', tag.tag_id)`,
    subject: `'subjects/' || tag.subject_type || '/' || tag.subject_id`,
    tenant: "tag.tenant",
    audit: false,
  })}
  ${ctx.hook("after_tag_apply", [
    ["uuid", "tag.tag_id"],
    ["text", "tag.subject_type"],
    ["text", "tag.subject_id"],
  ])}
  return true;
end;
$$;
${userGrant(`${fn("tag")}(${ctx.idType}, text, text, uuid)`)}

${["", ", jsonb", ...(extras.length === 0 ? [", jsonb, jsonb"] : [])]
  .map(
    (tail) => `drop function if exists ${fn("update_tag")}(uuid, text${tail});`,
  )
  .join("\n")}
-- patch: name, slug, color, description and kind to set; a key that is
-- present sets its column, so null clears color or description.
create or replace function ${fn("update_tag")}(tag_id uuid, name text, patch jsonb default null${extra.param})
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select ${tenant} into v_tenant from ${tags} where ${id} = update_tag.tag_id;
  if not found then
    ${fail("TAG_NOT_FOUND", "tag not found", "P0002")}
  end if;
  if not (auth.role() = 'service_role' or ${ctx.scope.can("v_tenant", update)}) then
    ${fail("TAG_FORBIDDEN", "not allowed to manage tags")}
  end if;
  if update_tag.patch is not null and (jsonb_typeof(update_tag.patch) <> 'object'
    or update_tag.patch ? 'slug' and coalesce(update_tag.patch ->> 'slug', '') !~ ${SLUG}
    or update_tag.patch ? 'name' and nullif(trim(update_tag.patch ->> 'name'), '') is null
    or update_tag.patch ? 'kind' and update_tag.patch ->> 'kind' is null) then
    ${fail("TAG_INVALID", "patch sets name, slug, color, description or kind; name, slug and kind can't be empty", "22023")}
  end if;
  update ${tags} t set ${name} = coalesce(update_tag.patch ->> 'name', update_tag.name, t.${name}),
    ${slug} = case when update_tag.patch ? 'slug' then update_tag.patch ->> 'slug' else t.${slug} end,
    ${color} = case when update_tag.patch ? 'color' then update_tag.patch ->> 'color' else t.${color} end,
    ${description} = case when update_tag.patch ? 'description' then update_tag.patch ->> 'description' else t.${description} end,
    ${kind} = case when update_tag.patch ? 'kind' then ${ctx.cast("tags", "kind", "update_tag.patch ->> 'kind'")} else t.${kind} end,
    ${updatedAt} = now() where t.${id} = update_tag.tag_id;${writeExtraColumns(tags, extras, "update_tag.fields", `x.${id} = update_tag.tag_id`)}
  ${ctx.record({
    type: "tag.updated",
    payload: `jsonb_build_object('organizationId', v_tenant, 'id', update_tag.tag_id, 'name', coalesce(update_tag.patch ->> 'name', update_tag.name))`,
    subject: `'tags/' || update_tag.tag_id::text`,
    tenant: "v_tenant",
    audit: false,
  })}
  return true;
end;
$$;
${userGrant(`${fn("update_tag")}(uuid, text, jsonb${extra.type})`)}
${ranked ? rankTag(ctx, { tags, id, tenant, rank, updatedAt, manage: update }) : ""}
create or replace function ${fn("delete_tag")}(tag_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select ${tenant} into v_tenant from ${tags} where ${id} = delete_tag.tag_id;
  if not found then
    ${fail("TAG_NOT_FOUND", "tag not found", "P0002")}
  end if;
  if not (auth.role() = 'service_role' or ${ctx.scope.can("v_tenant", remove)}) then
    ${fail("TAG_FORBIDDEN", "not allowed to manage tags")}
  end if;
  delete from ${tags} where ${id} = delete_tag.tag_id;
  ${ctx.record({
    type: "tag.deleted",
    payload: `jsonb_build_object('organizationId', v_tenant, 'id', delete_tag.tag_id)`,
    subject: `'tags/' || delete_tag.tag_id::text`,
    tenant: "v_tenant",
    audit: false,
  })}
  return true;
end;
$$;
${userGrant(`${fn("delete_tag")}(uuid)`)}

create or replace function ${fn("untag")}(tenant ${ctx.idType}, subject_type text, subject_id text, tag_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  ${ctx.scope.bind("untag.tenant")}if not (${mayApply("untag.tenant")}) then
    ${fail("TAG_FORBIDDEN", "not allowed to apply tags")}
  end if;
  if not (${readable({ type: "untag.subject_type", id: "untag.subject_id", tenant: "untag.tenant" }, "write")}) then
    ${fail("TAG_SUBJECT_FORBIDDEN", "not allowed to tag this record")}
  end if;
  ${untagBody(ctx, bound, taggings)}
  ${ctx.record({
    type: "subject.untagged",
    payload: `jsonb_build_object('organizationId', untag.tenant, 'subjectType', untag.subject_type, 'subjectId', untag.subject_id, 'id', untag.tag_id)`,
    subject: `'subjects/' || untag.subject_type || '/' || untag.subject_id`,
    tenant: "untag.tenant",
    audit: false,
  })}
  return true;
end;
$$;
${userGrant(`${fn("untag")}(${ctx.idType}, text, text, uuid)`)}

-- The tenant's tags of one kind (every kind when it is null), in rank order.
create or replace function ${fn("list_tags")}(tenant ${ctx.idType}, kind text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  ${ctx.scope.bind("list_tags.tenant")}if not (auth.role() = 'service_role' or ${ctx.scope.can("list_tags.tenant", read)} or ${ctx.scope.can("list_tags.tenant", manage)}) then
    ${fail("TAG_FORBIDDEN", "not allowed to read tags")}
  end if;
  return coalesce((
    select jsonb_agg(${tagJson(ctx, "t", extras)} order by ${ranked ? `t.${rank} collate "C", ` : ""}t.${name}, t.${id})
    from ${tags} t
    where ${ctx.scope.eq(`t.${tenant}`, "list_tags.tenant")}
      and (list_tags.kind is null or t.${kind} = ${ctx.cast("tags", "kind", "list_tags.kind")})
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_tags")}(${ctx.idType}, text)`)}

-- The tags on one subject, for a caller who can read the tenant's tags and the subject.
create or replace function ${fn("subject_tags")}(tenant ${ctx.idType}, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_ids uuid[];
begin
  ${ctx.scope.bind("subject_tags.tenant")}if not (auth.role() = 'service_role' or ${ctx.scope.can("subject_tags.tenant", read)} or ${ctx.scope.can("subject_tags.tenant", manage)}) then
    ${fail("TAG_FORBIDDEN", "not allowed to read tags")}
  end if;
  if not (${readable({ type: "subject_tags.subject_type", id: "subject_tags.subject_id", tenant: "subject_tags.tenant" }, "read")}) then
    ${fail("TAG_SUBJECT_FORBIDDEN", "not allowed to read this record's tags")}
  end if;
  ${subjectTagIds(ctx, bound, taggings)}
  return coalesce((
    select jsonb_agg(${tagJson(ctx, "t", extras)} order by ${ranked ? `t.${rank} collate "C", ` : ""}t.${name}, t.${id})
    from ${tags} t
    where ${ctx.scope.eq(`t.${tenant}`, "subject_tags.tenant")}
      and t.${id} = any (v_ids)
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("subject_tags")}(${ctx.idType}, text, text)`)}${
    taggings === ""
      ? ""
      : subjectMergeHandler(
          ctx,
          list,
          moveSubjectRows(
            {
              table: taggings,
              type: ctx.col("taggings", "subjectType"),
              id: ctx.col("taggings", "subjectId"),
              unique: [ctx.col("taggings", "tag")],
            },
            "v_type",
          ),
        )
  }
`;
}

/** One tag row as the JSON `list_tags` and `subject_tags` return. */
function tagJson(
  ctx: BlockSqlContext,
  alias: string,
  extras: readonly ExtraColumn[],
): string {
  const col = (logical: string): string =>
    `${alias}.${ctx.col("tags", logical)}`;

  return `jsonb_build_object('id', ${col("id")}, 'kind', ${col("kind")}, 'name', ${col("name")}, 'slug', ${col("slug")}, 'color', ${col("color")}, 'description', ${col("description")}${ctx.has("tags", "rank") ? `, 'rank', ${col("rank")}` : ""}${extraFieldsJson(alias, extras)})`;
}

/**
 * Fills `v_ids` with the tag ids on `subject_tags`' subject, from its link
 * table.
 */
function subjectTagIds(
  ctx: BlockSqlContext,
  bound: readonly SubjectTableBinding[],
  taggings: string,
): string {
  const polymorphic =
    taggings === ""
      ? fail("TAG_SUBJECT_UNKNOWN", "this subject has no link table", "22023")
      : `select array_agg(g.${ctx.col("taggings", "tag")}) into v_ids from ${taggings} g
      where ${ctx.scope.eq(`g.${ctx.col("taggings", "tenant")}`, "subject_tags.tenant")}
        and g.${ctx.col("taggings", "subjectType")} = ${ctx.cast("taggings", "subjectType", "subject_tags.subject_type")}
        and g.${ctx.col("taggings", "subjectId")} = subject_tags.subject_id;`;

  if (bound.length === 0) {
    return polymorphic;
  }

  const whens = bound
    .map((link) => {
      const subject = link.columns["subject"] ?? "subject";
      const tagCol = link.columns["tag"] ?? "tag";

      return `    when ${sqlString(link.type)} then
      select array_agg(l.${sqlIdent(tagCol)}) into v_ids from ${link.qualified} l where l.${sqlIdent(subject)}::text = subject_tags.subject_id;`;
    })
    .join("\n");

  return `case subject_tags.subject_type
${whens}
    else
      ${polymorphic}
  end case;`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  const extra = extraFieldsArg(ctx.extraColumns("tags", RESERVED)).contract;

  return [
    {
      name: "create_tag",
      args: ["{id}", "text", "text", "text", "text", "text", ...extra],
      returns: "jsonb",
    },
    { name: "tag", args: ["{id}", "text", "text", "uuid"], returns: "boolean" },
    { name: "list_tags", args: ["{id}", "text"], returns: "jsonb" },
    { name: "subject_tags", args: ["{id}", "text", "text"], returns: "jsonb" },
    ...(ctx.has("tags", "rank")
      ? [{ name: "rank_tag", args: ["uuid", "text"], returns: "boolean" }]
      : []),
  ];
}

interface RankTagNames {
  readonly tags: string;
  readonly id: string;
  readonly tenant: string;
  readonly rank: string;
  readonly updatedAt: string;
  readonly manage: string;
}

function rankTag(ctx: BlockSqlContext, names: RankTagNames): string {
  const { tags, id, tenant, rank, updatedAt, manage } = names;

  return `
-- Sets a tag's rank key, from rankBetween over its neighbours' keys.
create or replace function ${ctx.fn("rank_tag")}(tag_id uuid, rank text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  if rank_tag.rank is null or rank_tag.rank !~ ${RANK_KEY_PATTERN} then
    ${fail("TAG_RANK_INVALID", "not a rank key", "22023")}
  end if;
  select ${tenant} into v_tenant from ${tags} where ${id} = rank_tag.tag_id;
  if not found then
    ${fail("TAG_NOT_FOUND", "tag not found", "P0002")}
  end if;
  if not (auth.role() = 'service_role' or ${ctx.scope.can("v_tenant", manage)}) then
    ${fail("TAG_FORBIDDEN", "not allowed to manage tags")}
  end if;
  update ${tags} set ${rank} = rank_tag.rank, ${updatedAt} = now() where ${id} = rank_tag.tag_id;
  return true;
end;
$$;
${userGrant(`${ctx.fn("rank_tag")}(uuid, text)`)}
`;
}

const CONTRIBUTES: BlockContributes = {
  bulk: (own) => [
    {
      name: "tags.set",
      declare: "v_tag uuid;",
      run: `for v_tag in select value::uuid from jsonb_array_elements_text(coalesce(bulk_row.args -> 'add', '[]'::jsonb)) loop
  perform ${own.fn("tag")}(bulk_row.tenant, bulk_row.subject_type, bulk_row.subject_id, v_tag);
end loop;
for v_tag in select value::uuid from jsonb_array_elements_text(coalesce(bulk_row.args -> 'remove', '[]'::jsonb)) loop
  perform ${own.fn("untag")}(bulk_row.tenant, bulk_row.subject_type, bulk_row.subject_id, v_tag);
end loop;`,
    },
  ],
};

export const TAGS: BlockSqlDefinition = {
  contributes: CONTRIBUTES,
  name: "tags",
  scopes: ["tenant", "user", "none"],
  title: "Tags",
  description:
    "Tenant tags with a kind, and a link from a tag to a subject. Over the app's tables it can use one link table per subject.",
  requires: ["memberships", "permissions"],
  integrates: ["outbox", "drive", "subjects"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 2,
  upgrades: [
    {
      from: 1,
      description:
        "Tags order by a fractional rank key instead of an integer position; rank_tag sets it.",
      sql: (ctx) => {
        if (!ctx.owns("tags")) {
          return "";
        }

        const tags = ctx.table("tags");
        const rank = ctx.col("tags", "rank");

        return `alter table ${tags} add column if not exists ${rank} text collate "C";
${rankBackfill({
  table: tags,
  id: ctx.col("tags", "id"),
  rank,
  partition: [ctx.col("tags", "tenant"), ctx.col("tags", "kind")],
  orderBy: `position, ${ctx.col("tags", "name")}, ${ctx.col("tags", "id")}`,
})}
alter table ${tags} alter column ${rank} set default 'V', alter column ${rank} set not null;
alter table ${tags} drop column if exists position;`;
      },
    },
  ],
  names: NAMES,
  contract,
  build,
  appSubjectTables(ctx) {
    return links(ctx).map((link) => ({
      logical: `links_${link.type}`,
      schema: link.schema,
      table: link.table,
      columns: {
        subject: link.columns["subject"] ?? null,
        tag: link.columns["tag"] ?? null,
        tenant: link.columns["tenant"] ?? null,
        createdAt: link.columns["createdAt"] ?? null,
      },
    }));
  },
};
