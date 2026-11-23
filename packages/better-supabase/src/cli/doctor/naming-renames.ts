import type { NamingRename } from "../codemod-naming.ts";
import type { Rule } from "./rules.ts";

import { renameArguments } from "../codemod-arguments.ts";
import { NAMING_RENAMES, namingCodemod } from "../codemod-naming.ts";
import { applyCodemod } from "../codemod.ts";

const escaped = (text: string): string =>
  text.replaceAll(/[.*+?^${}()|[\]\\/]/g, String.raw`\$&`);

/** The kinds that name something in source code; SQL object renames don't. */
const SOURCE_KINDS: ReadonlySet<string> = new Set([
  "argument",
  "env",
  "event",
  "function",
  "hint",
  "subpath",
  "type",
]);

const OLD_NAMES = NAMING_RENAMES.filter((rename) =>
  SOURCE_KINDS.has(rename.kind),
).map((rename) => ({
  rename,
  pattern: new RegExp(
    rename.kind === "subpath"
      ? `better-supabase/${escaped(rename.from)}(?![\\w-])`
      : `(?<![A-Za-z0-9_])${escaped(rename.from)}(?![A-Za-z0-9_])`,
  ),
}));

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null;

const camel = (name: string): string =>
  name.replaceAll(/[_-]+([a-z0-9])/g, (_, letter: string) =>
    letter.toUpperCase(),
  );

/**
 * The argument names of verbs on an entity the config renamed: an app whose
 * `names.<entity>.name` is `work_item` keeps `workItemId` and `workItemIds`.
 */
function renamedEntityArguments(
  blocks: Readonly<Record<string, unknown>>,
): ReadonlySet<string> {
  const kept = new Set<string>();

  const keep = (name: unknown): void => {
    if (typeof name === "string") {
      kept.add(`${camel(name)}Id`).add(`${camel(name)}Ids`);
    }
  };

  for (const block of Object.values(blocks)) {
    if (!isRecord(block)) {
      continue;
    }

    for (const value of [block["names"], block["entities"]]) {
      if (typeof value === "string") {
        keep(value);
      } else if (isRecord(value)) {
        for (const entity of Object.values(value)) {
          keep(isRecord(entity) ? entity["name"] : entity);
        }
      }
    }
  }

  return kept;
}

/** The line the naming codemod changes first for `rename`, if it changes any. */
function firstChangedLine(
  file: { readonly path: string; readonly text: string },
  rename: NamingRename,
): number | undefined {
  const { text } = applyCodemod(
    namingCodemod([rename]),
    file.text,
    undefined,
    file.path,
  );

  if (text === file.text) {
    return undefined;
  }

  const before = file.text.split("\n");
  const after = text.split("\n");
  const index = before.findIndex((line, at) => line !== after[at]);

  return (index === -1 ? Math.min(before.length, after.length) : index) + 1;
}

/** BS260: a source file that still uses a name `api/naming.json` renamed. */
export const NAMING_RENAME_RULES: readonly Rule[] = [
  {
    code: "BS260",
    severity: "warning",
    title: "Code uses a name that api/naming.json renamed",
    description:
      "The app sources name an export, type, subpath or environment variable that the rename table of `api/naming.json` replaced. The old names have no alias. `better-supabase codemod naming` renames them.",
    check: (context) => {
      const kept = renamedEntityArguments(context.config.blocks);

      // An argument name counts only where the codemod renames it, as a key or
      // member, so a local variable of the same name is left alone.
      const argumentAt = (text: string, rename: NamingRename): number => {
        const renamed = renameArguments(text, [rename]).text;
        let at = 0;

        while (at < text.length && text[at] === renamed[at]) {
          at += 1;
        }

        return at === text.length && renamed.length === text.length ? -1 : at;
      };

      return context.sources.flatMap((file) =>
        OLD_NAMES.flatMap(({ rename, pattern }) => {
          let line: number | undefined;

          if (rename.kind === "argument") {
            const at = kept.has(rename.from)
              ? -1
              : argumentAt(file.text, rename);

            if (at === -1) {
              return [];
            }

            line = file.text.slice(0, at).split("\n").length;
          } else if (pattern.test(file.text)) {
            // The finding is what the codemod would change, so a comment or a
            // string that only mentions the name never counts.
            line = firstChangedLine(file, rename);

            if (line === undefined) {
              return [];
            }
          } else {
            return [];
          }

          return [
            {
              message: `${file.path} uses \`${rename.from}\`, which ${rename.since} renamed \`${rename.to}\`. Run \`better-supabase codemod naming\`.`,
              target: file.path,
              location: { file: file.path, line },
            },
          ];
        }),
      );
    },
  },
];
