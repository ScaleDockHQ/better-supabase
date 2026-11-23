import type { ResolvedConfig } from "../config/index.ts";
import type { CommandResult } from "./core/io.ts";

import { readFileFacts, SchemaReadFailure } from "./schema-reader/index.ts";

/** One SQL expression the config carries, with where it was written. */
export interface ConfigSqlFragment {
  /** The config key path, such as `authorization.functions.can`. */
  readonly path: string;
  readonly sql: string;
  /**
   * How the text is read: a scalar `expression` (the default), an `order by`
   * list, or one or more `statements`.
   */
  readonly kind?: "expression" | "order" | "statements";
}

/** `{row}`, `{user}` and the other placeholders stand for a column or value. */
const PLACEHOLDER = /\{([A-Za-z_]+)\}/g;

/**
 * Every config key that holds SQL: the authorization provider's function
 * templates, role sources and platform roles (`through.where`), persona and
 * fixture role `setup` statements, the `vectorSearch` `boost`, `predicate` and
 * `order`, the `{ sql }` payload columns of each block's events, and the `{ sql
 * }` payload values of `realtime.triggers`.
 *
 * @param config - The resolved config.
 * @returns The fragments, in config order.
 */
export function configSqlFragments(
  config: ResolvedConfig,
): readonly ConfigSqlFragment[] {
  const fragments: ConfigSqlFragment[] = [];

  const add = (
    path: string,
    sql: unknown,
    kind?: ConfigSqlFragment["kind"],
  ): void => {
    if (typeof sql === "string" && sql.trim() !== "") {
      fragments.push({ path, sql, ...(kind === undefined ? {} : { kind }) });
    }
  };

  const authorization = config.authorization;

  for (const [key, sql] of Object.entries(authorization?.functions ?? {})) {
    add(`authorization.functions.${key}`, sql);
  }

  for (const [index, source] of (authorization?.roleSources ?? []).entries()) {
    add(
      `authorization.roleSources[${String(index)}].role.through.where`,
      source.role.through.where,
    );
  }

  add(
    "authorization.platformRoles.through.where",
    authorization?.platformRoles?.through?.where,
  );

  const personas = authorization?.personas;

  if (personas !== undefined && personas !== "roles") {
    for (const [index, persona] of personas.entries()) {
      add(
        `authorization.personas[${String(index)}].setup`,
        persona.setup,
        "statements",
      );
    }
  }

  for (const [index, role] of (authorization?.fixtureRoles ?? []).entries()) {
    add(
      `authorization.fixtureRoles[${String(index)}].setup`,
      role.setup,
      "statements",
    );
  }

  for (const entry of config.vectorSearch) {
    const at = `vectorSearch.${entry.table}`;

    add(`${at}.boost`, entry.boost);
    add(`${at}.predicate`, entry.predicate);
    add(`${at}.order`, entry.order, "order");
  }

  for (const [index, trigger] of config.realtime.triggers.entries()) {
    const payload = trigger.payload;

    if (typeof payload === "object") {
      for (const [key, value] of Object.entries(payload)) {
        if (typeof value !== "string" && "sql" in value) {
          add(
            `realtime.triggers[${String(index)}].payload.${key}.sql`,
            value.sql,
          );
        }
      }
    }
  }

  for (const [block, options] of Object.entries(config.blocks)) {
    const events = options?.events;
    const payload = typeof events === "object" ? events.payload : undefined;

    for (const [event, columns] of Object.entries(payload ?? {})) {
      for (const [key, column] of Object.entries(columns)) {
        if (typeof column !== "string") {
          add(`blocks.${block}.events.payload.${event}.${key}.sql`, column.sql);
        }
      }
    }
  }

  return fragments;
}

/** The text `fragment` is parsed as, with each placeholder an identifier. */
function probe(fragment: ConfigSqlFragment): string {
  const sql = fragment.sql.replaceAll(PLACEHOLDER, "$1_placeholder");

  const kind = fragment.kind ?? "expression";

  switch (kind) {
    case "expression": {
      return `select (${sql});`;
    }

    case "order": {
      return `select 1 from placeholder_table order by ${sql};`;
    }

    case "statements": {
      return sql.trimEnd().endsWith(";") ? sql : `${sql};`;
    }

    default: {
      const unknown: never = kind;

      return unknown;
    }
  }
}

/**
 * Parses each fragment (as `select (<fragment>)` for an expression) with its
 * placeholders replaced by identifiers, so a typo stops `gen` at the config key
 * instead of in a migration.
 *
 * @param config - The resolved config.
 * @returns A failing result that names the first bad config key, or
 *   `undefined`.
 */
export async function checkConfigSql(
  config: ResolvedConfig,
): Promise<CommandResult | undefined> {
  for (const fragment of configSqlFragments(config)) {
    const text = probe(fragment);

    try {
      await readFileFacts(text, { path: fragment.path });
    } catch (error) {
      if (error instanceof SchemaReadFailure) {
        return {
          code: 1,
          error: `${fragment.path} is not valid SQL: ${error.details.message}\n  ${fragment.sql}`,
        };
      }

      throw error;
    }
  }

  return undefined;
}
