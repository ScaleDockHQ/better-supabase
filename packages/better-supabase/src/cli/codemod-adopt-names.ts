import type { ScanToken } from "@supabase/pg-parser";

import { readdir } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../config/index.ts";
import type { Codemod, CodemodProject } from "./codemod.ts";
import type { PlannedFile } from "./core/files.ts";

import { SQL_MODULES } from "../sql/index.ts";
import { withoutConfigPaths } from "./codemod-prune.ts";
import { scanSql } from "./schema-reader/index.ts";
import { migrationsDir } from "./sql-layout.ts";
import { migrationFile } from "./sql/migration-names.ts";

/** The names one table goes by in the app and in the block (ADR 1190). */
export interface NamePlan {
  readonly from: { readonly schema: string; readonly name: string };
  readonly to: { readonly schema: string; readonly name: string };
  /** App column to the block's column. */
  readonly columns: ReadonlyMap<string, string>;
}

const plain = (name: string): string =>
  /^[a-z_][a-z0-9_]*$/u.test(name) ? name : `"${name.replaceAll('"', '""')}"`;

const unquoted = (token: ScanToken): string =>
  token.text.startsWith('"')
    ? token.text.slice(1, -1).replaceAll('""', '"')
    : token.text.toLowerCase();

const isName = (token: ScanToken | undefined, name: string): boolean =>
  token?.kind === "IDENT" && unquoted(token) === name;

const DOT = "ASCII_46";

/** Keywords after which an unqualified table name can stand. */
const TABLE_AFTER: ReadonlySet<string> = new Set([
  "FROM",
  "JOIN",
  "TABLE",
  "INTO",
  "UPDATE",
  "ONLY",
  "REFERENCES",
  "ON",
]);

interface Edit {
  readonly start: number;
  readonly end: number;
  readonly text: string;
}

/**
 * `text` with the table and its columns renamed in each statement that names
 * the table. A string, a comment and a statement that never names the table
 * stay.
 */
export function renameNames(
  text: string,
  tokens: readonly ScanToken[],
  plan: NamePlan,
): { readonly text: string; readonly statements: number } {
  const code = tokens.filter(
    (token) => token.kind !== "SQL_COMMENT" && token.kind !== "C_COMMENT",
  );

  const edits: Edit[] = [];
  let statements = 0;
  let first = 0;

  const sameSchema = plan.from.schema === plan.to.schema;

  const target = (qualified: boolean): string =>
    qualified || !sameSchema
      ? `${plain(plan.to.schema)}.${plain(plan.to.name)}`
      : plain(plan.to.name);

  for (let at = 0; at <= code.length; at += 1) {
    if (at < code.length && code[at]?.kind !== "ASCII_59") {
      continue;
    }

    const statement = code.slice(first, at);
    const tableEdits: Edit[] = [];

    for (const [index, token] of statement.entries()) {
      if (!isName(token, plan.from.name)) {
        continue;
      }

      const dot = statement[index - 1];
      const schema = statement[index - 2];

      if (dot?.kind === DOT && isName(schema, plan.from.schema)) {
        tableEdits.push({
          start: schema!.start,
          end: token.end,
          text: target(true),
        });

        continue;
      }

      const previous = statement[index - 1];
      const next = statement[index + 1];

      if (
        plan.from.schema === "public" &&
        previous !== undefined &&
        previous.kind !== DOT &&
        (TABLE_AFTER.has(previous.kind) ||
          (previous.kind === "COLUMN" && next?.kind === DOT))
      ) {
        tableEdits.push({
          start: token.start,
          end: token.end,
          text: target(false),
        });
      }
    }

    if (tableEdits.length > 0) {
      statements += 1;
      edits.push(...tableEdits);

      for (const token of statement) {
        const renamed =
          token.kind === "IDENT"
            ? plan.columns.get(unquoted(token))
            : undefined;

        if (
          renamed !== undefined &&
          !tableEdits.some(
            (edit) => token.start >= edit.start && token.end <= edit.end,
          )
        ) {
          edits.push({
            start: token.start,
            end: token.end,
            text: token.text.startsWith('"')
              ? `"${renamed.replaceAll('"', '""')}"`
              : plain(renamed),
          });
        }
      }
    }

    first = at + 1;
  }

  const bytes = Buffer.from(text, "utf-8");
  let out = "";
  let cursor = 0;

  for (const edit of edits.toSorted((a, b) => a.start - b.start)) {
    out += bytes.toString("utf-8", cursor, edit.start) + edit.text;
    cursor = edit.end;
  }

  return { text: out + bytes.toString("utf-8", cursor), statements };
}

/**
 * The statements of the hand-written migration that gives the table the block's
 * names.
 */
export function renameMigration(plan: NamePlan): string {
  const old = `${plain(plan.from.schema)}.${plain(plan.from.name)}`;
  const lines: string[] = [];

  if (plan.from.name !== plan.to.name) {
    lines.push(`alter table ${old} rename to ${plain(plan.to.name)};`);
  }

  const renamed = `${plain(plan.from.schema)}.${plain(plan.to.name)}`;

  if (plan.from.schema !== plan.to.schema) {
    lines.push(`alter table ${renamed} set schema ${plain(plan.to.schema)};`);
  }

  const now = `${plain(plan.to.schema)}.${plain(plan.to.name)}`;

  for (const [from, to] of plan.columns) {
    lines.push(
      `alter table ${now} rename column ${plain(from)} to ${plain(to)};`,
    );
  }

  return lines.length === 0
    ? ""
    : `-- better-supabase codemod adopt-names: ${plan.from.schema}.${plan.from.name} takes the block's names.\n${lines.join("\n")}\n`;
}

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

