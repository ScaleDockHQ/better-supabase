import { dirname, posix, resolve } from "node:path";

import type { BlockSqlLayout } from "../sql/index.ts";
import type { Codemod, CodemodProject } from "./codemod.ts";
import type { PlannedFile } from "./core/files.ts";

import {
  LEGACY_OPTION,
  legacyOptionTarget,
  moduleContext,
  parseDeclared,
} from "../sql/index.ts";
import { codeRanges } from "./code-ranges.ts";
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
 * `text` with `columns` listed as `@bsb fields` in the comment of a table the
 * app creates: an existing `comment on table` gets the line, a table without
 * one gets the statement.
 */
function taggedFields(
  text: string,
  table: string,
  columns: readonly string[],
): string {
  const line = `@bsb fields ${columns.join(", ")}`;
  const [schema, name] = table.split(".");

  const comment = new RegExp(
    String.raw`(comment\s+on\s+table\s+(?:"?${schema}"?\s*\.\s*)?"?${name}"?\s+is\s+')((?:[^']|'')*)(')`,
    "i",
  );

  if (comment.test(text)) {
    return text.replace(
      comment,
      (_all, head: string, body: string, tail: string) =>
        `${head}${body === "" ? "" : `${body}\n`}${line}${tail}`,
    );
  }

  return `${text.replace(/\n*$/, "\n")}\ncomment on table "${quoted(schema!)}"."${quoted(name!)}" is '${line}';\n`;
}

/**
 * `text` without the `<key>: { ... }` properties named in `keys`, with the
 * comma and the line each leaves behind. Only code counts: a key in a string or
 * a comment stays.
 */
export function withoutOptionKeys(
  text: string,
  keys: ReadonlySet<string>,
): string {
  const ranges = codeRanges(text);

  const inCode = (index: number): boolean =>
    ranges.some(([start, end]) => index >= start && index < end);

  const edits: [number, number][] = [];

  for (const match of text.matchAll(/\b([A-Za-z_]\w*)\s*:\s*\{/g)) {
    if (!keys.has(match[1]!) || !inCode(match.index)) {
      continue;
    }

    let depth = 0;
    let end = match.index + match[0].length - 1;

    for (; end < text.length; end += 1) {
      if (!inCode(end)) {
        continue;
      }

      depth += text[end] === "{" ? 1 : text[end] === "}" ? -1 : 0;

      if (depth === 0) {
        break;
      }
    }

    end += 1;

    const after = /^[ \t]*,?[ \t]*\n?/.exec(text.slice(end))![0];
    const lineStart = text.lastIndexOf("\n", match.index) + 1;
    const alone = text.slice(lineStart, match.index).trim() === "";

    edits.push([alone ? lineStart : match.index, end + after.length]);
  }

  return edits
    .toSorted((a, b) => b[0] - a[0])
    .reduce((out, [start, end]) => out.slice(0, start) + out.slice(end), text);
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
        parseDeclared(file.text).creates.some((each) => each.table === table),
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

    const text = withoutOptionKeys(input.config.text, keys);

    if (text !== input.config.text) {
      files.push({ path: input.config.path, contents: text, policy: "edit" });
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
