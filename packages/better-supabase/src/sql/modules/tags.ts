import type { TagsEvents } from "../../blocks/tags/events.ts";
import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { RANK_KEY_PATTERN, rankAfter, rankBackfill } from "../rank-sql.ts";
import { fail, lockTable, schemaPreamble, userGrant } from "../shared.ts";
import {
  type SubjectTableBinding,
  subjectReadable,
  subjectTableBindings,
  subjectsOption,
} from "../subjects.ts";
import { OPERATIONS } from "./access-model.ts";

const EVENTS: ModuleEvents<TagsEvents> = {
  "tag.created": {
    subject: "tags",
    payload: ["organizationId", "id", "kind", "name"],
  },
  "tag.updated": {
    subject: "tags",
    payload: ["organizationId", "id", "name"],
  },
  "tag.deleted": {
    subject: "tags",
    payload: ["organizationId", "id"],
  },
  "subject.tagged": {
    subject: "subjects",
    payload: ["organizationId", "subjectType", "subjectId", "id"],
  },
  "subject.untagged": {
    subject: "subjects",
    payload: ["organizationId", "subjectType", "subjectId", "id"],
  },
};

const NAMES: ModuleNames = {
  events: EVENTS,
  hooks: ["before_tag_apply", "after_tag_apply"],
  options: ["subjects"],
  tables: {
    tags: {
      name: "tags",
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
    },
    taggings: {
      name: "taggings",
      lifecycle: { tenant: "tenant", export: true },
      optionalTable: true,
      columns: {
        tenant: "tenant_id",
        tag: "tag_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        createdAt: "created_at",
      },
    },
  },
};

const LINK_COLUMNS = ["subject", "tag"] as const;

function subjects(ctx: ModuleContext) {
  return subjectsOption(ctx, ["links", "kinds"]);
}

function links(ctx: ModuleContext) {
  return subjectTableBindings(ctx, subjects(ctx), "links", {
    columns: [...LINK_COLUMNS],
    optional: ["tenant", "createdAt"],
  });
}

function kindsOf(extra: Readonly<Record<string, unknown>>): readonly string[] {
  const value = extra["kinds"];
  if (value === undefined) return [];
  if (!Array.isArray(value)) {
    throw new TypeError(
      "blocks.tags.options.subjects.<type>.kinds must be a list of strings",
    );
  }
  const kinds: string[] = [];
  for (const item of value) {
    if (typeof item !== "string" || item.length === 0) {
      throw new TypeError(
        "blocks.tags.options.subjects.<type>.kinds must be a list of strings",
      );
    }
    kinds.push(item);
  }
  return kinds;
}

