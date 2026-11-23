import type { Node } from "oxc-parser";

import { walk } from "oxc-walker";

import type { BlockTable } from "../../sql/index.ts";
import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import { toSnake } from "../../index.ts";
import { blockTables } from "../../sql/index.ts";
import { parseSource } from "../config-document/parse.ts";
import { appTablesOf } from "./app-tables.ts";
import { PROJECTION_RULES, projectedBlockTables } from "./projections.ts";
import { provablyNotClient } from "./receiver-types.ts";

const DIRECT_METHODS: ReadonlySet<string> = new Set([
  "insert",
  "update",
  "upsert",
  "delete",
]);

const TYPED_METHODS: ReadonlySet<string> = new Set([
  "create",
  ...DIRECT_METHODS,
]);

interface OwnedTable {
  readonly block: string;
  readonly logical: string;
  readonly table: BlockTable;
  /** The app's view a write went through, as `schema.view`. */
  readonly view?: string;
}

interface OwnedTables {
  /** By `schema.name`. */
  readonly qualified: ReadonlyMap<string, OwnedTable>;
  /** By name, for a `.from()` without `.schema()`. */
  readonly named: ReadonlyMap<string, OwnedTable>;
  /** The app's tables, which a write without `.schema()` reaches first. */
  readonly own: Readonly<Record<string, string>>;
  /** The app's projection views over block tables, by `schema.view`. */
  readonly views: ReadonlyMap<string, OwnedTable>;
}

/**
 * The tables blocks create. Tables of the app's that a block runs over (ADR 0098)
 * are the app's to write.
 */
function ownedTables(context: DoctorContext): OwnedTables {
  const own = appTablesOf(context);
  const qualified = new Map<string, OwnedTable>();
  const named = new Map<string, OwnedTable>();

  for (const [block, tables] of Object.entries(
    blockTables(context.config).byBlock,
  )) {
    for (const [logical, table] of Object.entries(tables)) {
      if (!Object.hasOwn(own, table.table)) {
        qualified.set(table.table, { block, logical, table });

        if (!named.has(table.name)) {
          named.set(table.name, { block, logical, table });
        }
      }
    }
  }

  const views = new Map<string, OwnedTable>();

  for (const { base, view } of projectedBlockTables(context)) {
    const entry = qualified.get(base);

    if (entry !== undefined) {
      views.set(view, { ...entry, view });
    }
  }

  return { qualified, named, own, views };
}

/**
 * The block table a `.from()` writes. Without `.schema()`, a table of the app's
 * in `public` wins; otherwise the name is the block's, reached through a client
 * created with `db: { schema }`.
 */
function writtenTable(
  owned: OwnedTables,
  schema: string | undefined,
  name: string,
): OwnedTable | undefined {
  if (schema !== undefined) {
    return (
      owned.qualified.get(`${schema}.${name}`) ??
      owned.views.get(`${schema}.${name}`)
    );
  }

  return (
    owned.qualified.get(`public.${name}`) ??
    owned.views.get(`public.${name}`) ??
    (Object.hasOwn(owned.own, `public.${name}`)
      ? undefined
      : owned.named.get(name))
  );
}

/** The keys block clients sit at on `db`: `webhooks` is `db.webhooks`. */
function blockClientKeys(context: DoctorContext): ReadonlySet<string> {
  return new Set(
    context.config.blockNames.flatMap((name) => [
      name,
      name.replaceAll(/-([a-z0-9])/g, (_, char: string) => char.toUpperCase()),
    ]),
  );
}

interface Write {
  readonly index: number;
  readonly method: string;
  readonly entry: OwnedTable;
}

