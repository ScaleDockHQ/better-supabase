import type { EventPayloadColumns } from "../config/blocks.ts";
import type { ResolvedConfig } from "../config/index.ts";
import type { CommandResult } from "./core/io.ts";

import { readFileFacts, SchemaReadFailure } from "./schema-reader/index.ts";

/** One SQL expression the config carries, with where it was written. */
export interface ConfigSqlFragment {
  /** The config key path, such as `authorization.functions.can`. */
  readonly path: string;
  readonly sql: string;
}

/** `{row}`, `{user}` and the other placeholders stand for a column or value. */
const PLACEHOLDER = /\{([A-Za-z_]+)\}/g;

/**
 * The SQL expressions of `config`: the authorization provider's function
 * templates and the `{ sql }` payload columns of each block's events.
 *
 * @param config - The resolved config.
 * @returns The fragments, in config order.
 */
export function configSqlFragments(
  config: ResolvedConfig,
): readonly ConfigSqlFragment[] {
  const fragments: ConfigSqlFragment[] = [];

  for (const [key, sql] of Object.entries(
    config.authorization?.functions ?? {},
  )) {
    if (typeof sql === "string") {
      fragments.push({ path: `authorization.functions.${key}`, sql });
    }
  }

  for (const [block, options] of Object.entries(config.blocks)) {
    if (options === undefined || !("eventPayload" in options)) {
      continue;
    }

    // SAFETY: a resolved block's `eventPayload` is `EventPayloadColumns`.
    const payload = options.eventPayload as EventPayloadColumns;

    for (const [event, columns] of Object.entries(payload)) {
      for (const [key, column] of Object.entries(columns)) {
        if (typeof column !== "string") {
          fragments.push({
            path: `blocks.${block}.events.payload.${event}.${key}.sql`,
            sql: column.sql,
          });
        }
      }
    }
  }

  return fragments;
}

/**
 * Parses each fragment as `select (<fragment>)` with its placeholders replaced
 * by identifiers, so a typo stops `gen` at the config key instead of in a
 * migration.
 *
 * @param config - The resolved config.
 * @returns A failing result that names the first bad config key, or
 *   `undefined`.
 */
export async function checkConfigSql(
  config: ResolvedConfig,
): Promise<CommandResult | undefined> {
  for (const fragment of configSqlFragments(config)) {
    const text = `select (${fragment.sql.replaceAll(PLACEHOLDER, "$1_placeholder")});`;

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
