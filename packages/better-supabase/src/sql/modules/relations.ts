import type { RelationsEvents } from "../../blocks/relations/events.ts";
import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import { sqlString } from "../../core/template.ts";
import {
  addExtraColumns,
  columnsObject,
  extraFieldsArg,
  extraFieldsJson,
  fail,
  lockTable,
  schemaPreamble,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import {
  type Subject,
  qualifiedTable,
  subjectCascades,
  subjectReadable,
  subjectsOption,
} from "../subjects.ts";
import { OPERATIONS } from "./access-model.ts";

/** How a kind of link behaves. */
export interface RelationKind {
  /** The name of the link read from the target's side, such as `blocked_by`. */
  readonly inverse?: string;
  /** Refuse a link that would close a cycle of this kind. */
  readonly acyclic?: boolean;
  /** `one`: a source has at most one target of this kind; a new link replaces it. */
  readonly cardinality?: "one" | "many";
  /** The link reads the same from both ends; it is stored once. */
  readonly symmetric?: boolean;
}

/** The kinds `options.kinds` falls back to. */
const DEFAULT_RELATION_KINDS: Readonly<Record<string, RelationKind>> = {
  blocks: { inverse: "blocked_by", acyclic: true },
  parent: { inverse: "children", cardinality: "one", acyclic: true },
  relates: { symmetric: true },
  created_from: { inverse: "converted_to", cardinality: "one", acyclic: true },
};

/** The aggregates `rollup` accepts. */
const RELATION_ROLLUPS = ["count", "sum", "avg", "min", "max"] as const;

const NAME: RegExp = /^[a-z][a-z0-9_]{0,62}$/;
const MAX_DATA_BYTES = 8192;
const MAX_DEPTH = 100;
const MAX_EDGES = 10_000;

const EVENTS: ModuleEvents<RelationsEvents> = {
  "subject.linked": {
    subject: "subjects",
    payload: [
      "organizationId",
      "id",
      "kind",
      "subjectType",
      "subjectId",
      "targetType",
      "targetId",
    ],
  },
  "subject.unlinked": {
    subject: "subjects",
    payload: [
      "organizationId",
      "id",
      "kind",
      "subjectType",
      "subjectId",
      "targetType",
      "targetId",
    ],
  },
};

const NAMES: ModuleNames = {
  events: EVENTS,
  hooks: ["before_relation_link", "after_relation_link"],
  options: ["kinds", "subjects", "extraColumns"],
  tables: {
    relations: {
      name: "relations",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        kind: "kind",
        sourceType: "source_type",
        sourceId: "source_id",
        targetType: "target_type",
        targetId: "target_id",
        data: "data",
        createdBy: "created_by",
        createdAt: "created_at",
      },
    },
  },
};

interface ResolvedKind {
  readonly name: string;
  readonly inverse: string | undefined;
  readonly acyclic: boolean;
  readonly single: boolean;
  readonly symmetric: boolean;
}

