import { primeSchemaTexts } from "../../src/cli/sql-facts.ts";

/**
 * Reads the texts of `files` so a doctor rule can read their facts and
 * statements.
 */
export const primeFiles = (
  files: readonly { readonly text: string }[],
): Promise<void> => primeSchemaTexts(files.map((file) => file.text));
