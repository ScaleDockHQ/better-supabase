import type { Node, ImportDeclarationSpecifier, Program } from "oxc-parser";

import { readdir, readFile } from "node:fs/promises";
import { posix } from "node:path";
import { walk } from "oxc-walker";

import type { Codemod, FileRewrite, ReviewLine } from "./codemod.ts";

import { rewriteSource } from "./config-document/index.ts";
import { schemaModulePath } from "./gen/emit.ts";
import { addNamedImports } from "./import-edits.ts";

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

/** `to` as an import path from `from`, keeping the extension style of `like`. */
function relativeSpecifier(from: string, to: string, like: string): string {
  let path = posix.relative(posix.dirname(from), to);

  if (!path.startsWith(".")) {
    path = `./${path}`;
  }

  const extension = /\.[cm]?[jt]sx?$/.exec(like)?.[0];

  return extension === undefined ? path.replace(/\.[cm]?[jt]sx?$/, "") : path;
}

/** The name an import specifier refers to in its source module. */
function importedName(
  specifier: ImportDeclarationSpecifier,
): string | undefined {
  if (specifier.type !== "ImportSpecifier") {
    return undefined;
  }

  const { imported } = specifier;

  return imported.type === "Literal" ? imported.value : imported.name;
}

/** Whether the module opens with the `"use client"` directive. */
function isClientModule(program: Program): boolean {
  for (const statement of program.body) {
    if (
      statement.type !== "ExpressionStatement" ||
      statement.directive === null
    ) {
      return false;
    }

    if (statement.directive === "use client") {
      return true;
    }
  }

  return false;
}

/**
 * The rewrite of one file, given the tables on disk. `output` is the generated
 * module (`config.output`, absolute); `path` the file, absolute. A file that
 * does not parse comes back unchanged with a review line.
 */
export function rewriteForTableModules(
  path: string,
  text: string,
  output: string,
  tables: readonly TableModuleFile[],
): { readonly text: string; readonly review: readonly ReviewLine[] } {
  const folder = posix.dirname(output);
  const outputBase = output.replace(/\.[cm]?[jt]sx?$/, "");
  const schemaBase = schemaModulePath(output).replace(/\.[cm]?[jt]sx?$/, "");
  const byKey = new Map(tables.map((table) => [table.key, table]));
  const eol = text.includes("\r\n") ? "\r\n" : "\n";

  return rewriteSource(text, ({ program, text: source, edit, report }) => {
    // `schema` moved to the server's schema module.
    for (const statement of program.body) {
      if (
        statement.type !== "ImportDeclaration" ||
        !statement.source.value.startsWith(".")
      ) {
        continue;
      }

      const specifier = statement.source.value;

      const target = posix
        .join(posix.dirname(path), specifier)
        .replace(/\.[cm]?[jt]sx?$/, "");

      if (target !== outputBase) {
        continue;
      }

      const moved = statement.specifiers.filter(
        (each) => importedName(each) === "schema",
      );

      if (moved.length === 0) {
        continue;
      }

      const kept = statement.specifiers.filter((each) => !moved.includes(each));

      if (kept.some((each) => each.type !== "ImportSpecifier")) {
        report(
          statement.start,
          `schema now comes from ${schemaBase.split("/").pop() ?? "the schema module"}, but this import also has a default or namespace import the codemod cannot split; move schema by hand.`,
        );
        continue;
      }

      const slice = (each: Node): string => source.slice(each.start, each.end);
      const head = `import${statement.importKind === "type" ? " type" : ""} `;
      const quote = source[statement.source.start]!;

      const schemaSpecifier = relativeSpecifier(
        path,
        `${schemaBase}.ts`,
        specifier,
      );

      const schemaImport = `${head}{ ${moved.map(slice).join(", ")} } from ${quote}${schemaSpecifier}${quote}`;

      // The statement's own `;` stays after the last import.
      const whole = source.slice(statement.start, statement.end);
      const semicolon = whole.endsWith(";") ? ";" : "";

      edit.overwrite(
        statement.start,
        statement.end - semicolon.length,
        kept.length === 0
          ? schemaImport
          : `${head}{ ${kept.map(slice).join(", ")} } from ${quote}${specifier}${quote};${eol}${schemaImport}`,
      );
    }

    if (!isClientModule(program)) {
      return;
    }

    const used = new Map<string, TableModuleFile>();

    walk(program, {
      enter(node, parent) {
        if (
          node.type !== "MemberExpression" ||
          node.computed ||
          node.property.type !== "Identifier" ||
          node.object.type !== "MemberExpression" ||
          node.object.computed ||
          node.object.property.type !== "Identifier"
        ) {
          return;
        }

        // `client.db.<table>`: the owner is a plain name, as it is in a hook or a module.
        if (
          node.object.property.name === "db" &&
          node.object.object.type === "Identifier" &&
          !(parent?.type === "CallExpression" && parent.callee === node)
        ) {
          const table = byKey.get(node.property.name);

          if (table !== undefined) {
            used.set(table.key, table);
            edit.overwrite(
              node.start,
              node.end,
              `${node.object.object.name}.table(${table.name})`,
            );
          }

          return;
        }

        if (
          node.object.property.name === "queries" &&
          byKey.has(node.property.name)
        ) {
          report(
            node.start,
            `queries.${node.property.name} is not on a browser client that registers its tables. Define the query with defineListQuery(client, ${node.property.name}Table, ...) and import it from the table module.`,
          );
        }
      },
    });

    if (used.size === 0) {
      return;
    }

    for (const table of used.values()) {
      addNamedImports(
        edit,
        program,
        relativeSpecifier(path, posix.join(folder, table.file), "x.ts"),
        [table.name],
        eol,
      );
    }
  });
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
