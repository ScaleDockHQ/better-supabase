import { createHash } from "node:crypto";
import { mkdir, stat, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { BlockSqlFile } from "../../sql/index.ts";
import type { CommandResult } from "../core/io.ts";

import { cacheEnabled, cacheRoot } from "../cache/store.ts";
import { getFileFacts, SchemaReadFailure } from "../schema-reader/index.ts";
import { PG_PARSER_VERSION } from "../schema-reader/node-fields.generated.ts";
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

/** Marker files of rendered texts that already parsed, by content hash. */
const markerFolder = (root: string): string =>
  resolve(cacheRoot(root), "parsed-ok");

/** The parser version is part of the name, so a new parser re-reads every text. */
const markerName = (contents: string): string =>
  createHash("sha256")
    .update(`${PG_PARSER_VERSION}\n${contents}`)
    .digest("hex");

/**
 * Parses every rendered module with the Postgres reader, so a template that
 * renders SQL Postgres rejects stops `gen` at the module instead of in the
 * migration.
 *
 * @param files - The rendered module files.
 * @param root - The project root. With it, a text that parsed before is
 *   recorded in the cache by content hash and not parsed again.
 * @returns A failing result that names the module, the file, the position and
 *   the statement, or `undefined` when all of them parse.
 */
export async function checkRenderedModules(
  files: readonly BlockSqlFile[],
  root?: string,
): Promise<CommandResult | undefined> {
  const marks =
    root !== undefined && cacheEnabled() ? markerFolder(root) : undefined;

  // Misses parse together; the first failing module in file order is reported.
  const failures = await Promise.all(
    files.map(async (file): Promise<SchemaReadFailure | undefined> => {
      const marker = marks && resolve(marks, markerName(file.contents));

      if (marker !== undefined && (await stat(marker).catch(() => undefined))) {
        return undefined;
      }

      try {
        await getFileFacts(file.contents, { path: file.path });
      } catch (error) {
        if (error instanceof SchemaReadFailure) {
          return error;
        }

        throw error;
      }

      if (marker !== undefined) {
        // A marker that can't be written only costs the next run a parse.
        await mkdir(marks!, { recursive: true })
          .then(() => writeFile(marker, ""))
          .catch(() => undefined);
      }

      return undefined;
    }),
  );

  const at = failures.findIndex((each) => each !== undefined);
  const error = failures[at];
  const file = files[at];

  if (error === undefined || file === undefined) {
    return undefined;
  }

  const name = file.instance ?? file.module;

  return {
    code: 1,
    error: `The rendered SQL of module ${name} is not valid: ${error.message}\n  ${statementAt(file.contents, error.details.line)}\nThis is a bug in the module template; report it.`,
  };
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
    config.root,
  );
}
