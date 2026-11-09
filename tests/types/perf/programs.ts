import type {
  CatalogColumn,
  CatalogForeignKey,
  CatalogFunction,
  CatalogTable,
  CatalogUnique,
  Snapshot,
} from "better-supabase/cli";

import { fromCatalog } from "better-supabase/cli";

/** Generators for the programs and snapshots the bench measures. */

export interface Profile {
  readonly tables: number;
  readonly queried: number;
  /**
   * CentraKit's shape: uuid keys, `unique (id, organization_id)` on every
   * table, composite foreign keys that repeat `organization_id`, and the
   * `graphql_public` schema next to `public`, plus one each of an enum column,
   * a CHECK union, two foreign keys to one table, a view, a JSON override and a
   * function the consumer calls.
   */
  readonly composite: boolean;
}

export const name = (i: number): string => `t${String(i).padStart(3, "0")}`;

function column(
  columnName: string,
  udt: string,
  options: { nullable?: boolean; default?: string; enum?: boolean } = {},
): CatalogColumn {
  return {
    name: columnName,
    udt,
    format: udt,
    typeSchema: options.enum ? "public" : "pg_catalog",
    isArray: false,
    isEnum: options.enum ?? false,
    nullable: options.nullable ?? false,
    hasDefault: options.default !== undefined,
    default: options.default ?? null,
    identity: null,
    generated: false,
    updatable: true,
    comment: null,
  };
}

function foreignKey(
  table: string,
  cols: readonly string[],
  ref: string,
  refCols: readonly string[] = ["id"],
): CatalogForeignKey {
  return {
    name: `${table}_${cols.join("_")}_fkey`,
    columns: cols,
    refSchema: "public",
    refTable: ref,
    refColumns: refCols,
    oneToOne: false,
    onDelete: "cascade",
    onUpdate: "no action",
  };
}

function table(
  tableName: string,
  columns: CatalogColumn[],
  foreignKeys: CatalogForeignKey[],
  uniques: CatalogUnique[] = [],
  options: { view?: boolean; checks?: CatalogTable["checks"] } = {},
): CatalogTable {
  return {
    id: 0,
    schema: "public",
    name: tableName,
    kind: options.view ? "view" : "table",
    rls: !options.view,
    forceRls: false,
    replicaIdentity: options.view ? null : "DEFAULT",
    insertable: !options.view,
    updatable: !options.view,
    comment: null,
    columns,
    primaryKey: options.view ? [] : ["id"],
    uniques,
    foreignKeys,
    checks: options.checks ?? [],
    indexes: [],
    policies: [],
    triggers: [],
    grants: [],
  };
}

/** The function `graphql_public` holds on every Supabase project. */
const GRAPHQL: CatalogFunction = {
  schema: "graphql_public",
  name: "graphql",
  signature:
    '"operationName" text, query text, variables jsonb, extensions jsonb',
  args: ["operationName", "query", "variables", "extensions"].map(
    (arg, index) => ({
      name: arg,
      udt: index < 2 ? "text" : "jsonb",
      isArray: false,
      hasDefault: true,
    }),
  ),
  returnsTable: null,
  returns: "jsonb",
  returnsRelation: null,
  returnsSet: false,
  volatility: "volatile",
  securityDefiner: false,
  language: "sql",
  searchPath: null,
};

const COUNT_ITEMS: CatalogFunction = {
  schema: "public",
  name: "count_items",
  signature: "p_organization_id uuid",
  args: [
    {
      name: "p_organization_id",
      udt: "uuid",
      isArray: false,
      hasDefault: false,
    },
  ],
  returnsTable: null,
  returns: "int4",
  returnsRelation: null,
  returnsSet: false,
  volatility: "stable",
  securityDefiner: false,
  language: "sql",
  searchPath: "",
};

const KIND_CHECK = {
  name: "kind_check",
  definition:
    "CHECK ((kind = ANY (ARRAY['task'::text, 'note'::text, 'call'::text])))",
};

