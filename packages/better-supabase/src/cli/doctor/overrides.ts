import { createHash } from "node:crypto";

import type { DoctorContext, FindingInput, Rule, TextFile } from "./rules.ts";

import { ownerOf, splitStatements } from "../../sql/index.ts";

const IDENT = String.raw`(?:"(?:[^"]|"")+"|[A-Za-z_][\w$]*)`;

/** `-- @bsb-override-of schema.fn <hash>`, then the app's own `create function`. */
const TAGGED = new RegExp(
  String.raw`^[^\S\n]*--[^\S\n]*@bsb-override-of[^\S\n]+(${IDENT}(?:\.${IDENT})?)[^\S\n]+([0-9a-f]{6,64})[^\S\n]*\n(?:[^\S\n]*--[^\n]*\n|[^\S\n]*\n)*[^\S\n]*create[^\S\n]+(?:or[^\S\n]+replace[^\S\n]+)?(?:function|procedure)[^\S\n]+(${IDENT}(?:\.${IDENT})?)`,
  "gim",
);

const FUNCTION_START = new RegExp(
  String.raw`^create\s+(?:or\s+replace\s+)?(?:function|procedure)\s+(${IDENT}(?:\s*\.\s*${IDENT})?)\s*\(`,
  "i",
);

/** `schema.name` unquoted, with `public` for a bare name. */
const plain = (name: string): string => {
  const parts = name
    .split(/\s*\.\s*/)
    .map((part) => part.replace(/^"(.*)"$/, "$1").replaceAll('""', '"'));

  return parts.length === 1 ? `public.${parts[0] ?? ""}` : parts.join(".");
};

/** One override an app file declares. */
export interface Override {
  readonly file: string;
  readonly line: number;
  /** The block function the app's function replaces, `schema.name`. */
  readonly of: string;
  /** The hash of the block function when the app copied it. */
  readonly hash: string;
  /** The app's own function, `schema.name`. */
  readonly name: string;
}

/**
 * The hash a `@bsb-override-of` tag records: the first twelve hex digits of the
 * SHA-256 of the function statement with its whitespace collapsed.
 */
export function overrideHash(statements: readonly string[]): string {
  return createHash("sha256")
    .update(
      statements
        .map((text) => text.replaceAll(/\s+/g, " ").trim().replace(/;$/, ""))
        .join("\n"),
    )
    .digest("hex")
    .slice(0, 12);
}

/** The overrides the app's schema files declare. */
export function overridesIn(files: readonly TextFile[]): readonly Override[] {
  return files
    .filter((file) => ownerOf(file.path, file.text).kind === "app")
    .flatMap((file) =>
      [...file.text.matchAll(TAGGED)].map((match) => ({
        file: file.path,
        line: file.text.slice(0, match.index).split("\n").length,
        of: plain(match[1] ?? ""),
        hash: (match[2] ?? "").toLowerCase(),
        name: plain(match[3] ?? ""),
      })),
    );
}

/**
 * The `create function` statements of `schema.name` in the block modules'
 * files.
 */
function moduleFunctions(
  files: readonly TextFile[],
  name: string,
): readonly string[] {
  return files
    .filter((file) => ownerOf(file.path, file.text).kind === "module")
    .flatMap((file) =>
      splitStatements(file.text)
        .map((statement) => statement.text)
        .filter((text) => {
          const declared = FUNCTION_START.exec(
            text.replaceAll(/\s+/g, " "),
          )?.[1];

          return declared !== undefined && plain(declared) === name;
        }),
    );
}

const schemaFiles = (context: DoctorContext): readonly TextFile[] =>
  (context.sqlFiles ?? []).filter(
    (file) =>
      !file.path.includes("migrations/") &&
      !file.path.includes("better-supabase-data/"),
  );

/** Overrides of block functions, held against the block modules' current text. */
export const OVERRIDE_RULES: readonly Rule[] = [
  {
    code: "BS394",
    severity: "warning",
    title: "An app override of a block function has drifted",
    description:
      "An app file that replaces a block function marks it with `-- @bsb-override-of schema.fn <hash>` above its own `create function`, where the hash is the one doctor prints for the block's function when the copy was made. When the block module's function changes, a later `upgrade` leaves the override behind, so it keeps the old behavior. Doctor compares the recorded hash with the module's current function and reports a difference, or a tag whose target no module declares. Diff the module's function against the copy, merge what changed, then set the hash doctor prints. A tagged override is not reported by BS369. Reads every schema file.",
    check(context) {
      const files = schemaFiles(context);

      return overridesIn(files).flatMap((override): FindingInput[] => {
        const current = moduleFunctions(files, override.of);

        const location = { file: override.file, line: override.line };

        if (current.length === 0) {
          return [
            {
              message: `${override.file}:${override.line} overrides ${override.of}, which no block module declares. Remove the tag, or name the function the module declares.`,
              target: `${override.file}:${override.of}`,
              location,
            },
          ];
        }

        const hash = overrideHash(current);

        if (hash.startsWith(override.hash) || override.hash.startsWith(hash)) {
          return [];
        }

        return [
          {
            message: `${override.file}:${override.line}: ${override.name} overrides ${override.of}, and the module's function changed since the override recorded ${override.hash}. Diff it against the module, then write \`-- @bsb-override-of ${override.of} ${hash}\`.`,
            target: `${override.file}:${override.of}`,
            location,
          },
        ];
      });
    },
  },
];
