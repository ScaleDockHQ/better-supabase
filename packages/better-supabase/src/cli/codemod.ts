/**
 * Source rewrites for `better-supabase codemod`. A small scanner masks strings,
 * template literals and comments, so renames only touch code; there is no
 * parser dependency, so each transform is a narrow, mechanical rename. A
 * release adds the transforms its codemod needs, with a test for each.
 */

import type { ResolvedConfig } from "../config/index.ts";
import type { TenantColumnSkip } from "./codemod-naming-pins.ts";
import type { PlannedFile } from "./core/files.ts";

import { codeRanges } from "./code-ranges.ts";
import { accountCallsCodemod } from "./codemod-account-calls.ts";
import { configCodemod } from "./codemod-config.ts";
import { extraColumnsCodemod } from "./codemod-extra-columns.ts";
import { namingCodemod } from "./codemod-naming.ts";
import { ownedColumnsCodemod } from "./codemod-owned-columns.ts";
import { reportReadMany } from "./codemod-read-many.ts";
import { serverImportsCodemod } from "./codemod-server-imports.ts";
import { renameSubpaths } from "./codemod-subpaths.ts";
import { tableModulesCodemod } from "./codemod-table-modules.ts";
import { generatorsCodemod } from "./generators/codemod.ts";

/** What a project-level codemod reads. */
export interface CodemodProject {
  readonly config: ResolvedConfig;
  /** The project's own `.sql` files under `supabase/`, as absolute paths. */
  readonly sql: readonly { readonly path: string; readonly text: string }[];
  /** The config file, when one was found, and its text. */
  readonly configFile?: string;
  readonly configText?: string;
  /** False when the config did not load and `config` is the default one. */
  readonly configLoaded?: boolean;
  /**
   * The columns of `tables` (`schema.table`) in the live database, by table, or
   * undefined when no database could be read.
   */
  readonly liveColumns?: (
    tables: readonly string[],
  ) => Promise<ReadonlyMap<string, ReadonlySet<string>> | undefined>;
}

/** What a codemod's migration knows about the project's config. */
export interface MigrationContext {
  /** False when the config did not load, so the project's own names are unknown. */
  readonly configLoaded: boolean;
  /**
   * The tenant column names the config sets. `global` is `sql.tenantColumn`.
   * `byTable` is a `columns.<table>.tenant` entry, and it skips that column
   * only on that table.
   */
  readonly tenantColumns: TenantColumnSkip;
}

/** A rewrite of one source file, with the project's context already read. */
export type FileRewrite = (
  path: string,
  text: string,
) => { readonly text: string; readonly review: readonly ReviewLine[] };

export interface Codemod {
  readonly name: string;
  readonly description: string;
  /**
   * Exported names, renamed in imports from `better-supabase` and where the
   * import is used.
   */
  readonly imports?: Readonly<Record<string, string>>;
  /** `better-supabase/<subpath>` import specifiers, renamed. */
  readonly subpaths?: Readonly<Record<string, string>>;
  /** A rewrite of every source file, after the renames above. */
  readonly source?: (text: string) => {
    readonly text: string;
    readonly review: readonly ReviewLine[];
  };
  /**
   * A rewrite of every source file that needs the project (the generated
   * folder, the config). It reads what it needs once and returns the per-file
   * rewrite, which runs after `source`.
   */
  readonly files?: (project: CodemodProject) => Promise<FileRewrite>;
  /**
   * A rewrite of each of the project's own `.sql` files (schema files, seeds),
   * except migrations, which are never rewritten, and files the blocks wrote.
   */
  readonly sql?: (text: string, context: MigrationContext) => string;
  /**
   * SQL for a hand migration the codemod writes next to the app's own, or
   * `undefined` when nothing needs renaming. `sql` is the text of the project's
   * `.sql` files, so a rename of an object the project never mentions writes
   * nothing.
   */
  readonly migration?: (
    sql: string,
    context: MigrationContext,
  ) => { readonly sql?: string; readonly review?: readonly string[] };
  /**
   * Files to write that no per-file rewrite can express, such as SQL moved out
   * of the config. A path the rewrites above also touch is written once, with
   * this text.
   */
  readonly project?: (
    project: CodemodProject,
  ) => Promise<{
    readonly files: readonly PlannedFile[];
    readonly review: readonly { readonly message: string }[];
  }>;
}

export interface ReviewLine {
  readonly line: number;
  readonly message: string;
  /** Set when the line means the command must exit `config_invalid`. */
  readonly errorCode?: "config_invalid";
}