/** `extraColumnOn` names a table that gets one more column, for incremental gen. */
export function snapshot(profile: Profile, extraColumnOn?: string): Snapshot {
  const tables = [
    table(
      "organizations",
      [
        column("id", "uuid", { default: "gen_random_uuid()" }),
        column("name", "text"),
      ],
      [],
    ),
  ];

  for (let i = 0; i < profile.tables - (profile.composite ? 1 : 0); i += 1) {
    const tableName = name(i);

    const columns = [
      column("id", "uuid", { default: "gen_random_uuid()" }),
      column("organization_id", "uuid"),
      column("parent_id", "uuid", { nullable: true }),
      column("name", "text"),
      column("description", "text", { nullable: true }),
      column("amount", "numeric", { nullable: true }),
      column("quantity", "int4", { default: "0" }),
      column("active", "bool", { default: "true" }),
      column("metadata", "jsonb", { nullable: true }),
      column("created_at", "timestamptz", { default: "now()" }),
      column("updated_at", "timestamptz", { default: "now()" }),
      column("archived_at", "timestamptz", { nullable: true }),
    ];

    for (let c = 0; c < 8; c += 1) {
      columns.push(column(`field_${String(c)}`, "text", { nullable: true }));
    }

    if (profile.composite) {
      columns.push(
        column("priority", "priority", { default: "'normal'", enum: true }),
        column("kind", "text", { default: "'task'" }),
      );
    }

    if (tableName === extraColumnOn) {
      columns.push(column("extra", "text", { nullable: true }));
    }

    const keys = [foreignKey(tableName, ["organization_id"], "organizations")];

    if (i > 0) {
      keys.push(
        profile.composite
          ? foreignKey(
              tableName,
              ["parent_id", "organization_id"],
              name(i - 1),
              ["id", "organization_id"],
            )
          : foreignKey(tableName, ["parent_id"], name(i - 1)),
      );
    }

    const uniques = profile.composite
      ? [
          {
            name: `${tableName}_id_organization_id_key`,
            columns: ["id", "organization_id"],
          },
        ]
      : [];

    tables.push(
      table(tableName, columns, keys, uniques, {
        checks: profile.composite ? [KIND_CHECK] : [],
      }),
    );
  }

  if (profile.composite) {
    tables.push(
      table(
        "transfers",
        [
          column("id", "uuid", { default: "gen_random_uuid()" }),
          column("from_organization_id", "uuid"),
          column("to_organization_id", "uuid"),
          column("amount", "numeric"),
        ],
        [
          foreignKey("transfers", ["from_organization_id"], "organizations"),
          foreignKey("transfers", ["to_organization_id"], "organizations"),
        ],
      ),
      table(
        "item_summaries",
        [
          column("id", "uuid", { nullable: true }),
          column("organization_id", "uuid", { nullable: true }),
          column("name", "text", { nullable: true }),
          column("priority", "priority", { nullable: true, enum: true }),
        ],
        [],
        [],
        { view: true },
      ),
    );
  }

  return fromCatalog({
    schemas: profile.composite ? ["public", "graphql_public"] : ["public"],
    tables,
    enums: profile.composite
      ? [
          {
            schema: "public",
            name: "priority",
            values: ["low", "normal", "high"],
          },
        ]
      : [],
    functions: profile.composite ? [GRAPHQL, COUNT_ITEMS] : [],
    buckets: [],
    realtime: [],
  });
}

/**
 * Mapper mode writes no database.types.ts, so `Database` comes from
 * generated.ts: the enriched type, which costs the composite profile about four
 * times the instantiations in either mode.
 */
export function consumer(
  profile: Profile,
  database = "./database.types.ts",
): string {
  const lines = [
    "import { createClient, type SupabaseClient } from '@supabase/supabase-js';",
    ...(profile.composite
      ? [`import type { Database } from '${database}';`]
      : []),
    "import { createSupabase } from 'better-supabase';",
    "import { membershipsExtension } from 'better-supabase/blocks/memberships';",
    "import { schema } from './generated.ts';",
    "declare const client: SupabaseClient;",
    "const db = createSupabase(schema).use(membershipsExtension()).connect(client);",
    "export async function run(): Promise<void> {",
  ];

  if (profile.composite) {
    lines.push(
      "  const typed = createClient<Database>('https://x.supabase.co', 'key');",
      "  await typed.from('item_summaries').select('id, priority');",
      "  await db.$rpc('count_items', { p_organization_id: 'o' }).orThrow();",
      "  await db.transfers.list({ include: { fromOrganization: { select: ['name'] }, toOrganization: { select: ['name'] } } }).orThrow();",
      "  await db.itemSummaries.list({ where: { priority: 'high' } }).orThrow();",
      `  await db.${name(1)}.update('id', { kind: 'note', priority: 'low', metadata: { tags: ['a'] } }).orThrow();`,
    );
  }

  for (let i = 1; i <= profile.queried; i += 1) {
    const key = name(i);
    const child = name(i + 1);
    lines.push(
      `  await db.${key}.list({ select: ['id', 'name', 'createdAt'], where: { active: true, quantity: { gt: 1 } }, orderBy: { createdAt: 'desc' }, include: { parent: { select: ['id', 'name'] }, ${child}: { select: ['id'] } } }).orThrow();`,
      `  await db.${key}.create({ organizationId: 'o', name: 'n' }, { select: ['id'] }).orThrow();`,
      `  await db.${key}.update('id', { name: 'x' }).orThrow();`,
    );
  }

  lines.push("}", "");

  return lines.join("\n");
}

