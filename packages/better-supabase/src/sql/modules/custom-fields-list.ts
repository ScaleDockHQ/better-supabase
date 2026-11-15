import type { BlockSqlContext } from "../context.ts";

import { userGrant } from "../shared.ts";
import { packsOn } from "./custom-fields-packs.ts";

export function listDefinitions(
  ctx: BlockSqlContext,
  definitions: string,
  rank: string,
  read: string,
): string {
  const archivable = ctx.has("definitions", "archivedAt");

  const order =
    rank === ""
      ? `d.${ctx.col("definitions", "key")}`
      : `d.${rank} collate "C", d.${ctx.col("definitions", "key")}`;

  return `
-- The definitions of one entity in display order. Archived fields stay out
-- unless include_archived is true.${archivable ? `\ndrop function if exists ${ctx.fn("list_field_definitions")}(${ctx.idType}, text);` : ""}
create or replace function ${ctx.fn("list_field_definitions")}(tenant ${ctx.idType}, entity text${archivable ? ", include_archived boolean default false" : ""})
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', d.${ctx.col("definitions", "id")},
    'entity', d.${ctx.col("definitions", "entity")},
    'key', d.${ctx.col("definitions", "key")},
    'label', d.${ctx.col("definitions", "label")},
    'type', d.${ctx.col("definitions", "type")},
    'required', d.${ctx.col("definitions", "required")},
    'sensitive', d.${ctx.col("definitions", "sensitive")},${
      ctx.has("definitions", "encrypted")
        ? `
    'encrypted', d.${ctx.col("definitions", "encrypted")},`
        : ""
    }
    ${
      packsOn(ctx)
        ? `'pack', d.${ctx.col("definitions", "pack")},
    'packVersion', d.${ctx.col("definitions", "packVersion")},
    `
        : ""
    }${archivable ? `'archivedAt', d.${ctx.col("definitions", "archivedAt")},\n    ` : ""}'rank', ${rank === "" ? "null" : `d.${rank}`}
  ) order by ${order}), '[]'::jsonb)
  from ${definitions} d
  where d.${ctx.col("definitions", "tenant")} = list_field_definitions.tenant
    and d.${ctx.col("definitions", "entity")} = list_field_definitions.entity${archivable ? `\n    and (coalesce(list_field_definitions.include_archived, false) or d.${ctx.col("definitions", "archivedAt")} is null)` : ""}
    and (auth.role() = 'service_role' or ${ctx.scope.can("list_field_definitions.tenant", read)})
$$;
${userGrant(`${ctx.fn("list_field_definitions")}(${ctx.idType}, text${archivable ? ", boolean" : ""})`)}
`;
}