/** `options.kinds`, checked: names, inverses that clash, and symmetric kinds without direction. */
function relationKinds(ctx: ModuleContext): readonly ResolvedKind[] {
  const where = "blocks.relations.options.kinds";
  const raw: unknown = ctx.option("kinds") ?? DEFAULT_RELATION_KINDS;
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    throw new TypeError(`${where} must be an object of kind name to options`);
  }
  const kinds: ResolvedKind[] = [];
  const names = new Set<string>();
  const claim = (name: string): void => {
    if (!NAME.test(name)) {
      throw new TypeError(
        `${where}: "${name}" must be lowercase letters, digits and underscores`,
      );
    }
    if (names.has(name)) {
      throw new TypeError(`${where}: "${name}" is named twice`);
    }
    names.add(name);
  };
  for (const [name, value] of new Map<string, unknown>(Object.entries(raw))) {
    claim(name);
    if (typeof value !== "object" || value === null || Array.isArray(value)) {
      throw new TypeError(`${where}.${name} must be an object`);
    }
    const entry = new Map<string, unknown>(Object.entries(value));
    for (const key of entry.keys()) {
      if (!["inverse", "acyclic", "cardinality", "symmetric"].includes(key)) {
        throw new TypeError(
          `${where}.${name}.${key} is not an option. Options: inverse, acyclic, cardinality, symmetric`,
        );
      }
    }
    const inverse = entry.get("inverse");
    if (inverse !== undefined && typeof inverse !== "string") {
      throw new TypeError(`${where}.${name}.inverse must be a string`);
    }
    const cardinality = entry.get("cardinality") ?? "many";
    if (cardinality !== "one" && cardinality !== "many") {
      throw new TypeError(`${where}.${name}.cardinality must be one or many`);
    }
    const symmetric = entry.get("symmetric") === true;
    if (symmetric && (inverse !== undefined || cardinality === "one")) {
      throw new TypeError(
        `${where}.${name}: a symmetric kind has no inverse and no cardinality`,
      );
    }
    if (inverse !== undefined) claim(inverse);
    kinds.push({
      name,
      inverse,
      acyclic: entry.get("acyclic") === true,
      single: cardinality === "one",
      symmetric,
    });
  }
  return kinds;
}

/** A `values` list of every name a caller may pass, with the kind it stands for. */
function kindTable(kinds: readonly ResolvedKind[]): string {
  const rows = kinds.flatMap((kind) => {
    const flags = `${String(kind.acyclic)}, ${String(kind.single)}, ${String(kind.symmetric)}`;
    const own = `(${sqlString(kind.name)}, ${sqlString(kind.name)}, false, ${flags}, ${sqlString(kind.inverse ?? kind.name)})`;
    return kind.inverse === undefined
      ? [own]
      : [
          own,
          `(${sqlString(kind.inverse)}, ${sqlString(kind.name)}, true, ${flags}, ${sqlString(kind.name)})`,
        ];
  });
  return `(values ${rows.join(", ")}) as k(name, canonical, inverted, acyclic, single, both_ways, opposite)`;
}

/** Subject type to table, id column and id type, for `rollup`. */
function subjectTables(list: readonly (readonly [string, Subject])[]): string {
  if (list.length === 0) return "";
  return list
    .map(
      ([type, subject]) =>
        `    when ${sqlString(type)} then v_table := ${sqlString(qualifiedTable(subject.table))}; v_id_col := ${sqlString(subject.id ?? "id")}; v_tenant_col := ${subject.tenant === false ? "null" : sqlString(subject.tenant ?? "organization_id")};`,
    )
    .join("\n");
}

/**
 * `options.extraColumns`, added to a managed relations table. The keys
 * `relations_of` returns next to them are reserved.
 */
