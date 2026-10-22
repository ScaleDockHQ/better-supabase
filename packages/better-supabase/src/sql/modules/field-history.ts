import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";
import type { RegisteredSubject } from "../subject-registry.ts";

import { isRecord } from "../../core/guards.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  lockTable,
  pageSize,
  schemaPreamble,
  SERVICE_CALLER,
  userGrant,
} from "../shared.ts";
import { registeredSubjects } from "../subject-registry.ts";
import { moduleOperations } from "./access-model.ts";

const NAMES: BlockSqlNames = {
  options: ["subjects"],
  tables: {
    changes: {
      name: "field_changes",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        field: "field",
        before: "old_value",
        after: "new_value",
        changedBy: "changed_by",
        changedAt: "changed_at",
      },
    },
  },
};

const COLUMN = /^[a-z_][a-z0-9_]{0,62}$/u;

/** A record type and the columns whose changes are kept. */
interface HistoryBinding {
  readonly subject: RegisteredSubject;
  readonly fields: readonly string[];
}

/** `blocks.field-history.options.subjects`, checked against `config.records`. */
function historyBindings(ctx: BlockSqlContext): readonly HistoryBinding[] {
  const raw = ctx.option("subjects") ?? {};

  if (!isRecord(raw)) {
    throw new TypeError(
      "blocks.field-history.options.subjects must be an object",
    );
  }

  const registry = registeredSubjects(ctx.subjects, ctx.naming);

  return Object.entries(raw).map(([type, fields]) => {
    const where = `blocks.field-history.options.subjects.${type}`;
    const subject = registry.find((item) => item.type === type);

    if (subject?.tenant === undefined) {
      throw new TypeError(
        `${where}: register "${type}" with a tenant column in config.records first`,
      );
    }

    if (
      !Array.isArray(fields) ||
      fields.length === 0 ||
      fields.some((field) => typeof field !== "string" || !COLUMN.test(field))
    ) {
      throw new TypeError(`${where} must be a non-empty list of column names`);
    }

    return { subject, fields: [...new Set(fields.map(String))] };
  });
}

function bindingTrigger(
  ctx: BlockSqlContext,
  binding: HistoryBinding,
  c: (column: string) => string,
): string {
  const type = binding.subject.type;
  const name = `bsb_field_history_${type}`;
  const watched = binding.fields.map(sqlIdent).join(", ");

  const values = binding.fields
    .map(
      (field) =>
        `(${sqlString(field)}, to_jsonb(old.${sqlIdent(field)}), to_jsonb(new.${sqlIdent(field)}))`,
    )
    .join(",\n      ");

  return `
-- Keeps the old and new value of each watched column of a ${type} on update.
create or replace function better_supabase.${name}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into ${ctx.table("changes")} (${c("tenant")}, ${c("subjectType")}, ${c("subjectId")}, ${c("field")}, ${c("before")}, ${c("after")}, ${c("changedBy")})
  select new.${binding.subject.tenant}, ${sqlString(type)}, new.${binding.subject.id}::text, x.field, x.old_value, x.new_value, auth.uid()
  from (values
      ${values}
  ) as x (field, old_value, new_value)
  where x.old_value is distinct from x.new_value;
  return null;
end;
$$;
revoke execute on function better_supabase.${name}() from public, anon, authenticated;
drop trigger if exists ${name} on ${binding.subject.qualified};
create trigger ${name} after update of ${watched} on ${binding.subject.qualified}
for each row execute function better_supabase.${name}();`;
}

function build(ctx: BlockSqlContext): string {
  const bindings = historyBindings(ctx);
  const read = ctx.permission("read", moduleOperations("field-history").read);
  const fn = (name: string): string => ctx.fn(name);
  const t = ctx.table("changes");
  const c = (column: string): string => ctx.col("changes", column);
  const canSubject = ctx.of("subjects").fn("can_subject");
  const policy = `${ctx.tableName("changes").name}_read`;

  const readable = (tenant: string, type: string, id: string): string =>
    `(${SERVICE_CALLER} or (${ctx.scope.can(tenant, read)} and coalesce(${canSubject}(${type}, ${id}, 'read'), false)))`;

  return `${schemaPreamble(ctx)}
-- Field history: the old and new value of the watched columns of a record on
-- every update, who made it and when.
create table if not exists ${t} (
  ${c("id")} bigint generated always as identity primary key,
  ${c("tenant")} ${ctx.idType} not null,
  ${c("subjectType")} text not null,
  ${c("subjectId")} text not null,
  ${c("field")} text not null,
  ${c("before")} jsonb,
  ${c("after")} jsonb,
  ${c("changedBy")} uuid references auth.users (id) on delete set null,
  ${c("changedAt")} timestamptz not null default now()
);
create index if not exists ${ctx.naming.rename("field_changes_subject_idx")} on ${t} (${c("subjectType")}, ${c("subjectId")}, ${c("id")} desc);
create index if not exists ${ctx.naming.rename("field_changes_tenant_idx")} on ${t} (${c("tenant")}, ${c("changedAt")});
create index if not exists ${ctx.naming.rename("field_changes_changed_by_idx")} on ${t} (${c("changedBy")}) where ${c("changedBy")} is not null;
${lockTable(t, { read: true })}
drop policy if exists ${policy} on ${t};
create policy ${policy} on ${t} for select to authenticated
using (${ctx.scope.check(c("tenant"), read)} and coalesce(${canSubject}(${c("subjectType")}, ${c("subjectId")}, 'read'), false));
${bindings.map((binding) => bindingTrigger(ctx, binding, c)).join("\n")}

-- A record's changes, newest first, optionally of one field. before is the id
-- of the last change of the previous page. Needs history.read and read access
-- to the record.
create or replace function ${fn("field_history")}(subject_type text, subject_id text, field text default null, before bigint default null, max_count integer default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', z.${c("id")}::text,
    'organizationId', z.${c("tenant")},
    'subjectType', z.${c("subjectType")},
    'subjectId', z.${c("subjectId")},
    'field', z.${c("field")},
    'before', z.${c("before")},
    'after', z.${c("after")},
    'changedBy', z.${c("changedBy")},
    'changedAt', z.${c("changedAt")}
  ) order by z.${c("id")} desc), '[]'::jsonb)
  from (
    select x.* from ${t} x
    where x.${c("subjectType")} = field_history.subject_type
      and x.${c("subjectId")} = field_history.subject_id
      and (field_history.field is null or x.${c("field")} = field_history.field)
      and (field_history.before is null or x.${c("id")} < field_history.before)
      and ${readable(`x.${c("tenant")}`, "field_history.subject_type", "field_history.subject_id")}
    order by x.${c("id")} desc
    limit ${pageSize("field_history.max_count", 50, 500)}
  ) z
$$;
${userGrant(`${fn("field_history")}(text, text, text, bigint, integer)`)}
`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "field_history",
      args: ["text", "text", "text", "bigint", "integer"],
      returns: "jsonb",
    },
  ];
}

export const FIELD_HISTORY: BlockSqlDefinition = {
  name: "field-history",
  scopes: ["tenant"],
  title: "Field history",
  description:
    "The old and new value of chosen columns of any registered record on every update, who changed it and when, read per record and field.",
  requires: ["tenant", "access", "subjects"],
  integrates: ["data-lifecycle"],
  target: "schema",
  modes: ["managed"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
