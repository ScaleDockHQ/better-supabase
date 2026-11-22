import { bodyOf, list, obj, str, strings } from "./ast.ts";

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
  if (Array.isArray(node)) {
    return node.some((item) => blocksWrites(item));
  }

  if (typeof node !== "object" || node === null) {
    return false;
  }

  return Object.entries(node).some(([key, value]) => {
    switch (key) {
      case "distinctClause":
      case "groupClause":
      case "windowClause": {
        return list(value).length > 0;
      }

      case "havingClause":
      case "limitCount":
      case "limitOffset":
      case "JoinExpr": {
        return true;
      }

      case "op": {
        return value !== "SETOP_NONE";
      }

      case "FuncCall": {
        const call = obj(value);
        const name = strings(call["funcname"]).at(-1)?.toLowerCase() ?? "";

        return (
          call["over"] !== undefined ||
          AGGREGATES.has(name) ||
          blocksWrites(call["args"])
        );
      }

      default: {
        return blocksWrites(value);
      }
    }
  });
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