const extrasOf = (ctx: ModuleContext) =>
  ctx.extraColumns("relations", [
    "direction",
    "type",
    "other_type",
    "other_id",
  ]);

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const extras = extrasOf(ctx);
  const relations = ctx.table("relations");
  const c = (column: string): string => ctx.col("relations", column);
  const [id, tenant, kind, sourceType, sourceId, targetType, targetId, data] = [
    c("id"),
    c("tenant"),
    c("kind"),
    c("sourceType"),
    c("sourceId"),
    c("targetType"),
    c("targetId"),
    c("data"),
  ];
  const createdBy = c("createdBy");
  const createdAt = c("createdAt");
  const read = ctx.permission("read", OPERATIONS["relations.read"]);
  const manage = ctx.permission("manage", OPERATIONS["relations.manage"]);
  const kinds = relationKinds(ctx);
  const list = subjectsOption(ctx);
  const kindsOf = kindTable(kinds);
  const fn = (value: string): string => ctx.fn(value);
  const readable = (prefix: string, type: string, idValue: string): string =>
    subjectReadable(ctx, list, {
      type,
      id: idValue,
      tenant: `${prefix}.tenant`,
    });
  const tables = ctx.manages
    ? `create table if not exists ${relations} (
  ${id} uuid primary key default gen_random_uuid(),
  ${tenant} ${ctx.idType} not null,
  ${kind} text not null,
  ${sourceType} text not null,
  ${sourceId} text not null,
  ${targetType} text not null,
  ${targetId} text not null,
  ${data} jsonb not null default '{}'::jsonb check (jsonb_typeof(${data}) = 'object' and pg_column_size(${data}) <= ${String(MAX_DATA_BYTES)}),
  ${createdBy} uuid,
  ${createdAt} timestamptz not null default now(),
  unique (${tenant}, ${kind}, ${sourceType}, ${sourceId}, ${targetType}, ${targetId}),
  check (not (${sourceType} = ${targetType} and ${sourceId} = ${targetId}))
);
create index if not exists relations_target_idx on ${relations} (${tenant}, ${targetType}, ${targetId}, ${kind});${addExtraColumns(relations, extras)}
${lockTable(relations, { read: true })}
`
    : "";
  const cascades = subjectCascades(
    ctx,
    list,
    `delete from ${relations}
  where (${sourceType} = v_type and ${sourceId} = v_id)
     or (${targetType} = v_type and ${targetId} = v_id);`,
  );
  // Puts (source, target) in the stored direction: an inverse name swaps the
  // ends, and a symmetric kind stores the smaller end first.
  const canonical = (prefix: string): string => `
  select k.canonical, k.inverted, k.acyclic, k.single, k.both_ways
    into v_kind, v_inverted, v_acyclic, v_single, v_symmetric
    from ${kindsOf} where k.name = ${prefix}.kind;
  if v_kind is null then
    ${fail("RELATION_KIND_UNKNOWN", "unknown relation kind", "22023")}
  end if;
  if v_inverted then
    v_source_type := ${prefix}.target_type; v_source_id := ${prefix}.target_id;
    v_target_type := ${prefix}.source_type; v_target_id := ${prefix}.source_id;
  else
    v_source_type := ${prefix}.source_type; v_source_id := ${prefix}.source_id;
    v_target_type := ${prefix}.target_type; v_target_id := ${prefix}.target_id;
  end if;
  if v_symmetric and (v_source_type, v_source_id) > (v_target_type, v_target_id) then
    select v_target_type, v_target_id, v_source_type, v_source_id
      into v_source_type, v_source_id, v_target_type, v_target_id;
  end if;`;
  const canonicalVars = `  v_kind text;
  v_inverted boolean;
  v_acyclic boolean;
  v_single boolean;
  v_symmetric boolean;
  v_source_type text;
  v_source_id text;
  v_target_type text;
  v_target_id text;`;
  const event = (
    type: "subject.linked" | "subject.unlinked",
    idValue: string,
    tenantValue: string,
  ): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${tenantValue}, 'id', ${idValue}, 'kind', v_kind, 'subjectType', v_source_type, 'subjectId', v_source_id, 'targetType', v_target_type, 'targetId', v_target_id)`,
      subject: `'subjects/' || v_source_type || '/' || v_source_id`,
      tenant: tenantValue,
      audit: false,
    });
  const tableCase = subjectTables(list);
  return `${schemaPreamble(ctx)}
${tables}
drop policy if exists relations_read on ${relations};
create policy relations_read on ${relations} for select to authenticated
using (${tenant} in (select ${ctx.scope.ids(read)}));

