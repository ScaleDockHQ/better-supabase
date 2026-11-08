import type { Rule } from "./rules.ts";

import { NAMING_RENAMES } from "../codemod-naming.ts";
import { lineOf } from "./shared.ts";

const escaped = (text: string): string =>
  text.replaceAll(/[.*+?^${}()|[\]\\/]/g, String.raw`\$&`);

/** The kinds that name something in source code; SQL object renames don't. */
const SOURCE_KINDS: ReadonlySet<string> = new Set([
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

/** BS260: a source file that still uses a name `api/naming.json` renamed. */
export const NAMING_RENAME_RULES: readonly Rule[] = [
  {
    code: "BS260",
    severity: "warning",
    title: "Code uses a name that api/naming.json renamed",
    description:
      "The app sources name an export, type, subpath or environment variable that the rename table of `api/naming.json` replaced. The old names have no alias. `better-supabase codemod naming` renames them.",
    check: (context) =>
      context.sources.flatMap((file) =>
        OLD_NAMES.filter(({ pattern }) => pattern.test(file.text)).map(
          ({ rename, pattern }) => ({
            message: `${file.path} uses \`${rename.from}\`, which ${rename.since} renamed \`${rename.to}\`. Run \`better-supabase codemod naming\`.`,
            target: file.path,
            location: {
              file: file.path,
              line: lineOf(file.text, new RegExp(pattern.source)) ?? 1,
            },
          }),
        ),
      ),
  },
];
