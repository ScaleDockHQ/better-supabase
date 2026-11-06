import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { fail, userGrant } from "../shared.ts";
import { quoteTemplatesOn } from "./quotes-kit.ts";

/** `clone_quote`: a new quote from a quote or a template, with its lines. */
export function cloneQuoteSql(
  ctx: BlockSqlContext,
  n: {
    readonly fn: (name: string) => string;
    readonly t: (table: string) => string;
    readonly c: (table: string, column: string) => string;
    readonly service: string;
    readonly write: string;
  },
): string {
  const fn = n.fn;
  const t = n.t;
  const q = (column: string): string => n.c("quotes", column);
  const lines = ctx.table("lines");
  const parent = ctx.col("lines", "parent");
  const parentKey = sqlString(ctx.colName("lines", "parent"));
  const on = quoteTemplatesOn(ctx);

  const templateExpr = on
    ? "case when coalesce(clone_quote.overrides, '{}'::jsonb) ? 'templateId' then clone_quote.overrides ->> 'templateId' else null end"
    : "null";

  const sourceExpr = on
    ? `case when v_src.${q("template")} is not null then v_src.${q(
        "template",
      )}::text else ${
        ctx.has("quotes", "sourceTemplate")
          ? `v_src.${q("sourceTemplate")}::text`
          : "null"
      } end`
    : "null";

  return [
    `create or replace function ${fn(
      "clone_quote",
    )}(source uuid, overrides jsonb default null)`,
    "returns jsonb",
    "language plpgsql",
    "security definer",
    "set search_path = ''",
    "as $$",
    "declare",
    `  v_src ${t("quotes")};`,
    "  v_created jsonb;",
    "  v_id uuid;",
    "begin",
    `  select * into v_src from ${t("quotes")} x where x.${q(
      "id",
    )} = clone_quote.source;`,
    "  if not found then",
    `    ${fail("QUOTE_NOT_FOUND", "no such quote", "P0002")}`,
    "  end if;",
    `  if not (${n.service} or ${ctx.scope.can(`v_src.${q("tenant")}`, n.write)}) then`,
    `    ${fail("QUOTE_FORBIDDEN", "not allowed to change quotes")}`,
    "  end if;",
    `  ${ctx.hook("before_quote_clone", [
      ["uuid", "clone_quote.source"],
      ["jsonb", "clone_quote.overrides"],
    ])}`,
    `  v_created := ${fn("create_quote")}(v_src.${q(
      "tenant",
    )}, jsonb_strip_nulls(jsonb_build_object('title', v_src.${q(
      "title",
    )}, 'currency', v_src.${q("currency")}, 'templateId', ${
      templateExpr
    }, 'sourceTemplateId', ${
      sourceExpr
    })) || (coalesce(clone_quote.overrides, '{}'::jsonb) - 'templateId') || jsonb_strip_nulls(jsonb_build_object('templateId', ${
      templateExpr
    }, 'sourceTemplateId', ${sourceExpr})), null);`,
    "  v_id := (v_created ->> 'id')::uuid;",
    `  insert into ${lines}`,
    `  select (jsonb_populate_record(null::${
      lines
    }, to_jsonb(l) || jsonb_build_object('id', gen_random_uuid(), ${
      parentKey
    }, v_id))).*`,
    `  from ${lines} l where l.${parent} = clone_quote.source;`,
    `  ${ctx.hook("after_quote_clone", [["uuid", "v_id"]])}`,
    "  return v_created;",
    "end;",
    "$$;",
    userGrant(`${fn("clone_quote")}(uuid, jsonb)`),
  ].join("\n");
}
