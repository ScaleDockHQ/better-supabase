import type { ResolvedConfig } from "../../config/index.ts";
import type { BlockSqlFile } from "../../sql/index.ts";
import type { CommandResult } from "../core/io.ts";

import { readFileFacts, SchemaReadFailure } from "../schema-reader/index.ts";
import { layoutFor } from "../sql/providers.ts";
import { renderBlocksCached } from "../sql/render-cache.ts";

/** The statement that holds `line` of `text`, trimmed to a readable excerpt. */
function statementAt(text: string, line: number): string {
  const lines = text.split("\n");
  let start = Math.min(line, lines.length) - 1;

  while (start > 0 && !lines[start - 1]!.trimEnd().endsWith(";")) {
    start -= 1;
  }

  let end = Math.min(line, lines.length) - 1;

  while (end < lines.length - 1 && !lines[end]!.trimEnd().endsWith(";")) {
    end += 1;
  }

  const statement = lines
    .slice(start, end + 1)
    .join("\n")
    .trim();

  return statement.length > 400 ? `${statement.slice(0, 400)}...` : statement;
}

/**
 * Parses every rendered module with the Postgres reader, so a template that
 * renders SQL Postgres rejects stops `gen` at the module instead of in the
 * migration.
 *
 * @param files - The rendered module files.
 * @returns A failing result that names the module, the file, the position and
 *   the statement, or `undefined` when all of them parse.
 */
export async function checkRenderedModules(
  files: readonly BlockSqlFile[],
): Promise<CommandResult | undefined> {
  for (const file of files) {
    try {
      await readFileFacts(file.contents, { path: file.path });
    } catch (error) {
      if (error instanceof SchemaReadFailure) {
        const name = file.instance ?? file.module;

        return {
          code: 1,
          error: `The rendered SQL of module ${name} is not valid: ${error.message}\n  ${statementAt(file.contents, error.details.line)}\nThis is a bug in the module template; report it.`,
        };
      }

      throw error;
    }
  }

  return undefined;
}

/**
 * Renders the config's installed modules, through the same cache `upgrade`
 * uses, and parses each one with `checkRenderedModules`.
 *
 * @param config - The resolved config.
 * @returns The failing result of the first module that does not parse, or
 *   `undefined`.
 */
export async function checkInstalledModules(
  config: ResolvedConfig,
): Promise<CommandResult | undefined> {
  if (config.blockNames.length === 0) {
    return undefined;
  }

  return checkRenderedModules(
    await renderBlocksCached(
      config,
      config.blockNames,
      await layoutFor(config, {}, config.blockNames),
    ),
  );
}
