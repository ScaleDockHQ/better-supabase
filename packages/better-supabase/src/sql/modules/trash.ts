import type { TrashEvents } from "../../blocks/trash/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockContributes } from "../contributions.ts";
import type { BlockSqlDefinition } from "../module-types.ts";
import type { Subject } from "../subjects.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  addExtraColumns,
  extraFieldsArg,
  extraFieldsJson,
  fail,
  lockTable,
  pageSize,
  schemaPreamble,
  SERVICE_CALLER,
  serviceGrant,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import { subjectWritable } from "../subject-write.ts";
import {
  qualifiedTable,
  subjectIdMatches,
  subjectReadable,
  subjectsOption,
} from "../subjects.ts";
import { OPERATIONS } from "./permissions-model.ts";

const PAYLOAD = [
  "organizationId",
  "subjectType",
  "subjectId",
  "id",
  "batchId",
] as const;

const EVENTS: BlockSqlEvents<TrashEvents> = {
  "subject.trashed": { subject: "trash-items", payload: PAYLOAD },
  "subject.restored": { subject: "trash-items", payload: PAYLOAD },
  "subject.purged": { subject: "trash-items", payload: PAYLOAD },
};

const NAMES: BlockSqlNames = {
  events: EVENTS,
  hooks: ["before_trash", "after_trash", "before_untrash", "after_untrash"],
  options: ["retentionDays", "extraColumns", "deletedAt"],
  tables: {
    items: {
      name: "trash_items",
      lifecycle: { tenant: "tenant", user: "trashedBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        title: "title",
        batch: "batch_id",
        depth: "depth",
        trashedBy: "trashed_by",
        trashedAt: "trashed_at",
        purgeAfter: "purge_after",
      },
    },
  },
};

const COLUMN = /^[a-z_][a-z0-9_]*$/;

interface Child {
  readonly type: string;
  readonly column: string;
}

interface Trashable {
  readonly type: string;
  readonly subject: Subject;
  readonly deletedAt: string;
  readonly title: string | undefined;
  /**
   * Columns no other live row in the tenant may share when this one is
   * restored.
   */
  readonly unique: readonly string[];
  /** Subjects whose `column` holds this subject's id, trashed with it. */
  readonly children: readonly Child[];
}

const isColumn = (value: unknown): value is string =>
  typeof value === "string" && COLUMN.test(value);

const isColumnList = (value: unknown): value is string[] =>
  Array.isArray(value) && value.every(isColumn);

interface ChildInput {
  readonly type?: unknown;
  readonly column?: unknown;
}

const isChildInput = (value: unknown): value is ChildInput =>
  typeof value === "object" && value !== null && !Array.isArray(value);

function childrenOf(value: unknown, where: string): readonly Child[] {
  if (value === undefined) {
    return [];
  }

  if (!Array.isArray(value)) {
    throw new TypeError(`${where} must be a list of { type, column }`);
  }

  return value.map((entry: unknown) => {
    if (
      !isChildInput(entry) ||
      typeof entry.type !== "string" ||
      !isColumn(entry.column)
    ) {
      throw new TypeError(`${where} must be a list of { type, column }`);
    }

    return { type: entry.type, column: entry.column };
  });
}

function trashable(ctx: BlockSqlContext): readonly Trashable[] {
  const where = `blocks.${ctx.instance}.on`;
  const explicit = ctx.on !== undefined;

  const list = subjectsOption(ctx, [
    "deletedAt",
    "title",
    "unique",
    "children",
  ]).flatMap(([type, subject]): Trashable[] => {
    const extra = subject.extra;
    const deletedAt = extra["deletedAt"];

    if (deletedAt === undefined && !explicit) {
      return [];
    }

    if (!isColumn(deletedAt)) {
      throw new TypeError(
        `${where}.${type}.deletedAt must name the timestamptz column that marks a trashed row`,
      );
    }

    const title = extra["title"];

    if (title !== undefined && !isColumn(title)) {
      throw new TypeError(`${where}.${type}.title must be a column name`);
    }

    const unique = extra["unique"] ?? [];

    if (!isColumnList(unique)) {
      throw new TypeError(
        `${where}.${type}.unique must be a list of column names`,
      );
    }

    return [
      {
        type,
        subject,
        deletedAt,
        title,
        unique,
        children: childrenOf(extra["children"], `${where}.${type}.children`),
      },
    ];
  });

  const types = new Set(list.map((entry) => entry.type));

  for (const entry of list) {
    for (const child of entry.children) {
      if (!types.has(child.type)) {
        throw new TypeError(
          `${where}.${entry.type}.children: "${child.type}" is not a subject type trash can hold`,
        );
      }
    }
  }

  return list;
}

