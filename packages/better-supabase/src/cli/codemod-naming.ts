/**
 * `codemod naming`: applies the rename table of `api/naming.json`. Exports and
 * types are renamed in imports and where they are used, `better-supabase/<x>`
 * subpaths in specifiers, and environment variables wherever a source or env
 * file names them. Renamed SQL objects of installed blocks get one hand
 * migration of `alter ... rename` statements, so no data moves.
 */

import { walk } from "oxc-walker";

import type { Rewritten } from "./codemod-arguments.ts";
import type { Codemod, MigrationContext } from "./codemod.ts";

import naming from "../../api/naming.json" with { type: "json" };
import { bsbPolicyName, getPolicies } from "../sql/index.ts";
import { renameArguments, renameBlockReferences } from "./codemod-arguments.ts";
import { renameConfigKeys } from "./codemod-config-keys.ts";
import {
  columnPins,
  pinReview,
  renameSqlColumns,
  withColumnPins,
  withHistoryPins,
} from "./codemod-naming-pins.ts";
import { rewriteSource } from "./config-document/index.ts";
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
  | "sqlFunctionName"
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
  /** The SQL module that owns a `sqlFunctionName` rename. */
  readonly module?: string;
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

const ENV_FILE_NAME = /^(?:\.env(?:\.[\w.-]+)?|turbo\.jsonc?)$/;

/** Whether `path` is an `.env*` file or `turbo.json`, which have no syntax tree. */
function isEnvFile(path: string | undefined): boolean {
  return (
    path !== undefined && ENV_FILE_NAME.test(path.split(/[/\\]/).at(-1) ?? "")
  );
}

/**
 * `text` with each environment variable name in `renames` replaced, in a file
 * that has no syntax tree (`.env*`, `turbo.json`): a whole name, not part of a
 * longer one.
 */