-- Links two subjects. An inverse name (blocked_by) stores the link from the
-- other end. Acyclic kinds take an advisory lock per tenant and kind, then
-- refuse a link whose target already reaches its source.
${extraFieldsArg(extras).drop(fn("link"), `${ctx.idType}, text, text, text, text, text, jsonb`)}
create or replace function ${fn("link")}(tenant ${ctx.idType}, kind text, source_type text, source_id text, target_type text, target_id text, data jsonb${extraFieldsArg(extras).param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
${canonicalVars}
  v_id uuid;
  v_created boolean := false;
  v_previous jsonb;
  v_replaced jsonb;
  v_old ${relations};
begin
  if not (auth.role() = 'service_role' or ${ctx.scope.can("link.tenant", manage)}) then
    ${fail("RELATION_FORBIDDEN", "not allowed to link records")}
  end if;
  if link.data is not null and jsonb_typeof(link.data) <> 'object' then
    ${fail("RELATION_INVALID", "data must be an object", "22023")}
  end if;
  if link.source_type = link.target_type and link.source_id = link.target_id then
    ${fail("RELATION_SELF", "a record can't link to itself", "22023")}
  end if;
${canonical("link")}
  if not (${readable("link", "link.source_type", "link.source_id")})
     or not (${readable("link", "link.target_type", "link.target_id")}) then
    ${fail("RELATION_SUBJECT_FORBIDDEN", "not allowed to link these records")}
  end if;
  ${ctx.hook("before_relation_link", [
    [ctx.idType, "link.tenant"],
    ["text", "v_kind"],
    ["text", "v_source_type"],
    ["text", "v_source_id"],
    ["text", "v_target_type"],
    ["text", "v_target_id"],
  ])}
  if v_acyclic or v_single then
    perform pg_advisory_xact_lock(hashtext(link.tenant::text || ':relations:' || v_kind));
  end if;
  select ${id}, ${data} into v_id, v_previous from ${relations}
    where ${tenant} = link.tenant and ${kind} = v_kind
      and ${sourceType} = v_source_type and ${sourceId} = v_source_id
      and ${targetType} = v_target_type and ${targetId} = v_target_id;
  if v_id is null then
    if v_acyclic and exists (
      with recursive reach(t, i, depth) as (
        select v_target_type, v_target_id, 0
        union
        select r.${targetType}, r.${targetId}, reach.depth + 1
        from ${relations} r join reach
          on r.${sourceType} = reach.t and r.${sourceId} = reach.i
        where r.${tenant} = link.tenant and r.${kind} = v_kind and reach.depth < ${String(MAX_DEPTH * 10)}
      )
      select 1 from reach where t = v_source_type and i = v_source_id
    ) then
      ${fail("RELATION_CYCLE", "this link would create a cycle", "23514")}
    end if;
    if v_single then
      delete from ${relations}
        where ${tenant} = link.tenant and ${kind} = v_kind
          and ${sourceType} = v_source_type and ${sourceId} = v_source_id
        returning * into v_old;
      if v_old.${id} is not null then
        v_replaced := jsonb_build_object('targetType', v_old.${targetType}, 'targetId', v_old.${targetId}, 'data', v_old.${data});
        ${ctx.record({
          type: "subject.unlinked",
          payload: `jsonb_build_object('organizationId', link.tenant, 'id', v_old.${id}, 'kind', v_kind, 'subjectType', v_source_type, 'subjectId', v_source_id, 'targetType', v_old.${targetType}, 'targetId', v_old.${targetId})`,
          subject: `'subjects/' || v_source_type || '/' || v_source_id`,
          tenant: "link.tenant",
          audit: false,
        })}
      end if;
    end if;
    insert into ${relations} (${tenant}, ${kind}, ${sourceType}, ${sourceId}, ${targetType}, ${targetId}, ${data}, ${createdBy})
    values (link.tenant, v_kind, v_source_type, v_source_id, v_target_type, v_target_id, coalesce(link.data, '{}'::jsonb), auth.uid())
    returning ${id} into v_id;
    v_created := true;
    ${event("subject.linked", "v_id", "link.tenant")}
  elsif link.data is not null then
    update ${relations} set ${data} = link.data where ${id} = v_id;
  end if;${writeExtraColumns(relations, extras, "link.fields", `x.${id} = v_id`)}
  ${ctx.hook("after_relation_link", [["uuid", "v_id"]])}
  return jsonb_build_object(
    'id', v_id, 'kind', v_kind, 'created', v_created,
    'sourceType', v_source_type, 'sourceId', v_source_id,
    'targetType', v_target_type, 'targetId', v_target_id,
    'previousData', case when v_created then null else v_previous end,
    'replaced', v_replaced${
      extras.length === 0
        ? ""
        : `,
    'fields', (select ${columnsObject(
      "r",
      extras.map((extra) => extra.name),
    )} from ${relations} r where r.${id} = v_id)`
    });
end;
$$;
${userGrant(`${fn("link")}(${ctx.idType}, text, text, text, text, text, jsonb${extraFieldsArg(extras).type})`)}

create or replace function ${fn("unlink")}(tenant ${ctx.idType}, kind text, source_type text, source_id text, target_type text, target_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
${canonicalVars}
  v_old ${relations};
begin
  if not (auth.role() = 'service_role' or ${ctx.scope.can("unlink.tenant", manage)}) then
    ${fail("RELATION_FORBIDDEN", "not allowed to unlink records")}
  end if;
${canonical("unlink")}
  if not (${readable("unlink", "unlink.source_type", "unlink.source_id")})
     or not (${readable("unlink", "unlink.target_type", "unlink.target_id")}) then
    ${fail("RELATION_SUBJECT_FORBIDDEN", "not allowed to unlink these records")}
  end if;
  delete from ${relations}
    where ${tenant} = unlink.tenant and ${kind} = v_kind
      and ${sourceType} = v_source_type and ${sourceId} = v_source_id
      and ${targetType} = v_target_type and ${targetId} = v_target_id
    returning * into v_old;
  if v_old.${id} is null then
    return jsonb_build_object('removed', false, 'data', null);
  end if;
  ${event("subject.unlinked", `v_old.${id}`, "unlink.tenant")}
  return jsonb_build_object('removed', true, 'data', v_old.${data});
end;
$$;
${userGrant(`${fn("unlink")}(${ctx.idType}, text, text, text, text, text)`)}

-- A subject's links in both directions, each named from the subject's side.
create or replace function ${fn("relations_of")}(tenant ${ctx.idType}, subject_type text, subject_id text, kind text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', e.id, 'kind', n.seen, 'direction', e.direction,
    'type', e.other_type, 'subjectId', e.other_id,
    'data', e.data, 'createdAt', e.created_at${extras.length === 0 ? "" : ", 'fields', e.fields"}
  ) order by n.seen, e.created_at, e.id), '[]'::jsonb)
  from (
    select r.${id} as id, r.${kind} as canonical, 'out' as direction,
      r.${targetType} as other_type, r.${targetId} as other_id, r.${data} as data, r.${createdAt} as created_at${
        extras.length === 0
          ? ""
          : `, ${columnsObject(
              "r",
              extras.map((extra) => extra.name),
            )} as fields`
      }
    from ${relations} r
    where r.${tenant} = relations_of.tenant and r.${sourceType} = relations_of.subject_type and r.${sourceId} = relations_of.subject_id
    union all
    select r.${id}, r.${kind}, 'in', r.${sourceType}, r.${sourceId}, r.${data}, r.${createdAt}${
      extras.length === 0
        ? ""
        : `, ${columnsObject(
            "r",
            extras.map((extra) => extra.name),
          )}`
    }
    from ${relations} r
    where r.${tenant} = relations_of.tenant and r.${targetType} = relations_of.subject_type and r.${targetId} = relations_of.subject_id
  ) e
  cross join lateral (
    select case when e.direction = 'in' and not k.both_ways then k.opposite else k.canonical end as seen
    from ${kindsOf}
    where k.name = e.canonical
  ) n
  where relations_of.kind is null or n.seen = relations_of.kind
$$;
${userGrant(`${fn("relations_of")}(${ctx.idType}, text, text, text)`)}

-- Every link of one kind in a tenant, for a Gantt chart or a tree.
create or replace function ${fn("relations_by_kind")}(tenant ${ctx.idType}, kind text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', r.${id}, 'kind', r.${kind},
    'sourceType', r.${sourceType}, 'sourceId', r.${sourceId},
    'targetType', r.${targetType}, 'targetId', r.${targetId},
    'data', r.${data}${extraFieldsJson("r", extras)}
  ) order by r.${createdAt}, r.${id}), '[]'::jsonb)
  from (
    select * from ${relations} r
    where r.${tenant} = relations_by_kind.tenant
      and r.${kind} = (select k.canonical from ${kindsOf} where k.name = relations_by_kind.kind)
    order by r.${createdAt}, r.${id}
    limit ${String(MAX_EDGES)}
  ) r
