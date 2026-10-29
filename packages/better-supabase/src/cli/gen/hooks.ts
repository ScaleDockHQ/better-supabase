import { posix } from "node:path";

import type { GeneratedFile, ResolvedConfig } from "../../config/index.ts";

import { GENERATED_HEADER } from "./emit.ts";
import { destructuredCall, importGroup, sortImports } from "./layout.ts";
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
  options: { readonly runtimeImport?: string } = {},
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

  const hooksImport = `import { defineDataHooks } from ${q(runtimeSubpath(runtime, config.hooks))};`;

  const selectImport =
    select && `import { ${select.export} } from ${q(select.module)};`;

  const group = select && importGroup(select.module);

  return {
    path: hooksPath(config),
    contents: [
      GENERATED_HEADER,
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
      ...(selectImport && group === "relative" ? ["", selectImport] : []),
      "",
      "type AppDb = DbOf<typeof betterSupabase>;",
      ...tables.flatMap((property) => {
        const names = hookNames(property);

        return [
          "",
          ...destructuredCall(
            [
              ["useList", names.list],
              ["useOne", names.one],
            ],
            "defineDataHooks",
            [q(property), wrap(`(db: AppDb) => ${access(property)}`)],
          ),
        ];
      }),
      "",
    ].join("\n"),
  };
}
