import { primeCodeStatements } from "../../src/cli/schema-reader/index.ts";
import { primeSchemaTexts } from "../../src/cli/sql-facts.ts";

/**
 * Reads the texts of `files` so a doctor rule can read their facts, statements
 * and code tokens.
 */
export const primeFiles = async (
  files: readonly { readonly text: string }[],
): Promise<void> => {
  const texts = files.map((file) => file.text);

  await primeSchemaTexts(texts);
  await primeCodeStatements(texts);
};