interface Resolved {
  readonly plan: NamePlan;
  readonly block: string;
  readonly logical: string;
  readonly logicalColumns: readonly string[];
  readonly hasValues: boolean;
}

/**
 * The names `blocks.<block>.tables.<logical>` and `columns.<logical>` give, or
 * why not.
 */
export function planOf(
  config: ResolvedConfig,
  target: string,
): Resolved | string {
  const [block, logical, ...extra] = target.split(".");

  if (block === undefined || logical === undefined || extra.length > 0) {
    return `Name the table as <block>.<table>, such as memberships.memberships (got "${target}").`;
  }

  const entry = config.blocks[block];
  const module = config.instances[block]?.block ?? block;
  const spec = SQL_MODULES[module]?.names?.tables[logical];

  if (entry === undefined || spec === undefined) {
    return `${target} is not a table of an installed block.`;
  }

  const schema =
    entry.schema ?? config.sql.blockDefaults?.schema ?? "better_supabase";

  const mapped = entry.tables?.[logical];

  if (typeof mapped !== "string") {
    return `blocks.${block}.tables.${logical} is not set, so the table already has the block's name.`;
  }

  const parts = mapped.includes(".") ? mapped.split(".") : [schema, mapped];
  const fromSchema = parts[0] ?? schema;
  const fromName = parts[1] ?? mapped;

  if (fromSchema !== schema) {
    return `The table is in ${fromSchema} and the block's schema is ${schema}. Set blocks.${block}.schema to "${fromSchema}" first (a block-level schema replaces the entries that name it), then run this again.`;
  }

  const columns = new Map<string, string>();
  const names: string[] = [];
  const mappedColumns = entry.columns?.[logical];

  for (const [column, value] of Object.entries(mappedColumns ?? {})) {
    const appName =
      typeof value === "string"
        ? value
        : isRecord(value)
          ? value.column
          : undefined;

    const own = spec.columns[column];

    if (typeof appName === "string" && own !== undefined) {
      names.push(column);

      if (appName !== own) {
        columns.set(appName, own);
      }
    }
  }

  return {
    block,
    logical,
    logicalColumns: names,
    hasValues: entry.values?.[logical] !== undefined,
    plan: {
      from: { schema: fromSchema, name: fromName },
      to: { schema, name: spec.name },
      columns,
    },
  };
}

const sourceFile = (path: string): boolean =>
  !/[\\/]migrations[\\/]/.test(path) &&
  !/(?:^|[\\/])900_better_supabase_/.test(path);

/**
 * The `adopt-names` codemod (ADR 1190): one table per run gets the block's
 * names. It writes a hand migration with the renames, rewrites the app's schema
 * files, removes the `tables` and `columns` entries and lists the types that
 * change. `values` entries stay: a stored label needs a data migration.
 */
export function adoptNamesCodemod(): Codemod {
  return {
    name: "adopt-names",
    description:
      "Rename one table to the block's names (--table <block>.<table>), with a migration",
    project: async (project: CodemodProject) => {
      const { config } = project;

      const resolved =
        project.table === undefined
          ? "Pass --table <block>.<table>. Each run renames one table."
          : planOf(config, project.table);

      if (typeof resolved === "string") {
        return { files: [], review: [{ message: resolved }] };
      }

      const { plan } = resolved;
      const files: PlannedFile[] = [];
      const review: { message: string }[] = [];

      for (const file of project.sql.filter((each) => sourceFile(each.path))) {
        const rewritten = renameNames(
          file.text,
          await scanSql(file.text),
          plan,
        );

        if (rewritten.text !== file.text) {
          files.push({
            path: file.path,
            contents: rewritten.text,
            policy: "edit",
          });
          review.push({
            message: `${file.path}: renamed in ${String(rewritten.statements)} statement(s). Check a query that reads the table through an alias or a bare column.`,
          });
        }
      }

      if (
        project.configFile !== undefined &&
        project.configText !== undefined
      ) {
        const base = `blocks.${resolved.block}`;

        const edited = withoutConfigPaths(
          project.configText,
          [
            `${base}.tables.${resolved.logical}`,
            `${base}.columns.${resolved.logical}`,
          ],
          { symbols: project.symbols, configFile: project.configFile },
        );

        review.push(...edited.review.map((message) => ({ message })));
        files.push(
          { path: project.configFile, contents: edited.text, policy: "edit" },
          ...edited.others.map(({ file, text }): PlannedFile => ({
            path: file,
            contents: text,
            policy: "edit",
          })),
        );
      }

      const sql = renameMigration(plan);

      if (sql !== "") {
        const dir = resolve(config.root, migrationsDir(config));
        const existing: string[] = await readdir(dir).catch(() => []);

        files.push({
          path: resolve(
            dir,
            (
              await migrationFile(
                existing,
                new Date(),
                "_better_supabase_adopt_names.sql",
                sql,
              )
            ).name,
          ),
          contents: sql,
          policy: "create",
        });
      }

      const changed = [
        ...(plan.from.name === plan.to.name &&
        plan.from.schema === plan.to.schema
          ? []
          : [
              `${plan.from.schema}.${plan.from.name} is now ${plan.to.schema}.${plan.to.name}`,
            ]),
        ...[...plan.columns].map(([from, to]) => `column ${from} is now ${to}`),
      ];

      review.push({
        message: `Types that change in database.types.ts and the generated client: ${changed.join("; ")}. Run better-supabase gen, then fix the code that names them.`,
      });

      if (resolved.hasValues) {
        review.push({
          message: `blocks.${resolved.block}.values.${resolved.logical} stays: the stored labels need a data migration, not a rename.`,
        });
      }

      return { files, review };
    },
  };
}
