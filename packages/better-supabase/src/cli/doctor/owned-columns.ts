import type { DoctorContext, FindingInput } from "./rules.ts";

import { duplicateObjects, ownedColumns } from "../../sql/index.ts";
import { writtenByBlocks } from "../sql-layout.ts";
import { moduleFiles } from "./module-files.ts";

/**
 * Columns a block adds to a table the app creates, which the app's own files
 * don't declare (BS622).
 */
export async function blockColumnsOnOwnedTables(
  context: DoctorContext,
): Promise<FindingInput[]> {
  const app = (context.sqlFiles ?? []).filter(
    (file) =>
      !file.path.includes("migrations/") &&
      !file.path.includes("better-supabase-data/") &&
      !writtenByBlocks(file),
  );

  const rendered = (await moduleFiles(context, { keepUndeclaredColumns: true }))
    .filter(({ file }) => file.kind === "schema")
    .map(({ file }) => ({ contents: file.contents }));

  return ownedColumns(rendered, app, context.config.schemas).map(
    (entry): FindingInput => ({
      message: `${entry.table}.${entry.column} is added by a block to a table your files create, and your files don't declare it. Blocks leave such columns out and turn the feature that needs them off. Run \`better-supabase codemod owned-columns\` to declare it in your schema files.`,
      target: `${entry.table}.${entry.column}`,
    }),
  );
}

/**
 * Block indexes and triggers that an object of the app's already covers (BS623,
 * BS624).
 */
export async function duplicatedBlockObjects(
  context: DoctorContext,
  kind: "index" | "trigger",
): Promise<FindingInput[]> {
  const app = (context.sqlFiles ?? []).filter(
    (file) =>
      !file.path.includes("migrations/") &&
      !file.path.includes("better-supabase-data/") &&
      !writtenByBlocks(file),
  );

  const rendered = (await moduleFiles(context))
    .filter(({ file }) => file.kind === "schema")
    .map(({ file }) => ({ contents: file.contents }));

  return duplicateObjects(rendered, app, context.config.schemas)
    .filter((entry) => entry.kind === kind)
    .map((entry): FindingInput => ({
      message:
        kind === "index"
          ? `${entry.table}: the block's unique index ${entry.block} ${entry.reason === "identical" ? "repeats" : "is weaker than"} your index ${entry.app}, so every write maintains both. Drop the block's, or set the block's key columns to the ones your index covers.`
          : `${entry.table}: the block's trigger ${entry.block} does the work of ${entry.app} in your files, so both run on every write. Keep one of them.`,
      target: `${entry.table}.${entry.block}`,
    }));
}
