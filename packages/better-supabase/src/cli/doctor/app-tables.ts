import type { DoctorContext } from "./rules.ts";

import { declaredTables } from "../../sql/index.ts";
import { writtenByBlocks } from "../sql-layout.ts";
import { catalogOf, qualified } from "./shared.ts";

/**
 * The app's tables in the database, as `ownTables`: those in `schemas` that no
 * block file or module migration creates.
 */
export function appTablesOf(
  context: DoctorContext,
): Readonly<Record<string, string>> {
  const created = new Set(
    declaredTables(
      (context.sqlFiles ?? []).filter(writtenByBlocks),
      context.config.schemas,
    ),
  );

  return Object.fromEntries(
    catalogOf(context)
      .tables.filter(
        (table) =>
          context.config.schemas.includes(table.schema) &&
          !created.has(qualified(table)),
      )
      .map((table) => [qualified(table), "database"]),
  );
}
