import { primeStatements } from "../../src/cli/schema-reader/index.ts";

/** Splits the texts of `files` so a doctor rule can read their statements. */
export const primeFiles = (
  files: readonly { readonly text: string }[],
): Promise<void> => primeStatements(files.map((file) => file.text));
