/**
 * Source rewrites for `better-supabase codemod`. A small scanner masks strings,
 * template literals and comments, so renames only touch code; there is no
 * parser dependency, so each transform is a narrow, mechanical rename. A
 * release adds the transforms its codemod needs, with a test for each.
 */

import type { Node } from "oxc-parser";

import { MagicString } from "magic-string";
import { ScopeTracker, isReferenceIdentifier, walk } from "oxc-walker";

import type { ResolvedConfig } from "../config/index.ts";
import type { TenantColumnSkip } from "./codemod-naming-pins.ts";
import type { PlannedFile } from "./core/files.ts";
import type { ProjectSymbols } from "./typescript-symbols/index.ts";

import { accountCallsCodemod } from "./codemod-account-calls.ts";
import { adoptNamesCodemod } from "./codemod-adopt-names.ts";
import { auditStatementCodemod } from "./codemod-audit-statement.ts";
import { blocksListCodemod } from "./codemod-blocks-list.ts";
import { configCodemod } from "./codemod-config.ts";
import { declaredRowsCodemod } from "./codemod-declared-rows.ts";
import { doctorBaselineCodemod } from "./codemod-doctor-baseline.ts";
import { reportExpireTags } from "./codemod-expire-tags.ts";
import { extraColumnsCodemod } from "./codemod-extra-columns.ts";
import { namingCodemod } from "./codemod-naming.ts";
import { ownedColumnsCodemod } from "./codemod-owned-columns.ts";
import { reportReadMany } from "./codemod-read-many.ts";
import { recordTypesCodemod } from "./codemod-record-types.ts";
import { serverImportsCodemod } from "./codemod-server-imports.ts";
import { renameSubpaths } from "./codemod-subpaths.ts";
import { tableModulesCodemod } from "./codemod-table-modules.ts";
import { tableTagsCodemod } from "./codemod-table-tags.ts";
import { lineColumn, parseSource } from "./config-document/parse.ts";
import { generatorsCodemod } from "./generators/codemod.ts";

/** What a project-level codemod reads. */
export interface CodemodProject {
  readonly config: ResolvedConfig;
  /** The project's own `.sql` files under `supabase/`, as absolute paths. */
  readonly sql: readonly { readonly path: string; readonly text: string }[];
  /** The config file, when one was found, and its text. */
  readonly configFile?: string;
  readonly configText?: string;
  /**
   * The optional TypeScript 7.1 tier, or why it is off. A codemod that edits a
   * value another file declares follows it with the tier and otherwise
   * reports.
   */
  readonly symbols?: ProjectSymbols;
  /** False when the config did not load and `config` is the default one. */
  readonly configLoaded?: boolean;
  /** `adopt-names`: the table to rename, as `<block>.<table>`. */
  readonly table?: string;
  /** `audit-statement`: the tables to rewrite, as `schema.table`. */
  readonly tables?: readonly string[];
  /**
   * `table-tags --explain`: list what moves and where each tag reaches, write
   * nothing.
   */
  readonly explain?: boolean;
  /** `config --prune`: remove every entry that equals its default. */
  readonly prune?: boolean;
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
  /**
   * The check constraints the app's schema files and seeds name, which the
   * `bsb_` loop leaves alone. Migrations stay out: a diff wrote the old block
   * names there too.
   */
  readonly appChecks?: ReadonlySet<string>;
  /**
   * The policies the app's schema files create, as `schema.table` and name
   * joined by a NUL. They belong to the app (or to a library it installs, such
   * as an authorization provider), so the `bsb_` policy renames leave them
   * alone.
   */
  readonly appPolicies?: ReadonlySet<string>;
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
  readonly source?: (
    text: string,
    path: string,
  ) => { readonly text: string; readonly review: readonly ReviewLine[] };
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
  readonly sql?: (
    text: string,
    context: MigrationContext,
  ) => Promise<string> | string;
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
  "blocks-list": blocksListCodemod(),
  "record-types": recordTypesCodemod(),
  "table-tags": tableTagsCodemod(),
  "adopt-names": adoptNamesCodemod(),
  "declared-rows": declaredRowsCodemod(),
  "doctor-baseline": doctorBaselineCodemod(),
  "table-modules": tableModulesCodemod(),
  "account-calls": accountCallsCodemod(),
  "server-imports": serverImportsCodemod(),
  generators: generatorsCodemod(),
  "expire-tags": {
    name: "expire-tags",
    description:
      "List updateTag and revalidateTag calls that bsb.expireTags replaces",
    source: reportExpireTags,
  },
  "read-many": {
    name: "read-many",
    description: "List Promise.all groups of reads that db.$many can load",
    source: reportReadMany,
  },
  "audit-statement": {
    name: "audit-statement",
    description:
      "Rewrite a table's row audit trigger as static statement triggers",
    project: auditStatementCodemod,
  },
};

