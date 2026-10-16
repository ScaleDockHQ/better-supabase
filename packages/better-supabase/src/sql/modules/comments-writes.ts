import type { ExtraColumn, ModuleContext } from "../context.ts";

import {
  extraFieldsArg,
  withExtraFields,
  writeExtraColumns,
} from "../shared.ts";

/** A function body that runs `statement` and returns the row it wrote. */
function writeBody(
  table: string,
  statement: string,
  then: {
    readonly copy: string;
    readonly json: string;
    readonly guard: string;
  },
  extras: readonly ExtraColumn[],
): string {
  if (extras.length === 0) {
    return `language sql
security invoker
set search_path = ''
as $$
  ${statement}
  returning to_jsonb(x.*)
$$;`;
  }
  return `language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row ${table}%rowtype;
begin
  ${statement}
  returning x.* into v_row;${then.guard}${then.copy}
  return ${then.json};
end;
$$;`;
}

/**
 * `create_comment` and `edit_comment`. With extra columns they take
 * `fields jsonb`, run as PL/pgSQL to copy the columns after the write, and
 * return them under `fields`; without, they stay `language sql`.
 */
export function commentWrites(
  ctx: ModuleContext,
  extras: readonly ExtraColumn[],
): string {
  const id = ctx.idType;
  const comments = ctx.table("comments");
  const c = (logical: string): string => ctx.col("comments", logical);
  const fn = (name: string): string => ctx.fn(name);
  const extra = extraFieldsArg(extras);
  const after = (name: string, guard = "") => ({
    copy: writeExtraColumns(
      comments,
      extras,
      `${name}.fields`,
      `x.${c("id")} = v_row.${c("id")}`,
      "v_row",
    ),
    json: withExtraFields("to_jsonb(v_row)", "v_row", extras),
    guard,
  });
  const insert = `insert into ${comments} as x (${[c("tenant"), c("subjectType"), c("subjectId"), c("body"), c("document"), c("mentions"), c("parent")].join(", ")})
  values (${ctx.scope.value("create_comment.tenant")}, create_comment.subject_type, create_comment.subject_id, create_comment.body, create_comment.document, coalesce(create_comment.mentions, '{}'), create_comment.parent)`;
  const update = `update ${comments} x
  set ${c("body")} = edit_comment.body,
      ${c("document")} = case
        when coalesce(edit_comment.clear_document, false) then null
        else coalesce(edit_comment.document, x.${c("document")})
      end,
      ${c("mentions")} = coalesce(edit_comment.mentions, x.${c("mentions")})
  where x.${c("id")} = edit_comment.id`;
  return `-- The functions run as the caller, so the policies above decide.
drop function if exists ${fn("create_comment")}(${id}, text, text, text, uuid[], uuid);
drop function if exists ${fn("edit_comment")}(uuid, text, uuid[]);
${extra.drop(fn("create_comment"), `${id}, text, text, text, uuid[], uuid, jsonb`)}
${extra.drop(fn("edit_comment"), "uuid, text, uuid[], jsonb, boolean")}
create or replace function ${fn("create_comment")}(
  tenant ${id},
  subject_type text,
  subject_id text,
  body text,
  mentions uuid[] default '{}',
  parent uuid default null,
  document jsonb default null${extra.param}
)
returns jsonb
${writeBody(comments, insert, after("create_comment"), extras)}

-- An edit keeps the document unless one is passed or clear_document is true.
create or replace function ${fn("edit_comment")}(id uuid, body text, mentions uuid[] default null, document jsonb default null, clear_document boolean default false${extra.param})
returns jsonb
${writeBody(
  comments,
  update,
  after(
    "edit_comment",
    `
  if not found then
    return null;
  end if;`,
  ),
  extras,
)}`;
}
