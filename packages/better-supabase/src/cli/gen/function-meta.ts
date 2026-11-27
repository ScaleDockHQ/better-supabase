import type { ResolvedConfig } from "../../config/index.ts";
import type { SchemaMeta } from "../../index.ts";
import type { TableModel } from "./model-types.ts";

import { resolveShares } from "../../config/shares.ts";
import { resolveBlock } from "../../sql/index.ts";
import { bootstrapTables } from "./bootstrap-tables.ts";

/**
 * The provider's `sharedFunctions` and the app's `shares.functions`, keyed by
 * the function's database name, with each table resolved to its app key. A
 * table gen doesn't know keeps its name, so the share check refuses it at run
 * time.
 */
/** The provider's tables and `shares.tables`, keyed by the config's name. */
export function declaredTableShares(
  config: ResolvedConfig,
): ReturnType<typeof resolveShares>["tables"] {
  return resolveShares(config).tables;
}

export function functionSharesMeta(
  config: ResolvedConfig,
  tables: readonly TableModel[],
): Pick<SchemaMeta, "functionShares"> {
  const declared = Object.entries(resolveShares(config).functions);

  if (declared.length === 0) {
    return {};
  }

  const keyOf = (name: string): string =>
    tables.find(
      ({ snapshot }) =>
        `${snapshot.schema}.${snapshot.name}` === name ||
        snapshot.name === name,
    )?.key ?? name;

  return {
    functionShares: Object.fromEntries(
      declared.map(([qualifiedName, entry]) => {
        const dot = qualifiedName.indexOf(".");
        const schema = dot === -1 ? "public" : qualifiedName.slice(0, dot);
        const name = dot === -1 ? qualifiedName : qualifiedName.slice(dot + 1);

        return [
          name,
          {
            schema,
            tables: [...new Set(entry.share.tables.map(keyOf))].toSorted(),
            permissions: [...entry.share.permissions].toSorted(),
          },
        ];
      }),
    ),
  };
}

/**
 * The schema the sessions block's `bootstrap_<name>` wrappers are callable in:
 * the API schema, unless its `functions` list leaves them out, else the module
 * schema. Omitted when that is `better_supabase`, the runtime default, unless
 * entries read tables: those are recorded with the schema.
 */
export function bootstrapMeta(
  config: ResolvedConfig,
  sources: Readonly<Record<string, string>> | undefined,
  tableModels: readonly TableModel[],
): Pick<SchemaMeta, "bootstrap"> {
  const sessions = config.blocks["sessions"];

  if (sessions?.options?.["bootstrap"] === undefined) {
    return {};
  }

  const block = resolveBlock(sessions);
  const api = block.api;

  const wrapped =
    api !== undefined &&
    (api.functions === undefined ||
      api.functions.some((name) => name.startsWith("bootstrap_")));

  const schema = wrapped ? api.schema : block.schema;

  const tables = bootstrapTables(
    config,
    sources,
    tableModels.map((table) => ({
      key: table.key,
      schema: table.snapshot.schema,
      name: table.snapshot.name,
    })),
  );

  const recorded = Object.keys(tables).length > 0 ? { tables } : {};

  return schema === "better_supabase" && !("tables" in recorded)
    ? {}
    : { bootstrap: { schema, ...recorded } };
}
