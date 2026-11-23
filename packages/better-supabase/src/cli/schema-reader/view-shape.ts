import { bodyOf, list, str, strings } from "./ast.ts";
import { walk } from "./walk.ts";

const AGGREGATES = new Set([
  "count",
  "sum",
  "avg",
  "min",
  "max",
  "array_agg",
  "string_agg",
  "jsonb_agg",
  "json_agg",
  "bool_and",
  "bool_or",
]);

/** Whether anything in `query` keeps Postgres from writing through the view. */
export function blocksWrites(node: unknown): boolean {
  let blocked = false;

  const block = (reason: boolean): boolean => {
    blocked ||= reason;

    return !blocked;
  };

  walk(node, {
    SelectStmt: (select) =>
      block(
        list(select.distinctClause).length > 0 ||
          list(select.groupClause).length > 0 ||
          list(select.windowClause).length > 0 ||
          select.havingClause !== undefined ||
          select.limitCount !== undefined ||
          select.limitOffset !== undefined ||
          (select.op !== undefined && select.op !== "SETOP_NONE"),
      ),
    JoinExpr: () => block(true),
    FuncCall: (call) =>
      block(
        call.over !== undefined ||
          AGGREGATES.has(strings(call.funcname).at(-1)?.toLowerCase() ?? ""),
      ),
  });

  return blocked;
}

/** The names of the select list, or `undefined` when one is `*` or unnamed. */
export function selectNames(query: unknown): readonly string[] | undefined {
  let select = bodyOf(query, "SelectStmt");

  while (select !== undefined && select["op"] !== "SETOP_NONE") {
    select = bodyOf(select["larg"], "SelectStmt");
  }

  if (select === undefined || select["withClause"] !== undefined) {
    return undefined;
  }

  const names: string[] = [];

  for (const item of list(select["targetList"])) {
    const target = bodyOf(item, "ResTarget");
    const alias = str(target?.["name"]);

    if (alias !== undefined && alias !== "") {
      names.push(alias);
      continue;
    }

    const field = list(bodyOf(target?.["val"], "ColumnRef")?.["fields"]).at(-1);
    const column = str(bodyOf(field, "String")?.["sval"]);

    if (column === undefined) {
      return undefined;
    }

    names.push(column);
  }

  return names;
}
