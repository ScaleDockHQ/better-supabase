import { readdir, readFile } from "node:fs/promises";
import { posix } from "node:path";

import type { Codemod, FileRewrite, ReviewLine } from "./codemod.ts";

import { codeRanges } from "./code-ranges.ts";
import { schemaModulePath } from "./gen/emit.ts";

/** A table module on disk: the table's key and where its module is. */
export interface TableModuleFile {
  /** The export without its `Table` suffix (`customerTags`). */
  readonly key: string;
  /** The export (`customerTagsTable`). */
  readonly name: string;
  /** Path of the module, relative to the generated module's folder. */
  readonly file: string;
}

const EXPORT = /export const (\w+)Table\b/;

/** Reads the `tables/*.ts` modules `gen` wrote next to `generated.ts`. */
async function readTableModules(
  folder: string,
): Promise<readonly TableModuleFile[]> {
  const names = await readdir(posix.join(folder, "tables")).catch(
    (): string[] => [],
  );

  const found = await Promise.all(
    names
      .filter((name) => name.endsWith(".ts"))
      .map(async (name): Promise<TableModuleFile[]> => {
        const text = await readFile(
          posix.join(folder, "tables", name),
          "utf-8",
        );

        const key = EXPORT.exec(text)?.[1];

        return key === undefined
          ? []
          : [{ key, name: `${key}Table`, file: `tables/${name}` }];
      }),
  );

  return found.flat();
}

const IMPORT_LIST =
  /(import\s+(?:type\s+)?)\{([^}]*)\}(\s*from\s*)(["'])([^"']+)\4/g;

const USE_CLIENT =
  /^\s*(?:\/\/[^\n]*\n|\/\*[\s\S]*?\*\/\s*)*["']use client["']/;

const TABLE_READ = /(?<![\w$.])([\w$]+)\.db\.([A-Za-z_$][\w$]*)(?![\w$(])/g;

const QUERY_READ = /\.queries\.([A-Za-z_$][\w$]*)/g;

/** `to` as an import path from `from`, keeping the extension style of `like`. */
function relativeSpecifier(from: string, to: string, like: string): string {
  let path = posix.relative(posix.dirname(from), to);

  if (!path.startsWith(".")) {
    path = `./${path}`;
  }

  const extension = /\.[cm]?[jt]sx?$/.exec(like)?.[0];

  return extension === undefined ? path.replace(/\.[cm]?[jt]sx?$/, "") : path;
}

/**
 * The rewrite of one file, given the tables on disk. `output` is the generated
 * module (`config.output`, absolute); `path` the file, absolute.
 */
export function rewriteForTableModules(
  path: string,
  text: string,
  output: string,
  tables: readonly TableModuleFile[],
): { readonly text: string; readonly review: readonly ReviewLine[] } {
  const review: ReviewLine[] = [];
  const folder = posix.dirname(output);
  const outputBase = output.replace(/\.[cm]?[jt]sx?$/, "");
  const schemaBase = schemaModulePath(output).replace(/\.[cm]?[jt]sx?$/, "");
  let next = text;

  // `schema` moved to the server's schema module.
  next = next.replaceAll(
    IMPORT_LIST,
    (
      whole: string,
      head: string,
      list: string,
      from: string,
      quote: string,
      specifier: string,
    ) => {
      if (!specifier.startsWith(".")) {
        return whole;
      }

      const target = posix
        .join(posix.dirname(path), specifier)
        .replace(/\.[cm]?[jt]sx?$/, "");

      if (target !== outputBase) {
        return whole;
      }

      const names = list
        .split(",")
        .map((name) => name.trim())
        .filter((name) => name !== "");

      const moved = names.filter((name) => /^schema(\s+as\s+\w+)?$/.test(name));

      if (moved.length === 0) {
        return whole;
      }

      const kept = names.filter((name) => !moved.includes(name));

      const schemaSpecifier = relativeSpecifier(
        path,
        `${schemaBase}.ts`,
        specifier,
      );

      const schemaImport = `${head}{ ${moved.join(", ")} }${from}${quote}${schemaSpecifier}${quote}`;

      return kept.length === 0
        ? schemaImport
        : `${head}{ ${kept.join(", ")} }${from}${quote}${specifier}${quote};\n${schemaImport}`;
    },
  );

  if (!USE_CLIENT.test(next)) {
    return { text: next, review };
  }

  const byKey = new Map(tables.map((table) => [table.key, table]));
  const ranges = codeRanges(next);
  const used = new Map<string, TableModuleFile>();

  const inCode = (index: number): boolean =>
    ranges.some(([start, end]) => index >= start && index < end);

  next = next.replaceAll(
    TABLE_READ,
    (whole: string, owner: string, key: string, offset: number) => {
      const table = byKey.get(key);

      if (table === undefined || !inCode(offset)) {
        return whole;
      }

      used.set(key, table);

      return `${owner}.table(${table.name})`;
    },
  );

  for (const match of next.matchAll(QUERY_READ)) {
    if (byKey.has(match[1]!)) {
      review.push({
        line: next.slice(0, match.index).split("\n").length,
        message: `queries.${match[1]!} is not on a browser client that registers its tables. Define the query with defineListQuery(client, ${match[1]!}Table, ...) and import it from the table module.`,
      });
    }
  }

  if (used.size === 0) {
    return { text: next, review };
  }

  const imports = [...used.values()]
    .map(
      (table) =>
        `import { ${table.name} } from "${relativeSpecifier(path, posix.join(folder, table.file), "x.ts")}";`,
    )
    .join("\n");

  // After the last import, so the file keeps its directive and header.
  const last = [...next.matchAll(/^import[\s\S]*?;\s*$/gm)].at(-1);
  const at = last === undefined ? 0 : last.index + last[0].length;

  return {
    text: `${next.slice(0, at)}${at === 0 ? "" : "\n"}${imports}\n${next.slice(at).replace(/^\n/, "")}`,
    review,
  };
}

/**
 * Moves a project to the default layout: `schema` is imported from
 * `generated-schema`, and a client file reads its tables through the table
 * modules. A file that uses `queries.<table>` is listed for a manual change.
 */
export function tableModulesCodemod(): Codemod {
  return {
    name: "table-modules",
    description:
      "Import schema from generated-schema and read tables in client files through the table modules",
    files: async (project): Promise<FileRewrite> => {
      const output = posix.join(
        project.config.root.split("\\").join("/"),
        project.config.output,
      );

      const tables = await readTableModules(posix.dirname(output));

      return (path, text) =>
        project.config.gen.tableModules === false ||
        project.config.gen.contentMapper === true
          ? { text, review: [] }
          : rewriteForTableModules(
              path.split("\\").join("/"),
              text,
              output,
              tables,
            );
    },
  };
}