/**
 * Plain TypeScript with no better-supabase types, so its check time tracks the
 * machine only.
 */
export function calibrationProgram(): string {
  const lines = [
    "type Deep<T> = { readonly [K in keyof T]: T[K] extends object ? Deep<T[K]> : T[K] };",
    "type Pick2<T, K extends keyof T> = { [P in K]: T[P] };",
  ];

  for (let i = 0; i < 400; i += 1) {
    const fields = Array.from(
      { length: 20 },
      (_, f) =>
        `f${String(f)}: ${f % 2 ? "string" : `{ n: number; s: string[] }`};`,
    ).join(" ");

    lines.push(
      `interface I${String(i)} { ${fields} }`,
      `export const v${String(i)}: Pick2<Deep<I${String(i)}>, "f0" | "f1" | "f2"> = { f0: { n: 1, s: [] }, f1: "", f2: { n: 2, s: ["a"] } };`,
    );
  }

  return `${lines.join("\n")}\n`;
}

/** The server program queries this many times the client program's tables. */
const SERVER_QUERY_FACTOR = 3;

/**
 * The server's program: `createServer` over the generated schema, a context per
 * request and reads and writes through `ctx.db`, with the same query shapes as
 * the client program (selection, filters, ordering, two includes) so the
 * context's types are checked against real work. It has its own gate so a
 * change to the server types (ADR 0450) cannot hide in the client program's
 * numbers, and `benchServer` refuses a program that checks below the
 * calibration floor.
 */
export function serverProgram(profile: Profile): string {
  const lines = [
    "import { createSupabase } from 'better-supabase';",
    "import { createServer } from 'better-supabase/server';",
    "import { schema } from './generated.ts';",
    "const server = createServer(createSupabase(schema), { env: { SUPABASE_URL: 'https://x.supabase.co', SUPABASE_PUBLISHABLE_KEY: 'key' } });",
    "export async function run(request: Request): Promise<void> {",
    "  const ctx = await server.context(request);",
    "  const service = server.contextFor(ctx.auth);",
  ];

  if (profile.composite) {
    lines.push(
      "  await ctx.db.$rpc('count_items', { p_organization_id: 'o' }).orThrow();",
      "  await ctx.db.transfers.list({ include: { fromOrganization: { select: ['name'] }, toOrganization: { select: ['name'] } } }).orThrow();",
      "  await ctx.db.itemSummaries.list({ where: { priority: 'high' } }).orThrow();",
    );
  }

  for (let i = 1; i <= profile.queried * SERVER_QUERY_FACTOR; i += 1) {
    const key = name(i);
    const child = name(i + 1);
    lines.push(
      `  await ctx.db.${key}.list({ select: ['id', 'name', 'createdAt'], where: { active: true, quantity: { gt: 1 } }, orderBy: { createdAt: 'desc' }, include: { parent: { select: ['id', 'name'] }, ${child}: { select: ['id'] } } }).orThrow();`,
      `  await ctx.db.${key}.create({ organizationId: 'o', name: 'n' }, { select: ['id'] }).orThrow();`,
      `  await ctx.db.${key}.update('id', { name: 'x' }).orThrow();`,
      `  await service.db.${key}.list({ select: ['id'], where: { active: true } }).orThrow();`,
    );
  }

  lines.push("}", "");

  return lines.join("\n");
}

/**
 * A `defineConfig` call typed against a provider with a large key union: 300
 * keys, 40 subjects that name keys, 20 roles that list them and 5 blocks that
 * rename an action. The permission typing is the one change that can grow the
 * config's check time, so it has its own gate (ADR 0323).
 */
export function configProgram(): string {
  const keys = Array.from(
    { length: 300 },
    (_, i) => `"res${String(i % 40)}.act${String(i)}"`,
  );

  const key = (i: number): string => keys.at(i % keys.length) ?? "";

  const roles = Array.from(
    { length: 20 },
    (_, r) =>
      `      r${String(r)}: [${Array.from({ length: 15 }, (_, k) => key(r * 15 + k)).join(", ")}],`,
  );

  const subjects = Array.from(
    { length: 40 },
    (_, i) =>
      `    s${String(i)}: { table: "public.s${String(i)}", permissions: { read: ${key(i)}, write: { key: ${key(i + 40)}, also: ${key(i + 80)} } } },`,
  );

  return `import type { AuthorizationProvider } from "better-supabase/config";

import { defineConfig } from "better-supabase/config";

type Key = ${keys.join(" | ")};

declare const provider: AuthorizationProvider<Key>;

export default defineConfig({
  auth: { authorization: provider },
  blocks: {
    permissions: {
      roles: {
${roles.join("\n")}
      },
    },
    tasks: { permissions: { read: ${key(1)} } },
  },
  recordTypes: {
${subjects.join("\n")}
  },
});
`;
}
