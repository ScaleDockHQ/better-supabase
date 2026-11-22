import { dirname, posix, resolve } from "node:path";

import type { BlockSqlLayout } from "../sql/index.ts";
import type { Codemod, CodemodProject } from "./codemod.ts";
import type { PlannedFile } from "./core/files.ts";

import {
  LEGACY_OPTION,
  legacyOptionTarget,
  moduleContext,
} from "../sql/index.ts";
import { ConfigDocument } from "./config-document/index.ts";
import { CliError } from "./core/errors.ts";
import { declarationsOfText, primeSchemaFacts } from "./sql-facts.ts";
import { layoutFor } from "./sql/providers.ts";

/** One `extraColumns` option of a block in the config. */
export interface ExtraColumnsOption {
  readonly block: string;
  readonly key: string;
  readonly columns: readonly (readonly [string, string])[];
}

/** What the codemod reads from the project. */
export interface ExtraColumnsInput {
  /** `blocks.<name>.options`, resolved, by block name. */
  readonly options: Readonly<Record<string, Readonly<Record<string, unknown>>>>;
  /** The `schema.table` a block's legacy option added its columns to. */
  readonly tableOf: (block: string, key: string) => string | undefined;
  /** The project's own SQL files (not the ones a block wrote). */
  readonly sql: readonly { readonly path: string; readonly text: string }[];
  /** The folder app schema files live in, for a new `<table>.ext.sql`. */
  readonly schemasDir: string;
  /** The config file and its text. */
  readonly config?: { readonly path: string; readonly text: string };
}

/** The `extraColumns` options a config sets, with their columns. */
export function extraColumnsOptions(
  options: ExtraColumnsInput["options"],
): ExtraColumnsOption[] {
  return Object.entries(options).flatMap(([block, own]) =>
    Object.entries(own)
      .filter(
        ([key, value]) =>
          LEGACY_OPTION.test(key) &&
          typeof value === "object" &&
          value !== null &&
          !Array.isArray(value),
      )
      .map(([key, value]) => ({
        block,
        key,
        // SAFETY: the filter above keeps only non-array objects.
        columns: Object.entries(value as Record<string, unknown>).flatMap(
          ([name, type]): [string, string][] =>
            typeof type === "string" ? [[name, type]] : [],
        ),
      })),
  );
}

const quoted = (name: string): string => name.replaceAll('"', '""');

/** Whether `text` has an `alter table` statement for `schema.table`. */
function altersTable(text: string, table: string): boolean {
  const schema = table.slice(0, table.indexOf("."));
  const name = table.slice(table.indexOf(".") + 1);

  const escape = (value: string): string =>
    value.replaceAll(/[.*+?^${}()|[\]\\]/g, String.raw`\$&`);

  return new RegExp(
    String.raw`\balter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?(?:"?${escape(schema)}"?\s*\.\s*)"?${escape(name)}"?(?![\w$])`,
    "i",
  ).test(text.replaceAll(/--[^\n]*/g, ""));
}

/** `alter table ... add column` for `columns`, as one statement. */
function addColumns(
  table: string,
  columns: readonly (readonly [string, string])[],
): string {
  const [schema, name] = table.split(".");

  return `alter table "${quoted(schema!)}"."${quoted(name!)}"\n${columns
    .map(([column, type]) => `  add column "${quoted(column)}" ${type}`)
    .join(",\n")};\n`;
}

/**
 * `text` with the tag `line` (`@bsb fields a, b`) in the comment of a table the
 * app creates: an existing `comment on table` gets the line, a table without
 * one gets the statement.
 */
