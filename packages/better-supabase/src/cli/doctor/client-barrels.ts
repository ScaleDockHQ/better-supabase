import { posix } from "node:path";

import type { Rule } from "./rules.ts";

import { schemaModulePath } from "../gen/emit.ts";
import { lineOf } from "./shared.ts";

/** A `"use client"` directive as the first statement, after comments. */
const USE_CLIENT =
  /^\s*(?:(?:\/\/[^\n]*|\/\*[\s\S]*?\*\/)\s*)*["']use client["']/;

const SPECIFIER =
  /(?:\bfrom\s*|\bimport\s*\(\s*|\bimport\s+)(["'])(\.{1,2}\/[^"']+|@\/[^"']+|~\/[^"']+)\1/g;

const stem = (specifier: string): string =>
  posix.basename(specifier).replace(/\.[cm]?[jt]sx?$/, "");

/**
 * BS621: a client file imports a generated module that holds every table or
 * every block. The server's schema and the block barrels are for server code; a
 * browser page imports the table modules and block slices it uses.
 */
export const CLIENT_BARREL_RULES: readonly Rule[] = [
  {
    code: "BS621",
    severity: "warning",
    title: "A client file imports a generated barrel",
    description:
      'A file with `"use client"` imports `generated-schema`, `blocks.generated` or `blocks.config`. Each one lists every table or every installed block, so the page ships all of them. Import the table modules (`tables/<table>`) and block slices (`blocks/slices`) the page uses, and build the browser\'s client over `clientSchema`.',
    check: (context) => {
      if (
        context.config.gen.tableModules === false ||
        context.config.gen.contentMapper === true
      ) {
        return [];
      }

      const barrels = new Set([
        stem(schemaModulePath(context.config.output)),
        "blocks.generated",
        "blocks.config",
      ]);

      return context.sources
        .filter((file) => USE_CLIENT.test(file.text))
        .flatMap((file) =>
          [...file.text.matchAll(SPECIFIER)]
            .filter((match) => barrels.has(stem(match[2]!)))
            .map((match) => ({
              message: `${file.path} is a client file and imports \`${stem(match[2]!)}\`, which holds every ${stem(match[2]!).startsWith("blocks") ? "block" : "table"}. Import the table modules or block slices it uses instead.`,
              target: `${file.path}:${stem(match[2]!)}`,
              location: {
                file: file.path,
                line: lineOf(file.text, new RegExp(escape(match[2]!))) ?? 1,
              },
            })),
        );
    },
  },
];

function escape(text: string): string {
  return text.replaceAll(/[.*+?^${}()|[\]\\/]/g, String.raw`\$&`);
}