/**
 * The subject types trash can hold, for a module that trashes through
 * `trash_cascade`.
 */
export function trashTypes(ctx: BlockSqlContext): ReadonlySet<string> {
  return new Set(trashable(ctx).map((entry) => entry.type));
}

const tenantColumn = (subject: Subject): string =>
  sqlIdent(
    typeof subject.tenant === "string" ? subject.tenant : "organization_id",
  );

function trashCase(list: readonly Trashable[], unsupported: string): string {
  if (list.length === 0) {
    return unsupported;
  }

  return `case trash_cascade.subject_type
${list
  .map(
    (entry) => `    when ${sqlString(entry.type)} then
      update ${qualifiedTable(entry.subject.table)} s set ${sqlIdent(entry.deletedAt)} = now()
        where ${subjectIdMatches(entry.subject, "trash_cascade.subject_id")}
          and s.${tenantColumn(entry.subject)} = trash_cascade.tenant
          and s.${sqlIdent(entry.deletedAt)} is null
        returning ${entry.title === undefined ? "null::text" : `s.${sqlIdent(entry.title)}::text`} into v_title;`,
  )
  .join("\n")}
    else
      ${unsupported}
  end case;
  if not found then
    return 0;
  end if;`;
}

function childrenCase(list: readonly Trashable[], cascade: string): string {
  const byType = new Map(list.map((entry) => [entry.type, entry]));

  const whens = list
    .filter((entry) => entry.children.length > 0)
    .map((entry) => {
      const loops = entry.children.flatMap((child) => {
        const target = byType.get(child.type);

        if (target === undefined) {
          return [];
        }

        return `      for v_child in
        select c.${sqlIdent(target.subject.id ?? "id")}::text from ${qualifiedTable(target.subject.table)} c
        where c.${sqlIdent(child.column)}::text = trash_cascade.subject_id
          and c.${tenantColumn(target.subject)} = trash_cascade.tenant
          and c.${sqlIdent(target.deletedAt)} is null
      loop
        v_count := v_count + ${cascade}(trash_cascade.tenant, ${sqlString(child.type)}, v_child, trash_cascade.batch, trash_cascade.depth + 1, trash_cascade.actor);
      end loop;`;
      });

      return `    when ${sqlString(entry.type)} then
${loops.join("\n")}`;
    });

  if (whens.length === 0) {
    return "";
  }

  return `case trash_cascade.subject_type
${whens.join("\n")}
    else null;
  end case;`;
}

function untrashCase(list: readonly Trashable[]): string {
  if (list.length === 0) {
    return "null;";
  }

  return `case v_item.subject_type
${list
  .map((entry) => {
    const table = qualifiedTable(entry.subject.table);
    const id = sqlIdent(entry.subject.id ?? "id");

    const conflict =
      entry.unique.length === 0
        ? ""
        : `
      if exists (
        select 1 from ${table} s
        join ${table} o on o.${tenantColumn(entry.subject)} = s.${tenantColumn(entry.subject)}
          and o.${id} <> s.${id}
          and o.${sqlIdent(entry.deletedAt)} is null
          and ${entry.unique.map((column) => `o.${sqlIdent(column)} = s.${sqlIdent(column)}`).join(" and ")}
        where ${subjectIdMatches(entry.subject, "v_item.subject_id")}
      ) then
        ${fail("TRASH_RESTORE_CONFLICT", `another ${entry.type} already uses this ${entry.unique.join(", ")}`, "23505")}
      end if;`;

    return `    when ${sqlString(entry.type)} then${conflict}
      update ${table} s set ${sqlIdent(entry.deletedAt)} = null
        where ${subjectIdMatches(entry.subject, "v_item.subject_id")};`;
  })
  .join("\n")}
    else null;
  end case;`;
}

