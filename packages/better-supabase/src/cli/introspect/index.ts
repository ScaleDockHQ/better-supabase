import type { HookTarget } from "./extras.ts";
import type { Queryable } from "./typegen.ts";
import type { Snapshot } from "./types.ts";

import { readExtras } from "./extras.ts";
import { readGeneratorMetadata, stabilizeMetadata } from "./typegen.ts";

export interface IntrospectOptions {
  /** Auth hook functions to read too, in any schema (`[auth.hook.*]`). */
  readonly hooks?: readonly HookTarget[];
  /** Functions (`schema.name`) whose bodies to read, for bootstrap tables. */
  readonly functions?: readonly string[];
  /**
   * Also read the bodies of the functions doctor BS430 could admit into a
   * shared fill, for a config with an authorization provider.
   */
  readonly shareable?: boolean;
}

/** Reads a v2 snapshot: typegen metadata plus the extras. */
export async function introspect(
  db: Queryable,
  schemas: readonly string[],
  options: IntrospectOptions = {},
): Promise<Snapshot> {
  const unique = [...new Set(schemas)].toSorted();

  const [metadata, extras] = await Promise.all([
    readGeneratorMetadata(db, unique),
    readExtras(db, unique, options.hooks, options.functions, options.shareable),
  ]);

  const { metadata: generator, ids } = stabilizeMetadata(metadata);

  return {
    version: 3,
    schemas: unique,
    generator,
    extras: {
      ...extras,
      tables: extras.tables.map((table) => ({
        ...table,
        id: ids.get(table.id) ?? table.id,
      })),
    },
  };
}

export { toCatalog } from "./catalog.ts";

export { managementSource, pgSource } from "./source.ts";

export type { IntrospectionSource, ManagementSourceOptions } from "./source.ts";

export type { Queryable } from "./typegen.ts";
