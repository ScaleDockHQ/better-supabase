import type { Snapshot } from './types.ts';

import { readExtras } from './extras.ts';
import {
  type Queryable,
  readGeneratorMetadata,
  stabilizeMetadata,
} from './typegen.ts';

/** Reads a v2 snapshot: typegen metadata plus the extras. */
export async function introspect(
  db: Queryable,
  schemas: readonly string[],
): Promise<Snapshot> {
  const unique = [...new Set(schemas)].sort();
  const { metadata: generator, ids } = stabilizeMetadata(
    await readGeneratorMetadata(db, unique),
  );
  const extras = await readExtras(db, unique);
  return {
    version: 2,
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

export { toCatalog } from './catalog.ts';
export { managementSource, pgSource } from './source.ts';
export type { IntrospectionSource, ManagementSourceOptions } from './source.ts';
export type { Queryable } from './typegen.ts';
