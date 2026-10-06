import type { ExtrasTable, Snapshot } from "./types.ts";

import { byCodePoint } from "../compare.ts";
import { type GeneratorMetadata, stabilizeMetadata } from "./typegen.ts";

/** What the extras query set reads that a `GeneratorMetadata` document leaves out. */
const METADATA_GAPS: readonly string[] = [
  "multi-column unique keys and checks",
  "foreign key actions",
  "indexes",
  "triggers",
  "policies",
  "grants",
  "storage buckets",
  "the realtime publication",
];

/** `METADATA_GAPS` as one phrase for notices. */
export const METADATA_GAPS_TEXT: string = `${METADATA_GAPS.slice(0, -1).join(", ")} or ${METADATA_GAPS.at(-1) ?? ""}`;

/**
 * Builds a snapshot from a `GeneratorMetadata` document alone, for
 * `gen --metadata`. Relations come from `relationships`, single-column unique
 * keys from `is_unique` and single-column checks from `check`, named as
 * Postgres names them by default (`<table>_<column>_key`, `<table>_<column>_check`).
 * Everything else the extras carry is empty, and `extras.fromMetadata` says so.
 */
export function fromMetadata(document: GeneratorMetadata): Snapshot {
  const { metadata } = stabilizeMetadata(document);
  const tableIds = new Set(metadata.tables.map((table) => table.id));
  const relations = [
    ...metadata.tables,
    ...metadata.foreignTables,
    ...metadata.views,
    ...metadata.materializedViews,
  ];
  const tables = relations.map((relation): ExtrasTable => {
    const columns = metadata.columns
      .filter((column) => column.table_id === relation.id)
      .sort((a, b) => a.ordinal_position - b.ordinal_position);
    const own = tableIds.has(relation.id);
    return {
      id: relation.id,
      schema: relation.schema,
      name: relation.name,
      primaryKey: [],
      uniques: own
        ? columns
            .filter((column) => column.is_unique)
            .map((column) => ({
              name: `${relation.name}_${column.name}_key`,
              columns: [column.name],
            }))
        : [],
      foreignKeys: own
        ? metadata.relationships
            .filter(
              (fk) =>
                fk.schema === relation.schema && fk.relation === relation.name,
            )
            .map((fk) => ({
              name: fk.foreign_key_name,
              onDelete: "no action" as const,
              onUpdate: "no action" as const,
            }))
            .sort((a, b) => byCodePoint(a.name, b.name))
        : [],
      checks: own
        ? columns.flatMap((column) =>
            column.check === null
              ? []
              : [
                  {
                    name: `${relation.name}_${column.name}_check`,
                    // `check` is the pretty-printed body; the extras read
                    // `pg_get_constraintdef` unpretty, which wraps it twice.
                    definition: `CHECK ((${column.check}))`,
                  },
                ],
          )
        : [],
      indexes: [],
      policies: [],
      triggers: [],
      grants: [],
    };
  });
  return {
    version: 2,
    schemas: [...new Set(metadata.schemas.map((schema) => schema.name))].sort(
      byCodePoint,
    ),
    generator: metadata,
    extras: { tables, buckets: [], realtime: [], fromMetadata: true },
  };
}