function untagBody(
  ctx: ModuleContext,
  bound: readonly SubjectTableBinding[],
  taggings: string,
): string {
  const polymorphic =
    taggings === ""
      ? fail("TAG_SUBJECT_UNKNOWN", "this subject has no link table", "22023")
      : `delete from ${taggings}
      where ${ctx.col("taggings", "tenant")} = untag.tenant
        and ${ctx.col("taggings", "tag")} = untag.tag_id
        and ${ctx.col("taggings", "subjectType")} = untag.subject_type
        and ${ctx.col("taggings", "subjectId")} = untag.subject_id;`;
  if (bound.length === 0) return polymorphic;
  const whens = bound
    .map((link) => {
      const subject = link.columns["subject"] ?? "subject";
      const tagCol = link.columns["tag"] ?? "tag";
      return `    when ${sqlString(link.type)} then
      delete from ${link.qualified} where ${sqlIdent(subject)}::text = untag.subject_id and ${sqlIdent(tagCol)} = untag.tag_id;`;
    })
    .join("\n");
  return `case untag.subject_type
${whens}
    else
      ${polymorphic}
  end case;`;
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
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
  const bound = links(ctx);
  const list = subjects(ctx);
  const tables = ctx.manages
    ? `create table if not exists ${tags} (
  ${id} uuid primary key default gen_random_uuid(),
  ${tenant} ${ctx.idType} not null,
  ${kind} text not null,
  ${name} text not null check (length(${name}) between 1 and 80),
  ${slug} text not null,
  ${color} text,
  ${description} text,
${ranked ? `  ${rank} text collate "C" not null default 'V',\n` : ""}  ${createdAt} timestamptz not null default now(),
  ${updatedAt} timestamptz not null default now(),
  unique (${tenant}, ${kind}, ${slug})
);
${lockTable(tags, { read: true })}
create table if not exists ${taggings} (
  ${ctx.col("taggings", "tenant")} ${ctx.idType} not null,
  ${ctx.col("taggings", "tag")} uuid not null references ${tags} (${id}) on delete cascade,
  ${ctx.col("taggings", "subjectType")} text not null,
  ${ctx.col("taggings", "subjectId")} text not null,
  ${ctx.col("taggings", "createdAt")} timestamptz not null default now(),
  primary key (${ctx.col("taggings", "tag")}, ${ctx.col("taggings", "subjectType")}, ${ctx.col("taggings", "subjectId")})
);
${lockTable(taggings, { read: true })}
`
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
create or replace function ${fn("create_tag")}(tenant ${ctx.idType}, kind text, name text, color text, description text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_slug text := trim(both '-' from regexp_replace(lower(create_tag.name), '[^a-z0-9]+', '-', 'g'));
  v_last text;
  v_rank text;
begin
  if not (auth.role() = 'service_role' or ${ctx.scope.can("create_tag.tenant", manage)}) then
    ${fail("TAG_FORBIDDEN", "not allowed to manage tags")}
  end if;
${
  ranked
    ? `  select max(t.${rank} collate "C") into v_last from ${tags} t
    where t.${tenant} = create_tag.tenant and t.${kind} = create_tag.kind;
  v_rank := ${rankAfter("v_last")};
  insert into ${tags} (${tenant}, ${kind}, ${name}, ${slug}, ${color}, ${description}, ${rank}, ${createdAt})
  values (create_tag.tenant, create_tag.kind, create_tag.name, v_slug, create_tag.color, create_tag.description, v_rank, now())`
    : `  insert into ${tags} (${tenant}, ${kind}, ${name}, ${slug}, ${color}, ${description}, ${createdAt})
  values (create_tag.tenant, create_tag.kind, create_tag.name, v_slug, create_tag.color, create_tag.description, now())`
}
  returning ${id} into v_id;
  ${ctx.record({
    type: "tag.created",
    payload: `jsonb_build_object('organizationId', create_tag.tenant, 'id', v_id, 'kind', create_tag.kind, 'name', create_tag.name)`,
    subject: `'tags/' || v_id::text`,
    tenant: "create_tag.tenant",
    audit: false,
  })}
  return jsonb_build_object('id', v_id, 'slug', v_slug, 'rank', v_rank);
end;
$$;
${userGrant(`${fn("create_tag")}(${ctx.idType}, text, text, text, text)`)}

create or replace function ${fn("tag")}(tenant ${ctx.idType}, subject_type text, subject_id text, tag_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_kind text;
begin
  if not (${subjectReadable(ctx, list, { type: "tag.subject_type", id: "tag.subject_id", tenant: "tag.tenant" })}) then
    ${fail("TAG_SUBJECT_FORBIDDEN", "not allowed to tag this record")}
  end if;
  select ${kind} into v_kind from ${tags} where ${id} = tag.tag_id and ${tenant} = tag.tenant;
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
      values (tag.tenant, tag.tag_id, tag.subject_type, tag.subject_id)
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

create or replace function ${fn("update_tag")}(tag_id uuid, name text)
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
  if not (auth.role() = 'service_role' or ${ctx.scope.can("v_tenant", manage)}) then
    ${fail("TAG_FORBIDDEN", "not allowed to manage tags")}
  end if;
  update ${tags} set ${name} = coalesce(update_tag.name, ${name}), ${updatedAt} = now() where ${id} = update_tag.tag_id;
  ${ctx.record({
    type: "tag.updated",
    payload: `jsonb_build_object('organizationId', v_tenant, 'id', update_tag.tag_id, 'name', update_tag.name)`,
    subject: `'tags/' || update_tag.tag_id::text`,
    tenant: "v_tenant",
    audit: false,
  })}
  return true;
end;
$$;
${userGrant(`${fn("update_tag")}(uuid, text)`)}
${ranked ? rankTag(ctx, { tags, id, tenant, rank, updatedAt, manage }) : ""}
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
  if not (auth.role() = 'service_role' or ${ctx.scope.can("v_tenant", manage)}) then
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
  if not (${subjectReadable(ctx, list, { type: "untag.subject_type", id: "untag.subject_id", tenant: "untag.tenant" })}) then
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
`;
}

function contract(ctx: ModuleContext): readonly ModuleContractFunction[] {
  return [
    {
      name: "create_tag",
      args: ["{id}", "text", "text", "text", "text"],
      returns: "jsonb",
    },
    { name: "tag", args: ["{id}", "text", "text", "uuid"], returns: "boolean" },
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

function rankTag(ctx: ModuleContext, names: RankTagNames): string {
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

export const TAGS: ModuleDefinition = {
  name: "tags",
  title: "Tags",
  description:
    "Tenant tags with a kind, and a link from a tag to a subject. Adopt mode can use one link table per subject.",
  requires: ["tenant", "access"],
  integrates: ["outbox"],
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  version: 2,
  upgrades: [
    {
      from: 1,
      description:
        "Tags order by a fractional rank key instead of an integer position; rank_tag sets it.",
      sql: (ctx) => {
        if (!ctx.manages) return "";
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
  adoptSubjectTables(ctx) {
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
