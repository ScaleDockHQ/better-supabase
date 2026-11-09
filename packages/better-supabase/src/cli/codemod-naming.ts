/**
 * `codemod naming`: applies the rename table of `api/naming.json`. Exports and
 * types are renamed in imports and where they are used, `better-supabase/<x>`
 * subpaths in specifiers, and environment variables wherever a source or env
 * file names them. Renamed SQL objects of installed blocks get one hand
 * migration of `alter ... rename` statements, so no data moves.
 */

import type { Codemod, MigrationContext } from "./codemod.ts";

import naming from "../../api/naming.json" with { type: "json" };
import { bsbPolicyName, readPolicies } from "../sql/index.ts";
import { renameArguments, renameBlockReferences } from "./codemod-arguments.ts";
import { renameConfigKeys } from "./codemod-config-keys.ts";
import {
  columnPins,
  renameSqlColumns,
  withColumnPins,
} from "./codemod-naming-pins.ts";
import { ownLayout } from "./sql-layout.ts";

export type RenameKind =
  | "argument"
  | "column"
  | "configKey"
  | "constraint"
  | "env"
  | "event"
  | "function"
  | "hint"
  | "index"
  | "policy"
  | "sqlFunction"
  | "subpath"
  | "table"
  | "trigger"
  | "type";