export function withTableTag(
  text: string,
  table: string,
  line: string,
): string {
  const [schema, name] = table.split(".");

  const comment = new RegExp(
    String.raw`(comment\s+on\s+table\s+(?:"?${schema}"?\s*\.\s*)?"?${name}"?\s+is\s+')((?:[^']|'')*)(')`,
    "i",
  );

  const escaped = line.replaceAll("'", "''");

  if (comment.test(text)) {
    // One `@bsb` starts the tag block and `;` separates the tags in it, so a
    // second `@bsb` would read as a word of the tag before it.
    return text.replace(
      comment,
      (_all, head: string, body: string, tail: string) =>
        /(^|\s)@bsb(?:\s|$)/u.test(body)
          ? `${head}${body.trimEnd().replace(/;$/u, "")}; ${escaped.replace(/^@bsb\s+/u, "")}${tail}`
          : `${head}${body === "" ? "" : `${body}\n`}${escaped}${tail}`,
    );
  }

  return `${text.replace(/\n*$/, "\n")}\ncomment on table "${quoted(schema!)}"."${quoted(name!)}" is '${escaped}';\n`;
}

function taggedFields(
  text: string,
  table: string,
  columns: readonly string[],
): string {
  return withTableTag(text, table, `@bsb fields ${columns.join(", ")}`);
}

/**
 * `text` without the `options.<key>` entries named in `keys`, under each block
 * of `blocks` and `instances`, with the comma, the line and the comments each
 * leaves behind. A key in a string or a comment stays, and an option the file
 * builds elsewhere (a spread of an import, a method) stays with a review line.
 */
export function withoutOptionKeys(
  text: string,
  keys: ReadonlySet<string>,
): { readonly text: string; readonly review: readonly string[] } {
  const document = ConfigDocument.parse(text);

  for (const root of ["blocks", "instances"]) {
    for (const name of document.keys([root]) ?? []) {
      for (const key of keys) {
        document.remove([root, name, "options", key]);
      }
    }
  }

  return { text: document.text, review: document.review };
}

/**
 * The files that move the config's `extraColumns` into the app's schema files:
 * each column is added where an app file already alters the table, or in
 * `<table>.ext.sql`, and the options leave the config.
 */
export function extraColumnsFiles(input: ExtraColumnsInput): {
  readonly files: readonly PlannedFile[];
  readonly review: readonly { readonly message: string }[];
} {
  const options = extraColumnsOptions(input.options);

  const byTable = new Map<string, [string, string][]>();
  const review: { message: string }[] = [];

  for (const option of options) {
    for (const [column, type] of option.columns) {
      const table = input.tableOf(option.block, option.key);

      if (table === undefined) {
        review.push({
          message: `blocks.${option.block}.options.${option.key}.${column}: this release has no table for the option, so it stays in the config.`,
        });
        continue;
      }

      byTable.set(table, [...(byTable.get(table) ?? []), [column, type]]);
    }
  }

  const files: PlannedFile[] = [];
  const edited = new Map<string, string>();

  for (const [table, columns] of byTable) {
    // A migration that already ran is never edited.
    const creator = input.sql.find(
      (file) =>
        !/[\\/]migrations[\\/]/.test(file.path) &&
        declarationsOfText(file.text).creates.some(
          (each) => each.table === table,
        ),
    );

    if (creator !== undefined) {
      const current = edited.get(creator.path) ?? creator.text;

      edited.set(
        creator.path,
        taggedFields(
          current,
          table,
          columns.map(([column]) => column),
        ),
      );
      continue;
    }

    const owner = input.sql.find(
      (file) =>
        !/[\\/]migrations[\\/]/.test(file.path) &&
        altersTable(file.text, table),
    );

    if (owner === undefined) {
      const name = table.split(".").at(-1)!;

      files.push({
        path: posix.join(input.schemasDir, `${name}.ext.sql`),
        contents: `-- App-owned extension of ${table}: columns the block reads and writes as fields.\n-- better-supabase upgrade never rewrites this file.\n\n${addColumns(table, columns)}`,
        policy: "create",
      });
      continue;
    }

    edited.set(
      owner.path,
      `${(edited.get(owner.path) ?? owner.text).replace(/\n*$/, "\n")}\n${addColumns(table, columns)}`,
    );
  }

  for (const [path, contents] of edited) {
    files.push({ path, contents, policy: "edit" });
  }

  if (input.config !== undefined && options.length > 0) {
    const kept = new Set(
      review
        .map(
          (entry) =>
            /^blocks\.[^.]+\.options\.([^.]+)\./.exec(entry.message)?.[1],
        )
        .filter((key) => key !== undefined),
    );

    const keys = new Set(
      options.map((option) => option.key).filter((key) => !kept.has(key)),
    );

    const edit = withoutOptionKeys(input.config.text, keys);
    const left = ConfigDocument.parse(edit.text);

    review.push(...edit.review.map((message) => ({ message })));

    for (const option of options) {
      const own = left.valueText(["blocks", option.block, "options"]);

      if (
        keys.has(option.key) &&
        (left.has(["blocks", option.block, "options", option.key]) ||
          (own !== undefined && !own.startsWith("{"))) &&
        !edit.review.some((line) => line.includes(option.key))
      ) {
        review.push({
          message: `blocks.${option.block}.options.${option.key}: the codemod could not remove it from the config file (it may come from another file); remove it by hand.`,
        });
      }
    }

    if (edit.text !== input.config.text) {
      files.push({
        path: input.config.path,
        contents: edit.text,
        policy: "edit",
      });
    }
  }

  return { files, review };
}

