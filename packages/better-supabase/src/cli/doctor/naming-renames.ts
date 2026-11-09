import type { Rule } from "./rules.ts";

import { NAMING_RENAMES } from "../codemod-naming.ts";
import { lineOf } from "./shared.ts";

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

      return context.sources.flatMap((file) =>
        OLD_NAMES.filter(
          ({ rename, pattern }) =>
            !(rename.kind === "argument" && kept.has(rename.from)) &&
            pattern.test(file.text),
        ).map(({ rename, pattern }) => ({
          message: `${file.path} uses \`${rename.from}\`, which ${rename.since} renamed \`${rename.to}\`. Run \`better-supabase codemod naming\`.`,
          target: file.path,
          location: {
            file: file.path,
            line: lineOf(file.text, new RegExp(pattern.source)) ?? 1,
          },
        })),
      );
    },
  },
];
