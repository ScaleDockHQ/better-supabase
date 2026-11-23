import { MagicString } from "magic-string";
import { realpathSync } from "node:fs";

import type { ReviewLine } from "./codemod.ts";
import type { ProjectSymbols } from "./typescript-symbols/index.ts";

import { lineColumn, parseSource } from "./config-document/parse.ts";

/** A renamed export the app passes on under the same name. */
export interface Reexport {
  readonly file: string;
  /** Where the exported name is written, in the original text. */
  readonly offset: number;
  readonly from: string;
  readonly to: string;
}

/** `path` as the disk spells it, or `path` when it does not exist. */
function onDisk(path: string): string {
  try {
    return realpathSync.native(path);
  } catch {
    return path;
  }
}

const packageName = (source: string): boolean =>
  source === "better-supabase" || source.startsWith("better-supabase/");

/**
 * The renamed exports `file` re-exports from better-supabase without an alias
 * (`export { old } from "better-supabase"`). Files that import `old` from
 * `file` need the new name too, and no single file can tell which they are.
 */
export function reexportsIn(
  file: string,
  text: string,
  renames: Readonly<Record<string, string>>,
): Reexport[] {
  const found: Reexport[] = [];
  const parsed = parseSource(text);

  for (const statement of parsed.program.body) {
    if (
      statement.type !== "ExportNamedDeclaration" ||
      !statement.source ||
      !packageName(statement.source.value)
    ) {
      continue;
    }

    for (const specifier of statement.specifiers) {
      const { local, exported } = specifier;

      if (
        local.type === "Identifier" &&
        exported.type === "Identifier" &&
        local.name === exported.name &&
        renames[local.name] !== undefined
      ) {
        found.push({
          file,
          offset: exported.start,
          from: local.name,
          to: renames[local.name]!,
        });
      }
    }
  }

  return found;
}

/** A replacement in the original text of a file. */
interface Splice {
  readonly start: number;
  readonly end: number;
  readonly to: string;
}

/**
 * The edits that follow each re-export through the project, by file, and the
 * review lines for what they could not follow. The barrel file itself is left
 * to the per-file rename.
 */
export function followReexports(
  reexports: readonly Reexport[],
  symbols: ProjectSymbols | undefined,
  files: readonly string[],
  textOf: (file: string) => string | undefined,
): {
  readonly splices: ReadonlyMap<string, readonly Splice[]>;
  readonly review: ReadonlyMap<string, readonly ReviewLine[]>;
} {
  // The tier may report a path in another case on a case-insensitive disk.
  const scanned = new Map<string, string>();

  for (const file of files) {
    scanned.set(file, file);
    scanned.set(onDisk(file), file);
  }

  const splices = new Map<string, Splice[]>();
  const review = new Map<string, ReviewLine[]>();

  for (const reexport of reexports) {
    const text = textOf(reexport.file) ?? "";
    const line = lineColumn(text, reexport.offset).line;
    const lines = review.get(reexport.file) ?? [];

    review.set(reexport.file, lines);

    if (symbols === undefined || "skipped" in symbols) {
      const reason =
        symbols === undefined
          ? "the TypeScript symbol tier is off"
          : symbols.skipped;

      lines.push({
        line,
        message: `${reexport.from} is renamed to ${reexport.to}, and this file passes it on under the old name. The files that import it from here were not changed (${reason}); rename them by hand, or install typescript 7.1 or later and run the codemod again.`,
      });
      continue;
    }

    const own = reexport.file;

    for (const found of symbols.tier.references(own, reexport.offset)) {
      const file = scanned.get(found.file) ?? scanned.get(onDisk(found.file));
      const place = { ...found, file: file ?? found.file };
      const there = file === undefined ? undefined : textOf(file);

      // The declaration in better-supabase and the barrel itself are not edited.
      if (place.file === own || there === undefined) {
        continue;
      }

      if (there.slice(place.start, place.end) !== reexport.from) {
        lines.push({
          line,
          message: `${place.file} uses ${reexport.from} in a way the codemod cannot rename in place; rename it by hand.`,
        });
        continue;
      }

      const list = splices.get(place.file) ?? [];

      if (!list.some((each) => each.start === place.start)) {
        list.push({ start: place.start, end: place.end, to: reexport.to });
      }

      splices.set(place.file, list);
    }
  }

  return { splices, review };
}

/** `text` with `splices`, which are offsets into `text`, applied. */
export function applySplices(text: string, splices: readonly Splice[]): string {
  const edit = new MagicString(text);

  for (const splice of splices) {
    edit.overwrite(splice.start, splice.end, splice.to);
  }

  return edit.toString();
}
