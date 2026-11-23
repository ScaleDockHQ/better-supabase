import { posix } from "node:path";

import type { Rule } from "./rules.ts";

import { schemaModulePath } from "../gen/emit.ts";
import { hasDirective, moduleSpecifiers } from "./tree.ts";

/** A relative or aliased specifier; a package never is a generated barrel. */
const LOCAL_SPECIFIER = /^(?:\.{1,2}\/|@\/|~\/)/;

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
        .filter((file) => hasDirective(file.text, "use client"))
        .flatMap((file) =>
          moduleSpecifiers(file.text)
            .filter(
              (site) =>
                LOCAL_SPECIFIER.test(site.specifier) &&
                barrels.has(stem(site.specifier)),
            )
            .map((site) => ({
              message: `${file.path} is a client file and imports \`${stem(site.specifier)}\`, which holds every ${stem(site.specifier).startsWith("blocks") ? "block" : "table"}. Import the table modules or block slices it uses instead.`,
              target: `${file.path}:${stem(site.specifier)}`,
              location: { file: file.path, line: site.line },
            })),
        );
    },
  },
];