export function renameEnvFileNames(
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
 * Renames environment variables, hint codes and event names in TypeScript or
 * TSX through the syntax tree. An environment variable changes where code names
 * it: a `process.env` or `env` member read, a key or a binding. A hint code, an
 * event name and an environment variable changes in a string only when the
 * whole string is the name, so `"LEDGER_OLD_CODE"` stays. Comments never
 * change. A string that holds an environment variable name among other words is
 * listed for review, because only the author knows whether it is a message or a
 * lookup. A file that does not parse is listed, not skipped.
 */
export function renameNames(
  text: string,
  renames: readonly NamingRename[],
): Rewritten {
  const env = new Map(
    renames.filter((r) => r.kind === "env").map((r) => [r.from, r.to]),
  );

  const quoted = new Map(
    renames
      .filter(
        (r) =>
          r.kind === "hint" ||
          r.kind === "event" ||
          r.kind === "sqlFunctionName",
      )
      .map((r) => [r.from, r.to]),
  );

  if (env.size === 0 && quoted.size === 0) {
    return { text, review: [] };
  }

  const mentions = [...env.keys()].map(
    (name) => new RegExp(`(?<![A-Za-z0-9_])${name}(?![A-Za-z0-9_])`),
  );

  return rewriteSource(text, ({ program, text: source, edit, report }) => {
    const whole = (value: string): string | undefined =>
      env.get(value) ?? quoted.get(value);

    walk(program, {
      enter(node, parent) {
        if (node.type === "Identifier") {
          const to = env.get(node.name);

          if (to === undefined || parent === null) {
            return;
          }

          if (
            parent.type === "ImportSpecifier" ||
            parent.type === "ExportSpecifier"
          ) {
            return;
          }

          edit.overwrite(node.start, node.end, to);

          return;
        }

        if (node.type === "TemplateLiteral" && node.expressions.length === 0) {
          const [quasi] = node.quasis;

          const to =
            quasi === undefined ? undefined : quoted.get(quasi.value.raw);

          if (quasi !== undefined && to !== undefined) {
            edit.overwrite(node.start + 1, node.end - 1, to);
          }

          return;
        }

        if (node.type !== "Literal" || typeof node.value !== "string") {
          return;
        }

        if (
          parent?.type === "ImportDeclaration" ||
          parent?.type === "ExportAllDeclaration" ||
          parent?.type === "ExportNamedDeclaration"
        ) {
          return;
        }

        const to = whole(node.value);

        if (to !== undefined) {
          const mark = source[node.start];

          edit.overwrite(node.start, node.end, `${mark}${to}${mark}`);

          return;
        }

        if (mentions.some((pattern) => pattern.test(node.value))) {
          report(
            node.start,
            "This string names a renamed environment variable among other text, so the codemod left it. Update it by hand if it is a lookup.",
          );
        }
      },
    });
  });
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

  return getPolicies(projectSql).flatMap(({ policy }): string[] => {
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
 * The names of the check constraints `sql` declares with `constraint <name>
 * check`.
 */
export function appCheckNames(sql: string): Set<string> {
  return new Set(
    Array.from(
      sql.matchAll(/\bconstraint\s+(?:"([^"]+)"|([a-z_][\w$]*))\s+check\b/giu),
      (match) => match[1] ?? match[2]!.toLowerCase(),
    ),
  );
}

/**
 * One loop that gives every check constraint of the block schemas the `bsb_`
 * prefix (ADR 0273), when `projectSql` creates a table in one of them. The old
 * names are the ones Postgres chose, which the files never write, so the loop
 * reads them from the catalog.
 */
function generatedCheckRenames(
  projectSql: string | undefined,
  appChecks: ReadonlySet<string> = new Set(),
): string[] {
  if (projectSql === undefined || !/\bbetter_supabase\b/.test(projectSql)) {
    return [];
  }

  const kept =
    appChecks.size === 0
      ? ""
      : ` and k.conname <> all (array[${[...appChecks].map(literal).join(", ")}])`;

  return [
    `declare\n    c record;\n  begin\n    for c in\n      select n.nspname as schema_name, r.relname as table_name, k.conname as name\n      from pg_catalog.pg_constraint k\n        join pg_catalog.pg_class r on r.oid = k.conrelid\n        join pg_catalog.pg_namespace n on n.oid = r.relnamespace\n      where n.nspname in ('better_supabase', 'workflow') and k.contype = 'c' and k.conname !~ '^bsb_' and length(k.conname) <= 59${kept}\n    loop\n      execute format('alter table %I.%I rename constraint %I to %I', c.schema_name, c.table_name, c.name, 'bsb_' || c.name);\n    end loop;\n  end;`,
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
      (!context.configLoaded ||
        context.tenantColumns.global.has(rename.from) ||
        (rename.table !== undefined &&
          context.tenantColumns.byTable.get(rename.table)?.has(rename.from) ===
            true))
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
      case "sqlFunctionName":
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
    ...generatedCheckRenames(projectSql, context?.appChecks),
  );

  if (statements.length === 0) {
    return undefined;
  }

  return `-- better-supabase codemod naming: renames installed objects, no data moves.\n-- destructive: reviewed\ndo $$\nbegin\n  ${statements.join("\n  ")}\nend\n$$;\n`;
}

/**
 * Rewrites a call to a renamed SQL function in the app's own SQL, where the
 * name is qualified with the module schema (X * bare name stays: it may be the
 * app's own function. The module's function is dropped and created again by the
 * next schema diff, never renamed, because its body qualifies its arguments
 * with the function name.
 */
export function renameSqlFunctions(
  text: string,
  renames: readonly NamingRename[],
): string {
  const functions = new Map(
    renames
      .filter((rename) => rename.kind === "sqlFunctionName")
      .map((rename) => [rename.from, rename.to]),
  );

  if (functions.size === 0) {
    return text;
  }

  const names = [...functions.keys()].toSorted((a, b) => b.length - a.length);

  return text.replaceAll(
    new RegExp(
      `(\\bbetter_supabase"?\\.)(["]?)(${names.join("|")})\\2(?![\\w])`,
      "g",
    ),
    (_match, schema: string, mark: string, name: string) =>
      `${schema}${mark}${functions.get(name) ?? name}${mark}`,
  );
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
    source: (text, path) => {
      if (isEnvFile(path)) {
        return { text: renameEnvFileNames(text, renames), review: [] };
      }

      const keys = renameConfigKeys(text, renames);
      const names = renameNames(keys.text, renames);
      const named = renameArguments(names.text, renames);

      const references = renameBlockReferences(named.text, renames);

      // Both rewrites read the same file, so a file that does not parse is
      // listed once.
      const seen = new Set<string>();

      const review = [
        ...keys.review,
        ...names.review,
        ...named.review,
        ...references.review,
      ].filter((line) => {
        const key = `${String(line.line)}:${line.message}`;

        return seen.has(key) ? false : Boolean(seen.add(key));
      });

      return { text: references.text, review };
    },
    files: async (project) => {
      if (project.configLoaded === false) {
        return (_path, text) => ({ text, review: [] });
      }

      let report: ReturnType<typeof columnPins> = {
        pins: [],
        history: [],
        review: [],
      };

      try {
        const own = await ownLayout(project.config);

        report = columnPins(
          project.config,
          renames,
          own.ownTables ?? {},
          own.ownColumns ?? {},
        );
      } catch {
        // Without the project's tables nothing says which names the app keeps.
      }

      return (path, text) => {
        const refused = report.review.map((message) => ({
          line: 1,
          message,
          errorCode: "config_invalid" as const,
        }));

        if (
          (report.pins.length === 0 && report.history.length === 0) ||
          path !== project.configFile
        ) {
          return { text, review: refused };
        }

        const history = withHistoryPins(text, report.history);
        const pinned = withColumnPins(history.text, report.pins);

        return {
          text: pinned.text,
          review: [
            ...refused,
            ...pinned.missed.map((pin) => ({
              line: 1,
              message: pinReview(pin),
            })),
            ...history.missed.map((pin) => ({
              line: 1,
              message: `Add \`actor: "${pin.actor}"\` to blocks.${pin.block}.options.machines.${pin.machine}.history. The table still has that column, and the history default is actor_id.`,
            })),
          ],
        };
      };
    },
    sql: async (text, context) =>
      renameSqlFunctions(
        context.configLoaded
          ? await renameSqlColumns(text, renames, context.tenantColumns)
          : text,
        renames,
      ),
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