/** One row of the rename table in `api/naming.json`. */
export interface NamingRename {
  readonly from: string;
  readonly to: string;
  readonly kind: RenameKind;
  readonly since: string;
  /**
   * The table a `column`, `constraint`, `policy`, `trigger` or `index` rename
   * belongs to (`schema.table`).
   */
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
 * The `alter policy` statements for the policies of `better_supabase` tables
 * that `projectSql` creates without the `bsb_` prefix (ADR 0272). They follow
 * from a rule, not from rows of the rename table, because a module writes
 * hundreds of them.
 */
function generatedPolicyRenames(projectSql: string | undefined): string[] {
  if (projectSql === undefined) {
    return [];
  }

  const seen = new Set<string>();

  return readPolicies(projectSql).flatMap(({ policy }): string[] => {
    const { schema, name } = qualifiedOf(policy.table);
    const to = bsbPolicyName(policy.name);
    const key = `${policy.table}\u0000${policy.name}`;

    if (schema !== "better_supabase" || to === policy.name || seen.has(key)) {
      return [];
    }

    seen.add(key);

    return [
      `if exists (select 1 from pg_policies where schemaname = ${literal(schema)} and tablename = ${literal(name)} and policyname = ${literal(policy.name)}) then\n    alter policy ${quote(policy.name)} on ${quote(schema)}.${quote(name)} rename to ${quote(to)};\n  end if;`,
    ];
  });
}

/**
 * One loop that gives every check constraint of the block schemas the `bsb_`
 * prefix (ADR 0273), when `projectSql` creates a table in one of them. The old
 * names are the ones Postgres chose, which the files never write, so the loop
 * reads them from the catalog.
 */
function generatedCheckRenames(projectSql: string | undefined): string[] {
  if (projectSql === undefined || !/\bbetter_supabase\b/.test(projectSql)) {
    return [];
  }

  return [
    `declare\n    c record;\n  begin\n    for c in\n      select n.nspname as schema_name, r.relname as table_name, k.conname as name\n      from pg_catalog.pg_constraint k\n        join pg_catalog.pg_class r on r.oid = k.conrelid\n        join pg_catalog.pg_namespace n on n.oid = r.relnamespace\n      where n.nspname in ('better_supabase', 'workflow') and k.contype = 'c' and k.conname !~ '^bsb_' and length(k.conname) <= 59\n    loop\n      execute format('alter table %I.%I rename constraint %I to %I', c.schema_name, c.table_name, c.name, 'bsb_' || c.name);\n    end loop;\n  end;`,
  ];
}

/**
 * The constraints, indexes and policies of a renamed table whose name starts
 * with the table's old name (after an optional `bsb_`): they take the new name,
 * which a table rename leaves alone. Run after the table rename, as a nested
 * block.
 */
function dependentRenames(schema: string, from: string, to: string): string {
  const table = literal(`${quote(schema)}.${quote(to)}`);
  const swap = `regexp_replace(x.name, '^(bsb_)?' || ${literal(from)}, '\\1' || ${literal(to)})`;

  return `    declare
      x record;
    begin
      for x in
        select 'constraint' as kind, k.conname::text as name from pg_catalog.pg_constraint k where k.conrelid = ${table}::regclass
        union all
        select 'index', i.relname::text from pg_catalog.pg_index ix join pg_catalog.pg_class i on i.oid = ix.indexrelid
          where ix.indrelid = ${table}::regclass and not exists (select 1 from pg_catalog.pg_constraint k where k.conindid = i.oid)
        union all
        select 'policy', p.polname::text from pg_catalog.pg_policy p where p.polrelid = ${table}::regclass
        order by 1 desc, 2
      loop
        if x.name ~ ('^(bsb_)?' || ${literal(from)} || '(_|$)') then
          execute case x.kind
            when 'constraint' then format('alter table %s rename constraint %I to %I', ${table}, x.name, ${swap})
            when 'index' then format('alter index %I.%I rename to %I', ${literal(schema)}, x.name, ${swap})
            else format('alter policy %I on %s rename to %I', x.name, ${table}, ${swap})
          end;
        end if;
      end loop;
    end;
`;
}

/**
 * The statements that rename installed SQL objects, or `undefined` when no
 * rename applies. Each one checks that the old object exists, so an app that
 * never installed the block runs the migration unchanged. With `projectSql`, a
 * renamed SQL function the project's files never name is left out.
 */
export function renameMigrationSql(
  renames: readonly NamingRename[],
  projectSql?: string,
  context?: MigrationContext,
): string | undefined {
  const statements = renames.flatMap((rename): string[] => {
    // A column the config names as the tenant column keeps its name, and
    // without the config nothing says which columns those are: renaming one
    // makes the schema diff drop it and add an empty one.
    if (
      rename.kind === "column" &&
      context !== undefined &&
      (!context.configLoaded || context.tenantColumns.has(rename.from))
    ) {
      return [];
    }

    switch (rename.kind) {
      case "table": {
        const { schema, name } = qualifiedOf(rename.from);

        if (projectSql !== undefined && !projectSql.includes(name)) {
          return [];
        }

        return [
          `if to_regclass(${literal(`${quote(schema)}.${quote(name)}`)}) is not null then\n    alter table ${quote(schema)}.${quote(name)} rename to ${quote(rename.to)};\n${dependentRenames(schema, name, rename.to)}  end if;`,
        ];
      }

      case "column": {
        if (projectSql !== undefined && !projectSql.includes(rename.from)) {
          return [];
        }

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

      case "constraint": {
        if (projectSql !== undefined && !projectSql.includes(rename.from)) {
          return [];
        }

        const { schema, name } = qualifiedOf(rename.table ?? "");

        return [
          `if exists (select 1 from pg_constraint k join pg_class c on c.oid = k.conrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname = ${literal(schema)} and c.relname = ${literal(name)} and k.conname = ${literal(rename.from)}) then\n    alter table ${quote(schema)}.${quote(name)} rename constraint ${quote(rename.from)} to ${quote(rename.to)};\n  end if;`,
        ];
      }

      case "trigger": {
        if (projectSql !== undefined && !projectSql.includes(rename.from)) {
          return [];
        }

        const { schema, name } = qualifiedOf(rename.table ?? "");

        return [
          `if exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname = ${literal(schema)} and c.relname = ${literal(name)} and t.tgname = ${literal(rename.from)} and not t.tgisinternal) then\n    alter trigger ${quote(rename.from)} on ${quote(schema)}.${quote(name)} rename to ${quote(rename.to)};\n  end if;`,
        ];
      }

      case "index": {
        if (projectSql !== undefined && !projectSql.includes(rename.from)) {
          return [];
        }

        const { schema } = qualifiedOf(rename.table ?? "");

        return [
          `if to_regclass(${literal(`${quote(schema)}.${quote(rename.from)}`)}) is not null then\n    alter index ${quote(schema)}.${quote(rename.from)} rename to ${quote(rename.to)};\n  end if;`,
        ];
      }

      case "sqlFunction": {
        // A function the project's SQL never names has nothing to move.
        const name = rename.from.slice(0, rename.from.indexOf("("));

        if (projectSql !== undefined && !projectSql.includes(name)) {
          return [];
        }

        const toSchema = rename.to.slice(0, rename.to.indexOf("."));

        return [
          `if to_regprocedure(${literal(rename.from)}) is not null then\n    alter function ${rename.from} set schema ${quote(toSchema)};\n  end if;`,
        ];
      }

      case "argument":
      case "configKey":
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

  statements.push(
    ...generatedPolicyRenames(projectSql),
    ...generatedCheckRenames(projectSql),
  );

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
    source: (text) => {
      const keys = renameConfigKeys(text, renames);

      return {
        text: renameBlockReferences(
          renameArguments(
            renameQuotedNames(renameEnvNames(keys.text, renames), renames),
            renames,
          ),
          renames,
        ),
        review: keys.review,
      };
    },
    files: async (project) => {
      if (project.configLoaded === false) {
        return (_path, text) => ({ text, review: [] });
      }

      let pins: ReturnType<typeof columnPins> = [];

      try {
        const own = await ownLayout(project.config);

        pins = columnPins(
          project.config,
          renames,
          own.ownTables ?? {},
          own.ownColumns ?? {},
        );
      } catch {
        // Without the project's tables nothing says which names the app keeps.
      }

      return (path, text) => {
        if (pins.length === 0 || path !== project.configFile) {
          return { text, review: [] };
        }

        const pinned = withColumnPins(text, pins);

        return {
          text: pinned.text,
          review: pinned.missed.map((pin) => ({
            line: 1,
            message: `Your table keeps "${pin.name}", which 0.58 names differently. Add \`columns: { ${pin.table}: { ${pin.column}: "${pin.name}" } }\` to blocks.${pin.block}.`,
          })),
        };
      };
    },
    sql: (text, context) =>
      context.configLoaded
        ? renameSqlColumns(text, renames, context.tenantColumns)
        : text,
    migration: (sql, context) => {
      const migration = renameMigrationSql(renames, sql, context);
      const review: string[] = [];

      if (
        !context.configLoaded &&
        renames.some((rename) => rename.kind === "column")
      ) {
        review.push(
          "The config did not load, so the column renames were left out: a tenant column named in the config must keep its name. Fix the config and run `better-supabase codemod naming` again.",
        );
      }

      return { ...(migration === undefined ? {} : { sql: migration }), review };
    },
  };
}