/** The subpath of a `better-supabase` module specifier, or undefined. */
function packageSubpath(source: string): string | undefined {
  if (source === "better-supabase") {
    return "";
  }

  return source.startsWith("better-supabase/")
    ? source.slice("better-supabase/".length)
    : undefined;
}

/** Renames imported names, from every subpath or only from `subpath`. */
function renameImports(
  text: string,
  renames: Readonly<Record<string, string>>,
  subpath?: string,
): { text: string; locals: Set<string> } {
  const locals = new Set<string>();
  const parsed = parseSource(text);
  const out = new MagicString(text);

  for (const statement of parsed.program.body) {
    if (
      (statement.type !== "ImportDeclaration" &&
        statement.type !== "ExportNamedDeclaration") ||
      !statement.source
    ) {
      continue;
    }

    const from = packageSubpath(statement.source.value);

    if (from === undefined || (subpath !== undefined && from !== subpath)) {
      continue;
    }

    for (const specifier of statement.specifiers) {
      const imported =
        specifier.type === "ImportSpecifier"
          ? specifier.imported
          : specifier.type === "ExportSpecifier"
            ? specifier.local
            : undefined;

      if (imported?.type !== "Identifier") {
        continue;
      }

      const to = renames[imported.name];

      if (to === undefined) {
        continue;
      }

      out.overwrite(imported.start, imported.end, to);

      const aliased =
        specifier.type === "ImportSpecifier"
          ? specifier.local.start !== imported.start
          : specifier.type === "ExportSpecifier" &&
            specifier.exported.start !== specifier.local.start;

      if (!aliased && statement.type === "ImportDeclaration") {
        locals.add(imported.name);
      }
    }
  }

  return { text: out.toString(), locals };
}

/**
 * Renames the references to a binding that no longer exists: an identifier that
 * is used as a value or type and that no scope in the file declares. A key, a
 * member, a shadowing local and text in a string or comment stay.
 */
function renameIdentifiers(
  text: string,
  renames: ReadonlyMap<string, string>,
): string {
  if (renames.size === 0) {
    return text;
  }

  const parsed = parseSource(text);
  const out = new MagicString(text);
  const scopeTracker = new ScopeTracker();

  walk(parsed.program, {
    scopeTracker,
    enter(node: Node, parent: Node | null): void {
      if (
        node.type !== "Identifier" ||
        parent === null ||
        !renames.has(node.name) ||
        !isReferenceIdentifier(node, parent)
      ) {
        return;
      }

      if (scopeTracker.getDeclaration(node.name, { mode: "all" }) !== null) {
        return;
      }

      const to = renames.get(node.name)!;

      if (parent.type === "Property" && parent.shorthand) {
        out.overwrite(node.start, node.end, `${node.name}: ${to}`);
      } else {
        out.overwrite(node.start, node.end, to);
      }
    },
  });

  return out.toString();
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
    const rewritten = codemod.source(text, path);
    text = rewritten.text;
    review.push(...rewritten.review);
  }

  if (rewrite) {
    const rewritten = rewrite(path, text);
    text = rewritten.text;
    review.push(...rewritten.review);
  }

  const hasSourceStage =
    codemod.source !== undefined ||
    codemod.imports !== undefined ||
    codemod.subpaths !== undefined;

  if (hasSourceStage && text === source && review.length === 0) {
    review.push(...unparsedLine(source, path));
  }

  return { text, review };
}

const SCRIPT_FILE = /\.[cm]?[jt]sx?$/;

/**
 * One review line when `source` is a script that does not parse, so a codemod
 * that found nothing to change is never mistaken for one that could not read
 * the file. A file with another extension (`.env`, `turbo.json`) has no tree.
 */
function unparsedLine(source: string, path: string): readonly ReviewLine[] {
  if (path !== "" && !SCRIPT_FILE.test(path)) {
    return [];
  }

  const [first] = parseSource(source).errors;

  if (first === undefined) {
    return [];
  }

  return [
    {
      line: lineColumn(source, first.labels[0]?.start ?? 0).line,
      message: `the file does not parse (${first.message}), so the codemod left it unchanged; fix it and run the codemod again.`,
    },
  ];
}
