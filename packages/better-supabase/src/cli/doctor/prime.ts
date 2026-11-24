import type { SchemaReadError } from "../schema-reader/facts.ts";
import type { DoctorContext } from "./rules.ts";

import { primeAdoption } from "../adopted-columns.ts";
import {
  primeCodeStatements,
  primeStatements,
} from "../schema-reader/index.ts";
import { primeSchemaFacts } from "../sql-facts.ts";
import { adoptionContext, appTablesOf } from "./app-tables.ts";
import { hookTokenFiles } from "./hooks.ts";

/**
 * Reads the context's SQL files with the parser so the rules can scan them. A
 * file that does not parse keeps empty facts: a check must still run on it.
 * Returns those files for BS731.
 */
export async function primeDoctorFacts(
  context: DoctorContext,
): Promise<readonly SchemaReadError[]> {
  const unread = await primeSchemaFacts(
    context.sqlFiles ?? [],
    context.config.root,
    { lenient: true },
  );

  // The rules that read calls and names in SQL bodies read code tokens. BS629
  // reads the migrations one at a time itself, so they are not all kept.
  await primeCodeStatements(
    [
      ...(context.sqlFiles ?? []).filter(
        (file) => !file.path.includes("/migrations/"),
      ),
      ...hookTokenFiles(context),
    ].map((file) => file.text),
  );

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

  return unread;
}
