/**
 * `codemod naming`: applies the rename table of `api/naming.json`. Exports and
 * types are renamed in imports and where they are used, `better-supabase/<x>`
 * subpaths in specifiers, and environment variables wherever a source or env
 * file names them. Renamed SQL objects of installed blocks get one hand
 * migration of `alter ... rename` statements, so no data moves.
 */

import type { Codemod } from "./codemod.ts";

import naming from "../../api/naming.json" with { type: "json" };

export type RenameKind =
  | "column"
  | "env"
  | "event"
  | "function"
  | "hint"
  | "policy"
  | "sqlFunction"
  | "subpath"
  | "table"
  | "type";

/** One row of the rename table in `api/naming.json`. */
export interface NamingRename {
  readonly from: string;
  readonly to: string;
  readonly kind: RenameKind;
  readonly since: string;
  /** The table a `column` or `policy` rename belongs to (`schema.table`). */
  readonly table?: string;
}

/** The rename table, as `naming.json` has it. */
// SAFETY: `kind` in naming.json is one of `RenameKind`, which the naming test checks.
export const NAMING_RENAMES: readonly NamingRename[] =
  naming.renames as readonly NamingRename[];

const IDENTIFIER_KINDS: ReadonlySet<RenameKind> = new Set(["function", "type"]);

function mapOf(
  renames: readonly NamingRename[],
  kind: (value: RenameKind) => boolean,
): Record<string, string> {
  return Object.fromEntries(
    renames.filter((rename) => kind(rename.kind)).map((r) => [r.from, r.to]),
  );
}

/** `text` with each environment variable name in `renames` replaced. */
export function renameEnvNames(
  text: string,
  renames: readonly NamingRename[],
): string {
  let result = text;

  for (const rename of renames) {
    if (rename.kind === "env") {
      result = result.replaceAll(
        new RegExp(`(?<![A-Za-z0-9_])${rename.from}(?![A-Za-z0-9_])`, "g"),
        rename.to,
      );
    }
  }

  return result;
}

/**
 * `text` with each quoted hint code and event name in `renames` replaced. Only
 * a whole string literal matches, so `"OLD_CODE"` changes and
 * `"LEDGER_OLD_CODE"` does not.
 */
export function renameQuotedNames(
  text: string,
  renames: readonly NamingRename[],
): string {
  let result = text;

  for (const rename of renames) {
    if (rename.kind === "hint" || rename.kind === "event") {
      result = result.replaceAll(
        new RegExp(
          `(["'\`])${rename.from.replaceAll(".", String.raw`\.`)}\\1`,
          "g",
        ),
        `$1${rename.to}$1`,
      );
    }
  }

  return result;
}

const quote = (name: string): string => `"${name.replaceAll('"', '""')}"`;

const literal = (text: string): string => `'${text.replaceAll("'", "''")}'`;

function qualifiedOf(table: string): { schema: string; name: string } {
  const [schema, name] = table.includes(".")
    ? table.split(".")
    : ["public", table];

  return { schema: schema!, name: name! };
}

/**
 * The statements that rename installed SQL objects, or `undefined` when no
 * rename applies. Each one checks that the old object exists, so an app that
 * never installed the block runs the migration unchanged.
 */
export function renameMigrationSql(
  renames: readonly NamingRename[],
): string | undefined {
  const statements = renames.flatMap((rename): string[] => {
    switch (rename.kind) {
      case "table": {
        const { schema, name } = qualifiedOf(rename.from);

        return [
          `if to_regclass(${literal(`${quote(schema)}.${quote(name)}`)}) is not null then\n    alter table ${quote(schema)}.${quote(name)} rename to ${quote(rename.to)};\n  end if;`,
        ];
      }

      case "column": {
        const { schema, name } = qualifiedOf(rename.table ?? "");

        return [
          `if exists (select 1 from information_schema.columns where table_schema = ${literal(schema)} and table_name = ${literal(name)} and column_name = ${literal(rename.from)}) then\n    alter table ${quote(schema)}.${quote(name)} rename column ${quote(rename.from)} to ${quote(rename.to)};\n  end if;`,
        ];
      }

      case "policy": {
        const { schema, name } = qualifiedOf(rename.table ?? "");

        return [
          `if exists (select 1 from pg_policies where schemaname = ${literal(schema)} and tablename = ${literal(name)} and policyname = ${literal(rename.from)}) then\n    alter policy ${quote(rename.from)} on ${quote(schema)}.${quote(name)} rename to ${quote(rename.to)};\n  end if;`,
        ];
      }

      case "sqlFunction": {
        const toSchema = rename.to.slice(0, rename.to.indexOf("."));

        return [
          `if to_regprocedure(${literal(rename.from)}) is not null then\n    alter function ${rename.from} set schema ${quote(toSchema)};\n  end if;`,
        ];
      }

      case "env":
      case "event":
      case "function":
      case "hint":
      case "subpath":
      case "type": {
        return [];
      }

      default: {
        const unknown: never = rename.kind;

        return unknown;
      }
    }
  });

  if (statements.length === 0) {
    return undefined;
  }

  return `-- better-supabase codemod naming: renames installed objects, no data moves.\n-- destructive: reviewed\ndo $$\nbegin\n  ${statements.join("\n  ")}\nend\n$$;\n`;
}

/** The `naming` codemod for `renames`, the whole table by default. */
export function namingCodemod(
  renames: readonly NamingRename[] = NAMING_RENAMES,
): Codemod {
  return {
    name: "naming",
    description:
      "Applies the renames in api/naming.json: exports, types, subpaths, environment variables and installed SQL objects",
    imports: mapOf(renames, (kind) => IDENTIFIER_KINDS.has(kind)),
    subpaths: mapOf(renames, (kind) => kind === "subpath"),
    source: (text) => ({
      text: renameQuotedNames(renameEnvNames(text, renames), renames),
      review: [],
    }),
    migration: () => renameMigrationSql(renames),
  };
}