$$;
${userGrant(`${fn("relations_by_kind")}(${ctx.idType}, text)`)}

-- Every record a subject reaches through links of one kind, with its depth.
-- up follows source to target (a parent's parents); down follows target to source.
create or replace function ${fn("relation_walk")}(tenant ${ctx.idType}, kind text, subject_type text, subject_id text, up boolean, max_depth integer)
returns table (type text, id text, depth integer)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_kind text;
  v_inverted boolean;
  v_up boolean;
begin
  select k.canonical, k.inverted into v_kind, v_inverted from ${kindsOf} where k.name = relation_walk.kind;
  if v_kind is null then
    ${fail("RELATION_KIND_UNKNOWN", "unknown relation kind", "22023")}
  end if;
  v_up := relation_walk.up <> v_inverted;
  return query
  with recursive walk(t, i, d) as (
    select relation_walk.subject_type, relation_walk.subject_id, 0
    union
    select case when v_up then r.${targetType} else r.${sourceType} end,
      case when v_up then r.${targetId} else r.${sourceId} end,
      walk.d + 1
    from ${relations} r join walk on (
      case when v_up then r.${sourceType} = walk.t and r.${sourceId} = walk.i
      else r.${targetType} = walk.t and r.${targetId} = walk.i end)
    where r.${tenant} = relation_walk.tenant and r.${kind} = v_kind
      and walk.d < least(coalesce(relation_walk.max_depth, ${String(MAX_DEPTH)}), ${String(MAX_DEPTH)})
  )
  select w.t, w.i, min(w.d)::integer from walk w where w.d > 0
  group by w.t, w.i
  order by min(w.d), w.t, w.i;
end;
$$;
${userGrant(`${fn("relation_walk")}(${ctx.idType}, text, text, text, boolean, integer)`)}

create or replace function ${fn("ancestors")}(tenant ${ctx.idType}, kind text, subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('type', w.type, 'id', w.id, 'depth', w.depth) order by w.depth, w.type, w.id), '[]'::jsonb)
  from ${fn("relation_walk")}(ancestors.tenant, ancestors.kind, ancestors.subject_type, ancestors.subject_id, true, null) w
