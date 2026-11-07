import type { DoctorContext, FindingInput } from "./rules.ts";

import { ownedColumns } from "../../sql/index.ts";
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

  const rendered = (await moduleFiles(context))
    .filter(({ file }) => file.kind === "schema")
    .map(({ file }) => ({ contents: file.contents }));

  return ownedColumns(rendered, app, context.config.schemas).map(
    (entry): FindingInput => ({
      message: `${entry.table}.${entry.column} is added by a block to a table your files create, and your files don't declare it. A later release leaves such columns out and turns the block's feature off for them. Run \`better-supabase codemod owned-columns\` to declare it in your schema files.`,
      target: `${entry.table}.${entry.column}`,
    }),
  );
}