function writesIn(
  text: string,
  owned: OwnedTables,
  clients: ReadonlySet<string>,
  notClient: (offset: number) => boolean,
): Write[] {
  const writes: Write[] = [];

  walk(parseSource(text).program, {
    enter(node) {
      if (node.type !== "CallExpression") {
        return;
      }

      const method = memberName(node.callee);

      if (method === undefined || node.callee.type !== "MemberExpression") {
        return;
      }

      // A supabase-js write: `.from("x").insert(`, with `.schema("s")` before.
      const from = node.callee.object;

      const table =
        from.type === "CallExpression" ? fromTable(from) : undefined;

      if (table !== undefined && DIRECT_METHODS.has(method)) {
        const entry = writtenTable(owned, table.schema, table.name);

        if (entry !== undefined) {
          writes.push({ index: table.start, method, entry });
        }

        return;
      }

      // A typed client write: `db.webhookEndpoints.create(`.
      if (!TYPED_METHODS.has(method) || from.type !== "MemberExpression") {
        return;
      }

      const key = memberName(from);

      const receiver =
        from.object.type === "Identifier"
          ? from.object
          : from.object.type === "MemberExpression"
            ? from.object.property
            : undefined;

      if (
        key === undefined ||
        receiver?.type !== "Identifier" ||
        clients.has(key) ||
        clients.has(receiver.name) ||
        notClient(receiver.start)
      ) {
        return;
      }

      const entry = writtenTable(owned, undefined, toSnake(key));

      if (entry !== undefined) {
        writes.push({ index: receiver.start, method, entry });
      }
    },
  });

  return writes.toSorted((a, b) => a.index - b.index);
}

/** The name after the dot of a member that isn't computed. */
function memberName(node: Node): string | undefined {
  return node.type === "MemberExpression" &&
    !node.computed &&
    node.property.type === "Identifier"
    ? node.property.name
    : undefined;
}

const literalString = (node: Node | undefined): string | undefined =>
  node?.type === "Literal" && typeof node.value === "string"
    ? node.value
    : node?.type === "TemplateLiteral" &&
        node.expressions.length === 0 &&
        node.quasis[0]
      ? (node.quasis[0].value.cooked ?? undefined)
      : undefined;

/** `.from("x")`, with the `.schema("s")` it follows, and where the chain starts. */
function fromTable(
  call: Node,
): { schema?: string; name: string; start: number } | undefined {
  if (
    call.type !== "CallExpression" ||
    memberName(call.callee) !== "from" ||
    call.callee.type !== "MemberExpression"
  ) {
    return undefined;
  }

  const name = literalString(call.arguments[0]);

  if (name === undefined || !/^[A-Za-z_][\w$]*$/.test(name)) {
    return undefined;
  }

  const before = call.callee.object;

  const schema =
    before.type === "CallExpression" && memberName(before.callee) === "schema"
      ? literalString(before.arguments[0])
      : undefined;

  const start =
    schema !== undefined &&
    before.type === "CallExpression" &&
    before.callee.type === "MemberExpression"
      ? before.callee.property.start
      : call.callee.property.start;

  return schema === undefined ? { name, start } : { schema, name, start };
}

const lineAt = (text: string, index: number): number =>
  text.slice(0, index).split("\n").length;

/**
 * App code that writes a block's table with supabase-js (BS351), which skips
 * the block's functions: its events, hooks and checks.
 */
function directBlockWrites(context: DoctorContext): FindingInput[] {
  if (context.config.blockNames.length === 0) {
    return [];
  }

  const owned = ownedTables(context);

  if (owned.qualified.size === 0) {
    return [];
  }

  const clients = blockClientKeys(context);

  return context.sources.flatMap((file) =>
    writesIn(
      file.text,
      owned,
      clients,
      (offset) =>
        provablyNotClient(context.symbols, file.path, offset) === true,
    ).map(({ index, method, entry }): FindingInput => {
      const line = lineAt(file.text, index);

      return {
        message: `${file.path}:${String(line)} calls .${method}() on ${entry.view === undefined ? "" : `${entry.view}, the app's view over `}${entry.table.table}, the ${entry.logical} table of blocks.${entry.block}. A direct write skips the block's functions, so its events, hooks and checks don't run. Write it through the ${entry.block} API that createBlocks returns.`,
        target: `${file.path}:${String(line)}`,
        location: { file: file.path, line },
      };
    }),
  );
}

export const BLOCK_WRITE_RULES: readonly Rule[] = [
  {
    code: "BS351",
    severity: "warning",
    title: "App code writes a block's table directly",
    description:
      "A source file calls `.from(\"x\").insert()`, `.update()`, `.upsert()` or `.delete()`, or `create()`, `insert()`, `update()`, `upsert()` or `delete()` on the typed client's table (`db.webhookEndpoints.create()`), on a table a block creates (`blockTables(config).byBlock`). The write skips the block's functions, so its events, hooks and the checks it runs before a write don't run, and the block's other tables can disagree with the row. Write it through the block's API from `createBlocks`. Tables of yours that a block runs over are yours to write and are not reported.",
    check: directBlockWrites,
  },
  ...PROJECTION_RULES,
];
