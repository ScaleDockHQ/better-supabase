/**
 * Generates `src/cli/schema-reader/node-fields.generated.ts`: for each parse
 * tree node type, the fields that hold nodes, so `walk.ts` can visit a tree
 * without knowing every node by hand. A field is either a wrapped node (`{
 * ColumnRef: {...} }`) or an untagged message whose type only the declaration
 * knows (`CreatePolicyStmt.table` is a bare `RangeVar`).
 *
 * The table is read from the type declarations `@supabase/pg-parser` ships per
 * Postgres version, merged over every version, so it always matches the types
 * the walker is checked against. `tests/cli/schema-reader/walk.test.ts` fails
 * when the installed package no longer matches the file.
 *
 * `node scripts/gen-pg-node-fields.ts` writes the file; `--check` only
 * compares.
 */
import { readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { parseSync } from "oxc-parser";

export const PG_PARSER_PACKAGE = "@supabase/pg-parser";
export const PG_VERSIONS: readonly number[] = [15, 16, 17];

/** `[field, "Node" or a message type, whether it is a list]`. */
export type NodeField = readonly [string, string, boolean];

function packageDir(): string {
  return join(
    dirname(fileURLToPath(import.meta.resolve(PG_PARSER_PACKAGE))),
    "..",
  );
}

export async function pgParserVersion(): Promise<string> {
  const pkg: unknown = JSON.parse(
    await readFile(join(packageDir(), "package.json"), "utf-8"),
  );

  if (typeof pkg === "object" && pkg !== null && "version" in pkg) {
    return String(pkg.version);
  }

  throw new Error(`no version in ${PG_PARSER_PACKAGE}/package.json`);
}

interface Named {
  readonly name?: unknown;
}

interface TypeNode {
  readonly type: string;
  readonly typeName?: Named;
  readonly elementType?: TypeNode;
}

interface Member {
  readonly type: string;
  readonly key?: Named;
  readonly typeAnnotation?: { readonly typeAnnotation?: TypeNode };
}

interface Statement {
  readonly type: string;
  readonly declaration?: {
    readonly type: string;
    readonly id?: Named;
    readonly body?: { readonly body?: readonly Member[] };
  };
}

/** Only the fields `nodeFieldsOf` reads, each checked before use. */
function isStatement(value: unknown): value is Statement {
  return typeof value === "object" && value !== null && "type" in value;
}

/** The type name a field refers to, and whether it is a list of it. */
function referenced(type: TypeNode | undefined): [string, boolean] | undefined {
  if (type?.type === "TSArrayType") {
    const inner = referenced(type.elementType);

    return inner === undefined ? undefined : [inner[0], true];
  }

  const name = type?.typeName?.name;

  return type?.type === "TSTypeReference" && typeof name === "string"
    ? [name, false]
    : undefined;
}

/**
 * The node fields of one version's type declarations.
 *
 * @param declarations - The text of `wasm/<version>/pg-parser-types.d.ts`.
 * @returns For each interface, the fields that hold a `Node` or a message.
 */
export function nodeFieldsOf(declarations: string): Map<string, NodeField[]> {
  const { program } = parseSync("pg-parser-types.d.ts", declarations);
  const statements: readonly unknown[] = program.body;
  const interfaces = new Map<string, readonly Member[]>();

  for (const statement of statements) {
    const declaration = isStatement(statement)
      ? statement.declaration
      : undefined;

    const name = declaration?.id?.name;

    if (
      declaration?.type === "TSInterfaceDeclaration" &&
      typeof name === "string"
    ) {
      interfaces.set(name, declaration.body?.body ?? []);
    }
  }

  const table = new Map<string, NodeField[]>();

  for (const [name, members] of interfaces) {
    const fields: NodeField[] = [];

    for (const member of members) {
      const key = member.key?.name;
      const target = referenced(member.typeAnnotation?.typeAnnotation);

      if (
        member.type === "TSPropertySignature" &&
        typeof key === "string" &&
        target !== undefined &&
        (target[0] === "Node" || interfaces.has(target[0]))
      ) {
        fields.push([key, target[0], target[1]]);
      }
    }

    if (fields.length > 0) {
      table.set(name, fields);
    }
  }

  return table;
}

/** The tables of several versions as one: every field any version has. */
export function mergedNodeFields(
  tables: readonly Map<string, NodeField[]>[],
): Record<string, NodeField[]> {
  const merged = new Map<string, Map<string, NodeField>>();

  for (const table of tables) {
    for (const [name, fields] of table) {
      const known = merged.get(name) ?? new Map<string, NodeField>();

      for (const field of fields) {
        known.set(field[0], known.get(field[0]) ?? field);
      }

      merged.set(name, known);
    }
  }

  return Object.fromEntries(
    [...merged.keys()]
      .toSorted()
      .map((name) => [name, [...merged.get(name)!.values()]]),
  );
}

/** The merged node fields of every supported version in the installed package. */
export async function installedNodeFields(): Promise<
  Record<string, NodeField[]>
> {
  const tables = await Promise.all(
    PG_VERSIONS.map(async (version) =>
      nodeFieldsOf(
        await readFile(
          join(packageDir(), "wasm", String(version), "pg-parser-types.d.ts"),
          "utf-8",
        ),
      ),
    ),
  );

  return mergedNodeFields(tables);
}

export function renderFieldsFile(
  version: string,
  table: Record<string, NodeField[]>,
): string {
  const rows = Object.entries(table)
    .map(
      ([name, fields]) =>
        `  ${name}: [${fields
          .map(([field, type, list]) => `["${field}", "${type}", ${list}]`)
          .join(", ")}],`,
    )
    .join("\n");

  return `// Generated by scripts/gen-pg-node-fields.ts from ${PG_PARSER_PACKAGE} ${version} (Postgres ${PG_VERSIONS.join(", ")}). Do not edit.

/** The \`${PG_PARSER_PACKAGE}\` version the table below was read from. */
export const PG_PARSER_VERSION = "${version}";

/**
 * For each node type, the fields that hold nodes: the field name, \`"Node"\`
 * for a wrapped node or the message type of an untagged value, and whether the
 * field is a list.
 */
export const NODE_FIELDS: Readonly<
  Record<string, readonly (readonly [string, string, boolean])[]>
> = {
${rows}
};
`;
}

export const OUTPUT: string = fileURLToPath(
  new URL("../src/cli/schema-reader/node-fields.generated.ts", import.meta.url),
);

if (import.meta.main) {
  const contents = renderFieldsFile(
    await pgParserVersion(),
    await installedNodeFields(),
  );

  if (process.argv.includes("--check")) {
    const current = await readFile(OUTPUT, "utf-8").catch(() => "");

    if (current !== contents) {
      console.error(`stale: ${OUTPUT}`);
      process.exitCode = 1;
    }
  } else {
    await writeFile(OUTPUT, contents);
    console.log(`wrote ${OUTPUT}`);
  }
}