export const CODEMODS: Readonly<Record<string, Codemod>> = {
  naming: namingCodemod(),
  "extra-columns": extraColumnsCodemod(),
  "owned-columns": ownedColumnsCodemod(),
  config: configCodemod(),
  "table-modules": tableModulesCodemod(),
  "account-calls": accountCallsCodemod(),
  "server-imports": serverImportsCodemod(),
  generators: generatorsCodemod(),
  "read-many": {
    name: "read-many",
    description: "List Promise.all groups of reads that db.$many can load",
    source: reportReadMany,
  },
};

interface Edit {
  readonly start: number;
  readonly end: number;
  readonly text: string;
}

function applyEdits(text: string, edits: readonly Edit[]): string {
  let out = "";
  let cursor = 0;

  for (const edit of edits.toSorted((a, b) => a.start - b.start)) {
    if (edit.start < cursor) {
      continue;
    }

    out += text.slice(cursor, edit.start) + edit.text;
    cursor = edit.end;
  }

  return out + text.slice(cursor);
}

const escapeRegExp = (value: string): string =>
  value.replaceAll(/[.*+?^${}()|[\]\\]/g, "\\$&");

function inCode(ranges: readonly [number, number][], index: number): boolean {
  let low = 0;
  let high = ranges.length - 1;

  while (low <= high) {
    const middle = Math.floor((low + high) / 2);
    const [start, end] = ranges[middle]!;

    if (index < start) {
      high = middle - 1;
    } else if (index >= end) {
      low = middle + 1;
    } else {
      return true;
    }
  }

  return false;
}

/** Matches of `pattern` that start in code. */
function codeMatches(
  text: string,
  pattern: RegExp,
  ranges: readonly [number, number][],
): RegExpExecArray[] {
  return [...text.matchAll(pattern)].filter((match) =>
    inCode(ranges, match.index),
  );
}

const IMPORT =
  /\b(import|export)\s+(type\s+)?\{([^}]*)\}\s*from\s*(["'])better-supabase(?:\/([\w./-]*))?\4/g;

/** Renames imported names, from every subpath or only from `subpath`. */
function renameImports(
  text: string,
  renames: Readonly<Record<string, string>>,
  subpath?: string,
): { text: string; locals: Set<string> } {
  const ranges = codeRanges(text);
  const locals = new Set<string>();
  const edits: Edit[] = [];

  for (const match of codeMatches(text, IMPORT, ranges)) {
    if (subpath !== undefined && match[5] !== subpath) {
      continue;
    }

    const list = match[3]!;
    const listStart = match.index + match[0].indexOf("{") + 1;

    const renamed = list.replaceAll(
      /(\btype\s+)?([\w$]+)(\s+as\s+[\w$]+)?/g,
      (spec, type: string | undefined, name: string, alias?: string) => {
        const to = renames[name];

        if (to === undefined) {
          return spec;
        }

        if (alias === undefined && match[1] === "import") {
          locals.add(name);
        }

        return `${type ?? ""}${to}${alias ?? ""}`;
      },
    );

    if (renamed !== list) {
      edits.push({
        start: listStart,
        end: listStart + list.length,
        text: renamed,
      });
    }
  }

  return { text: applyEdits(text, edits), locals };
}

function renameIdentifiers(
  text: string,
  renames: ReadonlyMap<string, string>,
): string {
  if (renames.size === 0) {
    return text;
  }

  const ranges = codeRanges(text);
  const names = [...renames.keys()].map(escapeRegExp).join("|");
  const pattern = new RegExp(`(?<![\\w$.])(?:${names})(?![\\w$])`, "g");

  return applyEdits(
    text,
    codeMatches(text, pattern, ranges).map((match) => ({
      start: match.index,
      end: match.index + match[0].length,
      text: renames.get(match[0])!,
    })),
  );
}

export interface CodemodResult {
  readonly text: string;
  /** 1-based lines that need a manual change, with the reason. */
  readonly review: readonly ReviewLine[];
}

/** Applies one codemod to a source file. */
export function applyCodemod(
  codemod: Codemod,
  source: string,
  rewrite?: FileRewrite,
  path: string = "",
): CodemodResult {
  let text = source;
  const review: ReviewLine[] = [];

  if (codemod.subpaths) {
    text = renameSubpaths(text, codemod.subpaths);
  }

  if (codemod.imports) {
    const imported = renameImports(text, codemod.imports);
    text = renameIdentifiers(
      imported.text,
      new Map(
        [...imported.locals].map((name) => [name, codemod.imports![name]!]),
      ),
    );
  }

  if (codemod.source) {
    const rewritten = codemod.source(text);
    text = rewritten.text;
    review.push(...rewritten.review);
  }

  if (rewrite) {
    const rewritten = rewrite(path, text);
    text = rewritten.text;
    review.push(...rewritten.review);
  }

  return { text, review };
}
