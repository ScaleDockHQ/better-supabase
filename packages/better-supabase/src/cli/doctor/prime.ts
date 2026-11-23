import type { DoctorContext } from "./rules.ts";

import { primeAdoption } from "../adopted-columns.ts";
import { primeStatements } from "../schema-reader/index.ts";
import { primeSchemaFacts } from "../sql-facts.ts";
import { adoptionContext, appTablesOf } from "./app-tables.ts";

/**
 * Reads the context's SQL files with the parser so the rules can scan them. A
 * file that does not parse keeps empty facts: a check must still run on it.
 */
export async function primeDoctorFacts(context: DoctorContext): Promise<void> {
  await primeSchemaFacts(context.sqlFiles ?? [], context.config.root, {
    lenient: true,
  });

  await primeAdoption(
    context.config.blocks,
    appTablesOf(context),
    adoptionContext(context).subjects,
  );

  // The seed and data rules split these files too, but read no facts from them.
  await primeStatements(
    [
      ...(context.seedFiles ?? []),
      ...(context.dataFiles ?? []),
      ...(context.functionFiles ?? []),
    ].map((file) => file.text),
  );
}
