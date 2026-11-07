import { posix } from "node:path";

import type { GeneratedFile, ResolvedConfig } from "../../config/index.ts";
import type { TableModuleInfo } from "./tables.ts";

import { byCodePoint } from "../compare.ts";
import { GENERATED_HEADER } from "./emit.ts";
import { importGroup, pureExport, sortImports } from "./layout.ts";
import { pascal, q, runtimeSubpath, singular } from "./shared.ts";

const IDENTIFIER = /^[A-Za-z_$][\w$]*$/;

function access(property: string): string {
  return IDENTIFIER.test(property) ? `db.${property}` : `db[${q(property)}]`;
}

/** `hooks.ts`, next to the main generated module. */
function hooksPath(config: Pick<ResolvedConfig, "output">): string {
  return posix.join(posix.dirname(config.output), "hooks.ts");
}

/** The list and record hook names for a `db` property. */
export function hookNames(property: string): {
  readonly list: string;
  readonly one: string;
} {
  const name = pascal(property);
  const one = pascal(singular(property));

  return one === name
    ? { list: `use${name}List`, one: `use${name}` }
    : { list: `use${name}`, one: `use${one}` };
}

/**
 * `hooks.ts`: `defineDataHooks` from the `gen.hooks` framework once per table,
 * typed by the app's definition in `./index`. Block instances keep their own
 * client methods on `db.<instance>`, which take their own arguments.
 * `undefined` with `hooks: false`.
 */
export function emitHooks(
  config: Pick<ResolvedConfig, "hooks" | "hooksSelect" | "output">,
  tables: readonly string[],
  options: {
    readonly runtimeImport?: string;
    /** Per-table modules: the hooks read through `client.table(<module>)`. */
    readonly tables?: readonly TableModuleInfo[];
  } = {},
): GeneratedFile | undefined {
  if (config.hooks === false) {
    return undefined;
  }

  const runtime = options.runtimeImport ?? "better-supabase";

  if (tables.length === 0) {
    return undefined;
  }

  const select = config.hooksSelect;

  const wrap = (fn: string): string =>
    select === undefined ? fn : `${select.export}(${fn})`;

  const hooksImport = `import { defineListHook, defineOneHook } from ${q(runtimeSubpath(runtime, config.hooks))};`;

  const selectImport =
    select && `import { ${select.export} } from ${q(select.module)};`;

  const group = select && importGroup(select.module);

  const moduleOf = new Map(
    (options.tables ?? []).map((table) => [table.key, table]),
  );

  const tableImports = [...moduleOf.values()]
    .toSorted((a, b) => byCodePoint(a.specifier, b.specifier))
    .map((table) => `import { ${table.name} } from ${q(table.specifier)};`);

  return {
    path: hooksPath(config),
    contents: [
      GENERATED_HEADER,
      "/* oxlint-disable no-inline-comments -- the PURE annotations sit inline. */",
      ...(config.hooks === "react" ? ['"use client";'] : []),
      "",
      `import type { DbOf } from ${q(runtime)};`,
      "",
      ...(selectImport && group === "external"
        ? sortImports([hooksImport, selectImport])
        : [hooksImport]),
      ...(selectImport && group === "internal" ? ["", selectImport] : []),
      "",
      'import type { betterSupabase } from "./index";',
      ...(tableImports.length > 0 ? ["", ...tableImports] : []),
      ...(selectImport && group === "relative" ? ["", selectImport] : []),
      "",
      "type AppDb = DbOf<typeof betterSupabase>;",
      ...tables.flatMap((property) => {
        const names = hookNames(property);

        const module = moduleOf.get(property);

        const select = [
          q(property),
          wrap(`(db: AppDb) => ${access(property)}`),
          ...(module === undefined ? [] : [module.name]),
        ];

        return [
          "",
          ...pureExport(names.list, "defineListHook", select),
          "",
          ...pureExport(names.one, "defineOneHook", select),
        ];
      }),
      "",
    ].join("\n"),
  };
}
