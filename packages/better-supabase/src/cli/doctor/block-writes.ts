import type { BlockTable } from "../../sql/index.ts";
import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import { toSnake } from "../../index.ts";
import { blockTables } from "../../sql/index.ts";
import { appTablesOf } from "./app-tables.ts";

/**
 * A supabase-js write: `.from("x").insert(`, with an optional `.schema("s")`
 * right before it. The groups are the schema, the table and the method.
 */
const DIRECT_WRITE =
  /(?:\.schema\(\s*["'`]([A-Za-z_][\w$]*)["'`]\s*\)\s*)?\.from\(\s*["'`]([A-Za-z_][\w$]*)["'`]\s*\)\s*\.(insert|update|upsert|delete)\s*\(/g;

/**
 * A typed client write: `db.webhookEndpoints.create(`, or `.insert(` on a
 * client of your own. The groups are the receiver, the table key and the
 * method.
 */
const TYPED_WRITE =
  /(?<![\w$])([A-Za-z_$][\w$]*)\s*\.\s*([A-Za-z_$][\w$]*)\s*\.\s*(create|insert|update|upsert|delete)\s*\(/g;

interface OwnedTable {
  readonly block: string;
  readonly logical: string;
  readonly table: BlockTable;
}

interface OwnedTables {
  /** By `schema.name`. */
  readonly qualified: ReadonlyMap<string, OwnedTable>;
  /** By name, for a `.from()` without `.schema()`. */
  readonly named: ReadonlyMap<string, OwnedTable>;
  /** The app's tables, which a write without `.schema()` reaches first. */
  readonly own: Readonly<Record<string, string>>;
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

  return { qualified, named, own };
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
    return owned.qualified.get(`${schema}.${name}`);
  }

  return (
    owned.qualified.get(`public.${name}`) ??
    (Object.hasOwn(owned.own, `public.${name}`)
      ? undefined
      : owned.named.get(name))
  );
}

/** The keys block clients sit at on `db`: `webhooks-out` is `db.webhooksOut`. */
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
): Write[] {
  const direct = [...text.matchAll(DIRECT_WRITE)].flatMap((match): Write[] => {
    const [, schema, name = "", method = ""] = match;
    const entry = writtenTable(owned, schema, name);

    return entry === undefined ? [] : [{ index: match.index, method, entry }];
  });

  const typed = [...text.matchAll(TYPED_WRITE)].flatMap((match): Write[] => {
    const [, receiver = "", key = "", method = ""] = match;

    if (clients.has(key) || clients.has(receiver)) {
      return [];
    }

    const entry = writtenTable(owned, undefined, toSnake(key));

    return entry === undefined ? [] : [{ index: match.index, method, entry }];
  });

  return [...direct, ...typed].toSorted((a, b) => a.index - b.index);
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
    writesIn(file.text, owned, clients).map(
      ({ index, method, entry }): FindingInput => {
        const line = lineAt(file.text, index);

        return {
          message: `${file.path}:${String(line)} calls .${method}() on ${entry.table.table}, the ${entry.logical} table of blocks.${entry.block}. A direct write skips the block's functions, so its events, hooks and checks don't run. Write it through the ${entry.block} API that createBlocks returns.`,
          target: `${file.path}:${String(line)}`,
          location: { file: file.path, line },
        };
      },
    ),
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
];