/** The folder app schema files live in, given where the block files go. */
export function schemasDirOf(sqlDir: string): string {
  const dir = sqlDir.replace(/\/$/, "");

  return posix.basename(dir).startsWith("_") ? dirname(dir) : dir;
}

/** The `extra-columns` codemod: move `extraColumns` options into app SQL files. */
export function extraColumnsCodemod(): Codemod {
  return {
    name: "extra-columns",
    description:
      "Move blocks.<name>.options.extraColumns into the app's schema files and drop the options",
    project: async (project: CodemodProject) => {
      const { config } = project;

      await primeSchemaFacts(project.sql, config.root);

      const options = Object.fromEntries(
        Object.entries(config.blocks).map(([name, block]) => [
          name,
          block?.options ?? {},
        ]),
      );

      if (extraColumnsOptions(options).length === 0) {
        return { files: [], review: [] };
      }

      const clean = <T extends { readonly options?: object | undefined }>(
        block: T | undefined,
      ): T | undefined =>
        block?.options === undefined
          ? block
          : {
              ...block,
              options: Object.fromEntries(
                Object.entries(block.options).filter(
                  ([key]) => !LEGACY_OPTION.test(key),
                ),
              ),
            };

      const cleaned = {
        ...config,
        blocks: Object.fromEntries(
          Object.entries(config.blocks).map(([name, block]) => [
            name,
            clean(block),
          ]),
        ),
        instances: Object.fromEntries(
          Object.entries(config.instances).map(([name, instance]) => [
            name,
            { ...instance, config: clean(instance.config) ?? instance.config },
          ]),
        ),
      };

      // The codemod only needs the table names, so a project whose
      // authorization provider doesn't load yet still gets its columns moved.
      let layout: BlockSqlLayout = {
        modules: cleaned.blocks,
        instances: cleaned.instances,
        subjects: cleaned.subjects,
      };

      try {
        layout = await layoutFor(cleaned, {}, config.blockNames);
      } catch {
        // The codemod only needs the table names, so a project whose
        // authorization provider doesn't load yet still gets its columns moved.
      }

      const modules = layout.modules;

      const tableOf = (block: string, key: string): string | undefined => {
        try {
          const ctx = moduleContext(
            block,
            { ...layout, ...(modules === undefined ? {} : { modules }) },
            config.blockNames,
          );

          return legacyOptionTarget(
            block,
            key,
            config.blocks[block]?.tables,
            (logical) => ctx.tableName(logical),
          )?.table;
        } catch (error) {
          if (error instanceof CliError) {
            throw error;
          }

          const message =
            error instanceof Error ? error.message : String(error);

          throw new CliError("config_invalid", message, { cause: error });
        }
      };

      return extraColumnsFiles({
        options,
        tableOf,
        sql: project.sql,
        schemasDir: resolve(config.root, schemasDirOf(config.sql.dir)),
        ...(project.configFile === undefined
          ? {}
          : {
              config: {
                path: project.configFile,
                text: project.configText ?? "",
              },
            }),
      });
    },
  };
}