$$;
${userGrant(`${fn("ancestors")}(${ctx.idType}, text, text, text)`)}

create or replace function ${fn("descendants")}(tenant ${ctx.idType}, kind text, subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('type', w.type, 'id', w.id, 'depth', w.depth) order by w.depth, w.type, w.id), '[]'::jsonb)
  from ${fn("relation_walk")}(descendants.tenant, descendants.kind, descendants.subject_type, descendants.subject_id, false, null) w
$$;
${userGrant(`${fn("descendants")}(${ctx.idType}, text, text, text)`)}

-- The record of into_type an origin was already converted into: the source
-- of a created_from link whose target is the origin. Conversions call it
-- first, so converting the same deal twice returns the first quote.
create or replace function ${fn("converted_into")}(tenant ${ctx.idType}, origin_type text, origin_id text, into_type text)
returns text
language sql
stable
security invoker
set search_path = ''
as $$
  select r.${sourceId}
  from ${relations} r
  where r.${tenant} = converted_into.tenant
    and r.${kind} = (select k.canonical from ${kindsOf} where k.name = 'created_from')
    and r.${targetType} = converted_into.origin_type and r.${targetId} = converted_into.origin_id
    and r.${sourceType} = converted_into.into_type
  order by r.${createdAt}, r.${id}
  limit 1
