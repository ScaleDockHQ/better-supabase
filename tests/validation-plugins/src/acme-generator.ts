import {
  defineGenerator,
  HEADER,
  siblingPath,
  tableEntries,
} from "better-supabase/generators";

export interface AcmeGeneratorOptions {
  /** Output path relative to the project root. */
  readonly output?: string;
}

/**
 * A generator that lives outside the library. It imports only the public kit,
 * writes the table names and an empty validators map, and declares itself pure
 * and worker safe.
 */
export function acmeTables(options: AcmeGeneratorOptions = {}) {
  return defineGenerator({
    name: "acme-tables",
    version: "1.0.0",
    options,
    pure: true,
    workerSafe: true,
    provides: ["validators"],
    generate: (input) => {
      const path =
        options.output ?? siblingPath(input.config.output, "acme.ts");

      const names = tableEntries(input).map(
        ([key]) => `  ${JSON.stringify(key)},`,
      );

      return [
        {
          path,
          contents: [
            HEADER,
            `import type { TableValidators } from ${JSON.stringify(input.imports.runtime)};`,
            "",
            "export const tableNames = [",
            ...names,
            "] as const;",
            "",
            "export const validators: TableValidators = {};",
            "",
          ].join("\n"),
        },
      ];
    },
  });
}
