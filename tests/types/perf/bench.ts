import { execFileSync, spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import {
  type CatalogColumn,
  type CatalogForeignKey,
  type CatalogFunction,
  type CatalogTable,
  type CatalogUnique,
  fromCatalog,
  type Snapshot,
} from "@better-supabase/cli";

interface Measurement {
  readonly types: number;
  readonly instantiations: number;
}

interface Profile {
  readonly tables: number;
  readonly queried: number;
  /**
   * CentraKit's shape: uuid keys, `unique (id, organization_id)` on every
   * table, composite foreign keys that repeat `organization_id`, and the
   * `graphql_public` schema next to `public`.
   */
  readonly composite: boolean;
}

interface BaselineEntry extends Profile {
  readonly measurement: Measurement;
}

type Baseline = Readonly<Record<string, BaselineEntry>>;

const PROFILES: Readonly<Record<string, Profile>> = {
  default: { tables: 150, queried: 40, composite: false },
  centrakit: { tables: 250, queried: 40, composite: true },
};
const TOLERANCE = 0.1;

const here = dirname(fileURLToPath(import.meta.url));
const work = join(here, "tmp");
const require = createRequire(import.meta.url);
const tsc = join(
  dirname(require.resolve("typescript/package.json")),
  "bin",
  "tsc",
);
const cli = join(
  dirname(require.resolve("better-supabase/package.json")),
  "dist",
  "cli",
  "bin.js",
);

const name = (i: number): string => `t${String(i).padStart(3, "0")}`;

function column(
  columnName: string,
  udt: string,
  options: { nullable?: boolean; default?: string } = {},
): CatalogColumn {
  return {
    name: columnName,
    udt,
    format: udt,
    typeSchema: "pg_catalog",
    isArray: false,
    isEnum: false,
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
): CatalogTable {
  return {
    id: 0,
    schema: "public",
    name: tableName,
    kind: "table",
    rls: true,
    forceRls: false,
    replicaIdentity: "DEFAULT",
    insertable: true,
    updatable: true,
    comment: null,
    columns,
    primaryKey: ["id"],
    uniques,
    foreignKeys,
    checks: [],
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

function snapshot(profile: Profile): Snapshot {
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
  for (let i = 0; i < profile.tables - (profile.composite ? 1 : 0); i++) {
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
    for (let c = 0; c < 8; c++)
      columns.push(column(`field_${String(c)}`, "text", { nullable: true }));
    const keys = [foreignKey(tableName, ["organization_id"], "organizations")];
    if (i > 0)
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
    const uniques = profile.composite
      ? [
          {
            name: `${tableName}_id_organization_id_key`,
            columns: ["id", "organization_id"],
          },
        ]
      : [];
    tables.push(table(tableName, columns, keys, uniques));
  }
  return fromCatalog({
    schemas: profile.composite ? ["public", "graphql_public"] : ["public"],
    tables,
    enums: [],
    functions: profile.composite ? [GRAPHQL] : [],
    buckets: [],
    realtime: [],
  });
}

function consumer(profile: Profile): string {
  const lines = [
    "import type { SupabaseClient } from '@supabase/supabase-js';",
    "import { defineSupabase } from 'better-supabase';",
    "import { softDelete } from 'better-supabase/plugins/soft-delete';",
    "import { tenant } from 'better-supabase/plugins/tenant';",
    "import { timestamps } from 'better-supabase/plugins/timestamps';",
    "import { schema } from './generated.ts';",
    "declare const client: SupabaseClient;",
    "const db = defineSupabase(schema).use(timestamps()).use(softDelete()).use(tenant()).connect(client);",
    "export async function run(): Promise<unknown[]> {",
    "  return [",
  ];
  for (let i = 1; i <= profile.queried; i++) {
    const key = name(i);
    const child = name(i + 1);
    lines.push(
      `    await db.${key}.findMany({ select: ['id', 'name', 'createdAt'], where: { active: true, quantity: { gt: 1 } }, orderBy: { createdAt: 'desc' }, include: { parent: { select: ['id', 'name'] }, ${child}: { select: ['id'] } } }).orThrow(),`,
      `    await db.${key}.create({ organizationId: 'o', name: 'n' }, { select: ['id'] }).orThrow(),`,
      `    await db.${key}.update('id', { name: 'x' }).orThrow(),`,
    );
  }
  lines.push("  ];", "}", "");
  return lines.join("\n");
}

function measure(): Measurement & { checkTime: string } {
  const result = spawnSync(
    process.execPath,
    [tsc, "-p", join(work, "tsconfig.json"), "--extendedDiagnostics"],
    {
      encoding: "utf8",
    },
  );
  const output = `${result.stdout}${result.stderr}`;
  if (result.status !== 0) {
    throw new Error(`tsc failed on the benchmark schema:\n${output}`);
  }
  const read = (label: string): string => {
    const match = new RegExp(`^${label}:\\s+(\\S+)`, "m").exec(output);
    if (!match?.[1]) throw new Error(`tsc output has no "${label}" line`);
    return match[1];
  };
  return {
    types: Number(read("Types")),
    instantiations: Number(read("Instantiations")),
    checkTime: read("Check time"),
  };
}

function run(profile: Profile): Measurement & {
  checkTime: string;
  genTime: string;
} {
  rmSync(work, { recursive: true, force: true });
  mkdirSync(work, { recursive: true });
  writeFileSync(join(work, "snapshot.json"), JSON.stringify(snapshot(profile)));
  writeFileSync(
    join(work, "better-supabase.config.json"),
    JSON.stringify({
      source: { snapshot: "snapshot.json" },
      ...(profile.composite ? { schemas: ["public", "graphql_public"] } : {}),
      casing: "camel",
      output: "generated.ts",
      plugins: {
        timestamps: true,
        softDelete: { column: "archived_at" },
        tenant: { column: "organization_id" },
      },
    }),
  );
  writeFileSync(join(work, "consumer.ts"), consumer(profile));
  writeFileSync(
    join(work, "tsconfig.json"),
    JSON.stringify({
      compilerOptions: {
        strict: true,
        exactOptionalPropertyTypes: true,
        module: "nodenext",
        moduleResolution: "nodenext",
        target: "es2024",
        lib: ["ES2024", "DOM"],
        types: [],
        allowImportingTsExtensions: true,
        skipLibCheck: true,
        noEmit: true,
      },
      files: ["consumer.ts"],
    }),
  );
  const started = performance.now();
  execFileSync(process.execPath, [cli, "gen", "--cwd", work], {
    stdio: "pipe",
  });
  const genTime = `${((performance.now() - started) / 1000).toFixed(2)}s`;
  return { ...measure(), genTime };
}

const baselinePath = join(here, "baseline.json");
const update = process.env["BENCH_UPDATE"] === "1";
// SAFETY: this script writes the baseline file in the Baseline shape.
const baseline = JSON.parse(readFileSync(baselinePath, "utf8")) as Baseline;
const next: Record<string, BaselineEntry> = {};

for (const [profileName, profile] of Object.entries(PROFILES)) {
  const current = run(profile);
  const summary = `${profileName}: ${String(profile.tables)} tables, ${String(profile.queried)} queried: ${String(current.instantiations)} instantiations, ${String(current.types)} types, gen ${current.genTime}, check ${current.checkTime}`;
  next[profileName] = {
    ...profile,
    measurement: {
      types: current.types,
      instantiations: current.instantiations,
    },
  };
  console.log(summary);
  if (update) continue;
  const previous = baseline[profileName];
  if (!previous) {
    console.error(
      `${profileName} has no baseline. Run \`pnpm --filter @better-supabase/types-perf update\`.`,
    );
    process.exitCode = 1;
    continue;
  }
  for (const metric of ["instantiations", "types"] as const) {
    if (current[metric] <= previous.measurement[metric] * (1 + TOLERANCE))
      continue;
    console.error(
      `${profileName}: ${metric} grew from ${String(previous.measurement[metric])} to ${String(current[metric])} (tolerance ${String(TOLERANCE * 100)}%). Run \`pnpm --filter @better-supabase/types-perf update\` if the growth is intended.`,
    );
    process.exitCode = 1;
  }
}

if (update) {
  writeFileSync(baselinePath, `${JSON.stringify(next, null, 2)}\n`);
  console.log("baseline updated");
}