$$;
${userGrant(`${fn("converted_into")}(${ctx.idType}, text, text, text)`)}

-- Aggregates a column over a subject's descendants of one type, such as the
-- sum of estimates under an epic. Runs as the caller, so the subject table's
-- policies decide which rows count. agg is count, sum, avg, min or max.
create or replace function ${fn("relation_rollup")}(tenant ${ctx.idType}, kind text, subject_type text, subject_id text, of_type text, column_name text, agg text)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_table text;
  v_id_col text;
  v_tenant_col text;
  v_ids text[];
  v_result jsonb;
begin
  if relation_rollup.agg is null or relation_rollup.agg not in (${RELATION_ROLLUPS.map((agg) => `'${agg}'`).join(", ")}) then
    ${fail("RELATION_ROLLUP_INVALID", "agg must be count, sum, avg, min or max", "22023")}
  end if;
  if relation_rollup.agg <> 'count' and relation_rollup.column_name is null then
    ${fail("RELATION_ROLLUP_INVALID", "this aggregate needs a column", "22023")}
  end if;
  ${
    tableCase === ""
      ? ""
      : `case relation_rollup.of_type
${tableCase}
    else null;
  end case;`
  }
  if v_table is null then
    ${fail("RELATION_SUBJECT_UNKNOWN", "this subject type has no table", "22023")}
  end if;
  select array_agg(w.id) into v_ids
  from ${fn("relation_walk")}(relation_rollup.tenant, relation_rollup.kind, relation_rollup.subject_type, relation_rollup.subject_id, false, null) w
  where w.type = relation_rollup.of_type;
  execute format(
    'select to_jsonb(%s) from %s s where s.%I::text = any ($1)%s',
    case when relation_rollup.agg = 'count' and relation_rollup.column_name is null then 'count(*)'
      else format('%s(s.%I)', relation_rollup.agg, relation_rollup.column_name) end,
    v_table,
    v_id_col,
    case when v_tenant_col is null then '' else format(' and s.%I = $2', v_tenant_col) end
  ) into v_result using coalesce(v_ids, '{}'::text[]), relation_rollup.tenant;
  return v_result;
end;
$$;
${userGrant(`${fn("relation_rollup")}(${ctx.idType}, text, text, text, text, text, text)`)}
${cascades}`;
}

function contract(ctx: ModuleContext): readonly ModuleContractFunction[] {
  return [
    {
      name: "link",
      args: [
        "{id}",
        "text",
        "text",
        "text",
        "text",
        "text",
        "jsonb",
        ...extraFieldsArg(extrasOf(ctx)).contract,
      ],
      returns: "jsonb",
    },
    {
      name: "unlink",
      args: ["{id}", "text", "text", "text", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "relations_of",
      args: ["{id}", "text", "text", "text"],
      returns: "jsonb",
    },
    { name: "relations_by_kind", args: ["{id}", "text"], returns: "jsonb" },
    {
      name: "ancestors",
      args: ["{id}", "text", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "descendants",
      args: ["{id}", "text", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "converted_into",
      args: ["{id}", "text", "text", "text"],
      returns: "text",
    },
    {
      name: "relation_rollup",
      args: ["{id}", "text", "text", "text", "text", "text", "text"],
      returns: "jsonb",
    },
  ];
}

export const RELATIONS: ModuleDefinition = {
  name: "relations",
  scopes: ["tenant"],
  title: "Relations",
  description:
    "Typed links between subjects (blocks, parent, relates, or your own kinds), with inverse names, cycle checks, one-target kinds, walks and rollups.",
  requires: ["tenant", "access"],
  integrates: ["outbox"],
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