function purgeCase(list: readonly Trashable[]): string {
  if (list.length === 0) {
    return "null;";
  }

  return `case v_item.subject_type
${list
  .map(
    (entry) => `    when ${sqlString(entry.type)} then
      delete from ${qualifiedTable(entry.subject.table)} s
        where ${subjectIdMatches(entry.subject, "v_item.subject_id")};`,
  )
  .join("\n")}
    else null;
  end case;`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const items = ctx.table("items");
  const c = (column: string): string => ctx.col("items", column);
  const read = ctx.permission("read", OPERATIONS["trash.read"]);
  const create = ctx.permission("create", OPERATIONS["trash.create"]);
  const restore = ctx.permission("restore", OPERATIONS["trash.restore"]);
  const manage = ctx.permission("manage", OPERATIONS["trash.manage"]);
  const list = trashable(ctx);
  const subjects = list.map((entry) => [entry.type, entry.subject] as const);
  const retention = ctx.number("retentionDays", 30);

  if (!Number.isInteger(retention) || retention < 0) {
    throw new TypeError(
      "blocks.trash.options.retentionDays must be a whole number of days, or 0 to keep trash until it is purged",
    );
  }

  const fn = (name: string): string => ctx.fn(name);
  const cascade = fn("trash_cascade");

  const record = (event: string, id: string, item: string): string =>
    ctx.record({
      type: event,
      payload: `jsonb_build_object('organizationId', ${item}.${c("tenant")}, 'subjectType', ${item}.${c("subjectType")}, 'subjectId', ${item}.${c("subjectId")}, 'id', ${id}, 'batchId', ${item}.${c("batch")})`,
      subject: `'trash-items/' || ${id}::text`,
      tenant: `${item}.${c("tenant")}`,
      audit: {
        category: "data",
        targetType: "trash_item",
        recordId: `${id}::text`,
        summary: `${sqlString(event.replace("subject.", ""))} || ' ' || ${item}.${c("subjectType")} || ' ' || ${item}.${c("subjectId")}`,
      },
    });

  const notFound = fail("TRASH_NOT_FOUND", "trash item not found", "P0002");
  // The root item's extra columns, such as a reason: trash() sets them, list_trash returns them.
  const extras = ctx.extraColumns("items", ["fields", "batchId", "count"]);
  const extra = extraFieldsArg(extras);

  const tables = ctx.manages
    ? `create table if not exists ${items} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType} not null,
  ${c("subjectType")} text not null,
  ${c("subjectId")} text not null,
  ${c("title")} text,
  ${c("batch")} uuid not null,
  ${c("depth")} integer not null default 0 check (${c("depth")} >= 0),
  ${c("trashedBy")} uuid,
  ${c("trashedAt")} timestamptz not null default now(),
  ${c("purgeAfter")} timestamptz,
  unique (${c("subjectType")}, ${c("subjectId")})
);${addExtraColumns(items, extras)}
create index if not exists ${sqlIdent(`${ctx.tableName("items").name}_tenant_idx`)} on ${items} (${c("tenant")}, ${c("trashedAt")} desc);
create index if not exists ${sqlIdent(`${ctx.tableName("items").name}_batch_idx`)} on ${items} (${c("batch")});
${lockTable(items, { read: true })}
drop policy if exists "trash_items_read" on ${items};
create policy "trash_items_read" on ${items} for select to authenticated
  using (${ctx.scope.check(c("tenant"), read)});
`
    : "";

  const children = childrenCase(list, cascade);

  return `${schemaPreamble(ctx)}
${tables}
-- Marks one subject row trashed, records it, then trashes the rows the
-- subject's children options point at, in the same batch.
create or replace function ${cascade}(tenant ${ctx.idType}, subject_type text, subject_id text, batch uuid, depth integer, actor uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_title text;
  v_count integer := 1;
  v_child text;
  v_item ${items}%rowtype;
begin
  ${trashCase(list, fail("TRASH_UNSUPPORTED", "this subject type has no deletedAt column", "22023"))}
  delete from ${items} i
    where i.${c("subjectType")} = trash_cascade.subject_type and i.${c("subjectId")} = trash_cascade.subject_id;
  insert into ${items} (${c("tenant")}, ${c("subjectType")}, ${c("subjectId")}, ${c("title")}, ${c("batch")}, ${c("depth")}, ${c("trashedBy")}, ${c("trashedAt")}, ${c("purgeAfter")})
  values (trash_cascade.tenant, trash_cascade.subject_type, trash_cascade.subject_id, v_title, trash_cascade.batch, trash_cascade.depth, trash_cascade.actor, now(), ${retention === 0 ? "null" : `now() + make_interval(days => ${String(retention)})`})
  returning * into v_item;
  ${record("subject.trashed", `v_item.${c("id")}`, "v_item")}
  ${children}
  return v_count;
end;
$$;
revoke execute on function ${cascade}(${ctx.idType}, text, text, uuid, integer, uuid) from public, anon, authenticated;

-- fields: the extra columns (blocks.trash.options.extraColumns) of the
-- subject's trash item.
${extra.drop(fn("trash"), `${ctx.idType}, text, text`)}
create or replace function ${fn("trash")}(tenant ${ctx.idType}, subject_type text, subject_id text${extra.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_batch uuid := gen_random_uuid();
  v_count integer;
  v_id uuid;
begin
  if not (${SERVICE_CALLER} or (${ctx.can("tenant", "trash.tenant", create)} and ${subjectReadable(ctx, subjects, { type: "trash.subject_type", id: "trash.subject_id", tenant: "trash.tenant" })} and ${subjectWritable(ctx, subjects, { type: "trash.subject_type", tenant: "trash.tenant" })})) then
    ${fail("TRASH_FORBIDDEN", "not allowed to trash this record")}
  end if;
  ${ctx.hook("before_trash", [
    [ctx.idType, "trash.tenant"],
    ["text", "trash.subject_type"],
    ["text", "trash.subject_id"],
  ])}
  v_count := ${cascade}(trash.tenant, trash.subject_type, trash.subject_id, v_batch, 0, auth.uid());
  if v_count = 0 then
    ${fail("TRASH_NOT_FOUND", "no live record to trash", "P0002")}
  end if;
  select i.${c("id")} into v_id from ${items} i
    where i.${c("subjectType")} = trash.subject_type and i.${c("subjectId")} = trash.subject_id;${writeExtraColumns(items, extras, "trash.fields", `x.${c("id")} = v_id`)}
  ${ctx.hook("after_trash", [
    ["uuid", "v_id"],
    ["uuid", "v_batch"],
  ])}
  return jsonb_build_object('id', v_id, 'batchId', v_batch, 'count', v_count);
end;
$$;
${userGrant(`${fn("trash")}(${ctx.idType}, text, text${extra.type})`)}

-- Restores every row of a batch, after checking the unique columns. The
-- caller deletes the batch's items, so the read-only guard sees its write.
create or replace function ${fn("trash_restore_batch")}(batch uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item ${items}%rowtype;
  v_count integer := 0;
begin
  for v_item in select * from ${items} where ${c("batch")} = trash_restore_batch.batch order by ${c("depth")} loop
    ${untrashCase(list)}
    ${record("subject.restored", `v_item.${c("id")}`, "v_item")}
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function ${fn("trash_restore_batch")}(uuid) from public, anon, authenticated;

create or replace function ${fn("restore_trash")}(item_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_root ${items}%rowtype;
  v_count integer;
begin
  select r.* into v_root from ${items} i
    join ${items} r on r.${c("batch")} = i.${c("batch")} and r.${c("depth")} = 0
    where i.${c("id")} = restore_trash.item_id;
  if not found then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or (${ctx.can("tenant", `v_root.${c("tenant")}`, restore)} and ${subjectWritable(ctx, subjects, { type: `v_root.${c("subjectType")}`, tenant: `v_root.${c("tenant")}` })})) then
    ${fail("TRASH_FORBIDDEN", "not allowed to restore this record")}
  end if;
  ${ctx.hook("before_untrash", [["uuid", `v_root.${c("id")}`]])}
  v_count := ${fn("trash_restore_batch")}(v_root.${c("batch")});
  delete from ${items} where ${c("batch")} = v_root.${c("batch")};
  ${ctx.hook("after_untrash", [
    ["uuid", `v_root.${c("id")}`],
    ["uuid", `v_root.${c("batch")}`],
  ])}
  return jsonb_build_object('id', v_root.${c("id")}, 'batchId', v_root.${c("batch")}, 'subjectType', v_root.${c("subjectType")}, 'subjectId', v_root.${c("subjectId")}, 'count', v_count);
end;
$$;
${userGrant(`${fn("restore_trash")}(uuid)`)}

create or replace function ${fn("list_trash")}(tenant ${ctx.idType}, subject_type text default null, page_size integer default 50, before timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", "list_trash.tenant", read)}) then
    ${fail("TRASH_FORBIDDEN", "not allowed to read this organization's trash")}
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', t.${c("id")}, 'subjectType', t.${c("subjectType")}, 'subjectId', t.${c("subjectId")}, 'title', t.${c("title")}, 'batchId', t.${c("batch")}, 'count', t.n, 'trashedBy', t.${c("trashedBy")}, 'trashedAt', t.${c("trashedAt")}, 'purgeAfter', t.${c("purgeAfter")}${extraFieldsJson("t", extras)}) order by t.${c("trashedAt")} desc, t.${c("id")}), '[]'::jsonb)
    into v_rows
  from (
    select x.*, (select count(*) from ${items} b where b.${c("batch")} = x.${c("batch")})::integer as n
    from ${items} x
    where x.${c("tenant")} = list_trash.tenant
      and x.${c("depth")} = 0
      and (list_trash.subject_type is null or x.${c("subjectType")} = list_trash.subject_type)
      and (list_trash.before is null or x.${c("trashedAt")} < list_trash.before)
      and (${SERVICE_CALLER} or ${subjectReadable(ctx, subjects, { type: `x.${c("subjectType")}`, id: `x.${c("subjectId")}`, tenant: `x.${c("tenant")}` })})
    order by x.${c("trashedAt")} desc, x.${c("id")}
    limit ${pageSize("list_trash.page_size", 50, 200)}
  ) t;
  return v_rows;
end;
$$;
${userGrant(`${fn("list_trash")}(${ctx.idType}, text, integer, timestamptz)`)}

-- Deletes a batch's rows for good, children first.
create or replace function ${fn("trash_purge_batch")}(batch uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item ${items}%rowtype;
  v_count integer := 0;
begin
  for v_item in select * from ${items} where ${c("batch")} = trash_purge_batch.batch order by ${c("depth")} desc loop
    ${purgeCase(list)}
    ${record("subject.purged", `v_item.${c("id")}`, "v_item")}
    v_count := v_count + 1;
  end loop;
  delete from ${items} where ${c("batch")} = trash_purge_batch.batch;
  return v_count;
end;
$$;
revoke execute on function ${fn("trash_purge_batch")}(uuid) from public, anon, authenticated;

create or replace function ${fn("purge_trash")}(item_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_batch uuid;
begin
  select ${c("tenant")}, ${c("batch")} into v_tenant, v_batch from ${items} where ${c("id")} = purge_trash.item_id;
  if v_batch is null then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", "v_tenant", manage)}) then
    ${fail("TRASH_FORBIDDEN", "not allowed to empty the trash")}
  end if;
  return ${fn("trash_purge_batch")}(v_batch);
end;
$$;
${userGrant(`${fn("purge_trash")}(uuid)`)}

-- Purges batches past their retention. Run it nightly, e.g. from pg_cron:
--   select cron.schedule('purge-trash', '15 3 * * *', 'select ${fn("purge_expired_trash")}()');
create or replace function ${fn("purge_expired_trash")}(max_batches integer default 100)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_batch uuid;
  v_count integer := 0;
begin
  for v_batch in
    select ${c("batch")} from ${items}
    where ${c("depth")} = 0 and ${c("purgeAfter")} <= now()
      and not ${ctx.held("trash", c("tenant"))}
    order by ${c("purgeAfter")}
    limit greatest(coalesce(purge_expired_trash.max_batches, 100), 1)
  loop
    v_count := v_count + ${fn("trash_purge_batch")}(v_batch);
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("purge_expired_trash")}(integer)`)}

-- For policies: \`using (not ${fn("is_trashed")}('doc', id::text))\` hides
-- trashed rows where the table's own deletedAt column isn't checked.
create or replace function ${fn("is_trashed")}(subject_type text, subject_id text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from ${items}
    where ${c("subjectType")} = is_trashed.subject_type and ${c("subjectId")} = is_trashed.subject_id
  )
$$;
${userGrant(`${fn("is_trashed")}(text, text)`)}
`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  const extra = extraFieldsArg(
    ctx.extraColumns("items", ["fields", "batchId", "count"]),
  ).contract;

  return [
    {
      name: "trash",
      args: ["{id}", "text", "text", ...extra],
      returns: "jsonb",
    },
    { name: "restore_trash", args: ["uuid"], returns: "jsonb" },
    { name: "purge_trash", args: ["uuid"], returns: "integer" },
    { name: "is_trashed", args: ["text", "text"], returns: "boolean" },
  ];
}

const CONTRIBUTES: BlockContributes = {
  "bulk-actions": (own) => [
    {
      name: "trash.trash",
      run: `perform ${own.fn("trash")}(bulk_row.tenant, bulk_row.subject_type, bulk_row.subject_id);`,
    },
  ],
};

export const TRASH: BlockSqlDefinition = {
  contributes: CONTRIBUTES,
  name: "trash",
  scopes: ["tenant"],
  title: "Trash",
  description:
    "Soft delete through each subject's deletedAt column: trash with children in one batch, restore with unique checks, a list per organization, and purge after a retention period.",
  requires: ["memberships", "permissions"],
  integrates: ["outbox", "audit", "data-lifecycle"],
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  version: 2,
  upgrades: [
    {
      from: 1,
      description:
        "purge_expired_trash skips batches under a data-lifecycle legal hold.",
      sql: () => "",
    },
  ],
  names: NAMES,
  contract,
  build,
};
