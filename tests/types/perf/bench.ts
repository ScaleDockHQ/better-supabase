import type {
  CatalogColumn,
  CatalogForeignKey,
  CatalogFunction,
  CatalogTable,
  CatalogUnique,
  Snapshot,
} from "better-supabase/cli";

import { fromCatalog } from "better-supabase/cli";
import { execFileSync, spawnSync } from "node:child_process";
import {
  cpSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";

import type { RuntimeTimes } from "./runtime.ts";

import { benchRuntime, checkRuntime } from "./runtime.ts";

interface Measurement {
  readonly types: number;
  readonly instantiations: number;
  /** Seconds; machine-dependent, so gated loosely. */
  readonly checkTime: number;
}

type Compiler = "ts6" | "ts7" | "ts71";

/**
 * Each compiler on the generated files, plus TypeScript 7.1 through the content
 * mapper.
 */
type Mode = Compiler | "ts71Mapper";

const MODES = ["ts6", "ts7", "ts71", "ts71Mapper"] as const;

interface Profile {
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

interface BaselineEntry extends Profile {
  readonly measurement: Readonly<Record<Mode, Measurement>>;
  readonly gen?: GenTimes;
  readonly mapper?: MapperTimes;
  /** The server program over the profile's schema (ADR 0450). */
  readonly server?: Readonly<Record<Compiler, Measurement>>;
}

interface Baseline {
  /**
   * Check time of the calibration program on the machine that wrote the
   * baseline.
   */
  readonly calibration: Readonly<Record<Compiler, number>>;
  readonly profiles: Readonly<Record<string, BaselineEntry>>;
  /** `upgrade` on the CentraKit fixture, by case (ADR 0247). */
  readonly upgrade?: UpgradeTimes;
  /** The config program typed against a provider key union (ADR 0323). */
  readonly config?: Readonly<Record<Compiler, Measurement>>;
  /** `AsyncResult` against a bare promise chain, at run time (ADR 0581). */
  readonly runtime?: RuntimeTimes;
}

/** What one `upgrade` run did. */
interface UpgradeRun {
  /** Seconds; machine-dependent, so gated loosely. */
  readonly seconds: number;
  /** Modules (and their data and test files) the run rendered. */
  readonly rendered: number;
  /** Files whose content changed on disk. */
  readonly written: number;
}

/** The three cases of Part 7. */
interface UpgradeTimes {
  /** A tree with no module files. */
  readonly cold: UpgradeRun;
  /** Again with nothing changed. */
  readonly warm: UpgradeRun;
  /** After one check is added to an app file. */
  readonly edit: UpgradeRun;
  /** After the app file registers one more audited table (ADR 0362). */
  readonly audit: UpgradeRun;
}

const PROFILES = {
  default: { tables: 150, queried: 40, composite: false },
  centrakit: { tables: 250, queried: 40, composite: true },
} satisfies Readonly<Record<string, Profile>>;

const TOLERANCE = 0.1;

/**
 * Check time fails only past twice the baseline and at least half a second
 * more, after scaling the baseline by how much slower this machine checks the
 * calibration program.
 */
const TIME_FACTOR = 2;
const TIME_SLACK = 0.5;

const here = import.meta.dirname;
const work = join(here, "tmp");
const require = createRequire(import.meta.url);

const tscFrom = (resolve: (id: string) => string): string =>
  join(dirname(resolve("typescript/package.json")), "bin", "tsc");

const compilers = {
  ts6: tscFrom(require.resolve),
  ts7: tscFrom(createRequire(join(here, "../ts-7/package.json")).resolve),
  ts71: tscFrom(createRequire(join(here, "../ts-7.1/package.json")).resolve),
} satisfies Readonly<Record<Compiler, string>>;

const cli = join(
  dirname(require.resolve("better-supabase/package.json")),
  "bin",
  "better-supabase.js",
);

const name = (i: number): string => `t${String(i).padStart(3, "0")}`;

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
function snapshot(profile: Profile, extraColumnOn?: string): Snapshot {
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
function consumer(profile: Profile, database = "./database.types.ts"): string {
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
function calibrationProgram(): string {
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

function calibrate() {
  rmSync(work, { recursive: true, force: true });
  mkdirSync(work, { recursive: true });
  writeFileSync(join(work, "calibration.ts"), calibrationProgram());
  writeFileSync(
    join(work, "tsconfig.json"),
    JSON.stringify({
      compilerOptions: {
        strict: true,
        types: [],
        noEmit: true,
        lib: ["ES2024"],
      },
      files: ["calibration.ts"],
    }),
  );

  return {
    ts6: measure(compilers.ts6).checkTime,
    ts7: measure(compilers.ts7).checkTime,
    ts71: measure(compilers.ts71).checkTime,
  } satisfies Readonly<Record<Compiler, number>>;
}

function measure(
  tsc: string,
  flags: readonly string[] = [],
  project = join(work, "tsconfig.json"),
): Measurement {
  const result = spawnSync(
    process.execPath,
    [tsc, "-p", project, "--extendedDiagnostics", ...flags],
    { encoding: "utf-8" },
  );

  const output = `${result.stdout}${result.stderr}`;

  if (result.status !== 0) {
    throw new Error(`tsc failed on the benchmark schema:\n${output}`);
  }

  const read = (label: string): string => {
    const match = new RegExp(`^${label}:\\s+(\\S+)`, "m").exec(output);

    if (!match?.[1]) {
      throw new Error(`tsc output has no "${label}" line`);
    }

    return match[1];
  };

  return {
    types: Number(read("Types")),
    instantiations: Number(read("Instantiations")),
    checkTime: Number(read("Check time").replace(/s$/, "")),
  };
}

/** Seconds for `better-supabase gen`; machine-dependent, so gated loosely. */
interface GenTimes {
  /** A fresh directory with no generated files. */
  readonly cold: number;
  /** Again with nothing changed. */
  readonly warm: number;
  /** After one column is added to one table. */
  readonly incremental: number;
}

/**
 * Seconds for `tsc --runExternalCode` in mapper mode, start to finish:
 * machine-dependent, so gated loosely.
 */
interface MapperTimes {
  /** TypeScript 7.1 on the generated files, for comparison. */
  readonly files: number;
  /** The mapper renders the types with an empty cache. */
  readonly cold: number;
  /** Again with nothing changed: the mapper reads the cached types. */
  readonly warm: number;
  /** After one column is added to one table, with no `gen` in between. */
  readonly incremental: number;
}

interface Run {
  readonly measurement: Readonly<Record<Mode, Measurement>>;
  readonly gen: GenTimes;
  readonly mapper: MapperTimes;
  readonly server: Readonly<Record<Compiler, Measurement>>;
}

interface Timed<T> {
  readonly value: T;
  readonly seconds: number;
}

function timed<T>(task: () => T): Timed<T> {
  const started = performance.now();
  const value = task();

  return {
    value,
    seconds: Number(((performance.now() - started) / 1000).toFixed(2)),
  };
}

function gen(): number {
  const started = performance.now();
  execFileSync(process.execPath, [cli, "gen", "--cwd", work], {
    stdio: "pipe",
  });

  return Number(((performance.now() - started) / 1000).toFixed(2));
}

function writeConfig(profile: Profile, contentMapper: boolean): void {
  writeFileSync(
    join(work, "better-supabase.config.json"),
    JSON.stringify({
      database: {
        source: { snapshot: "snapshot.json" },
        schemas: profile.composite ? ["public", "graphql_public"] : undefined,
      },
      gen: {
        casing: "camel",
        file: "generated.ts",
        // The benchmark measures one schema object, so its baselines hold.
        tableModules: false,
        blockModules: false,
        tasks: ["types"],
        contentMapper: contentMapper || undefined,
        json: profile.composite
          ? { [`${name(1)}.metadata`]: { type: "{ tags: string[] }" } }
          : undefined,
      },
      auth: { tenant: { column: "organization_id" } },
      blocks: {
        "updated-at": {},
        trash: { options: { deletedAt: "archived_at" } },
      },
    }),
  );
}

function writeTsconfig(contentMapper: boolean): void {
  writeFileSync(
    join(work, "tsconfig.json"),
    JSON.stringify({
      contentMappers: contentMapper
        ? [{ package: "better-supabase", extensions: [".bsb"] }]
        : undefined,
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
}

/**
 * The server's program: `createServer` over the generated schema, a context per
 * request and reads through `ctx.db`. It has its own gate so a change to the
 * server types (ADR 0450) cannot hide in the client program's numbers.
 */
function serverProgram(profile: Profile): string {
  const lines = [
    "import { createSupabase } from 'better-supabase';",
    "import { createServer } from 'better-supabase/server';",
    "import { schema } from './generated.ts';",
    "const server = createServer(createSupabase(schema), { env: { SUPABASE_URL: 'https://x.supabase.co', SUPABASE_PUBLISHABLE_KEY: 'key' } });",
    "export async function run(request: Request): Promise<void> {",
    "  const ctx = await server.context(request);",
  ];

  for (let i = 1; i <= profile.queried; i += 1) {
    lines.push(
      `  await ctx.db.${name(i)}.list({ select: ['id', 'name'], where: { active: true } }).orThrow();`,
      `  await ctx.db.${name(i)}.create({ organizationId: 'o', name: 'n' }, { select: ['id'] }).orThrow();`,
    );
  }

  lines.push("}", "");

  return lines.join("\n");
}

function benchServer(
  profile: Profile,
): Readonly<Record<Compiler, Measurement>> {
  writeFileSync(join(work, "server.ts"), serverProgram(profile));
  writeFileSync(
    join(work, "tsconfig.server.json"),
    JSON.stringify({
      extends: "./tsconfig.json",
      compilerOptions: { lib: ["ES2024", "DOM"] },
      files: ["server.ts"],
    }),
  );

  const project = join(work, "tsconfig.server.json");

  return {
    ts6: measure(compilers.ts6, [], project),
    ts7: measure(compilers.ts7, [], project),
    ts71: measure(compilers.ts71, [], project),
  };
}

function run(profile: Profile): Run {
  rmSync(work, { recursive: true, force: true });
  mkdirSync(work, { recursive: true });
  writeFileSync(join(work, "snapshot.json"), JSON.stringify(snapshot(profile)));
  writeConfig(profile, false);
  writeFileSync(join(work, "consumer.ts"), consumer(profile));
  writeTsconfig(false);
  const cold = gen();

  const ts71 = timed(() => measure(compilers.ts71));

  const measurement = {
    ts6: measure(compilers.ts6),
    ts7: measure(compilers.ts7),
    ts71: ts71.value,
  };

  const server = benchServer(profile);

  const warm = gen();
  writeFileSync(
    join(work, "snapshot.json"),
    JSON.stringify(snapshot(profile, name(1))),
  );
  const incremental = gen();

  writeFileSync(join(work, "snapshot.json"), JSON.stringify(snapshot(profile)));
  writeConfig(profile, true);
  writeFileSync(join(work, "consumer.ts"), consumer(profile, "./generated.ts"));
  writeTsconfig(true);
  gen();
  rmSync(join(work, "node_modules/.cache"), { recursive: true, force: true });

  const mapped = (): Measurement =>
    measure(compilers.ts71, ["--runExternalCode"]);

  const mapperCold = timed(mapped);
  const mapperWarm = timed(mapped);
  writeFileSync(
    join(work, "snapshot.json"),
    JSON.stringify(snapshot(profile, name(1))),
  );
  const mapperIncremental = timed(mapped);

  return {
    measurement: { ...measurement, ts71Mapper: mapperWarm.value },
    gen: { cold, warm, incremental },
    server,
    mapper: {
      files: ts71.seconds,
      cold: mapperCold.seconds,
      warm: mapperWarm.seconds,
      incremental: mapperIncremental.seconds,
    },
  };
}

const baselinePath = join(here, "baseline.json");
const update = process.env["BENCH_UPDATE"] === "1";

// SAFETY: this script writes the baseline file in the Baseline shape.
const baseline = JSON.parse(readFileSync(baselinePath, "utf-8")) as Baseline;
const next: Record<string, BaselineEntry> = {};
const calibration = calibrate();

console.log(
  `calibration: ts6 ${calibration.ts6.toFixed(2)}s, ts7 ${calibration.ts7.toFixed(2)}s, ts71 ${calibration.ts71.toFixed(2)}s`,
);

const compilerOf = (mode: Mode): Compiler =>
  mode === "ts71Mapper" ? "ts71" : mode;

const describe = (measurement: Measurement): string =>
  `${String(measurement.instantiations)} instantiations, ${String(measurement.types)} types, check ${measurement.checkTime.toFixed(2)}s`;

// `BENCH_ONLY=upgrade` skips the type profiles, for work on the generator alone.
const only = process.env["BENCH_ONLY"];

for (const [profileName, profile] of Object.entries(
  only === "upgrade" ? {} : PROFILES,
)) {
  const current = run(profile);
  next[profileName] = {
    ...profile,
    measurement: current.measurement,
    gen: current.gen,
    mapper: current.mapper,
    server: current.server,
  };
  console.log(
    `${profileName}: ${String(profile.tables)} tables, ${String(profile.queried)} queried, gen cold ${current.gen.cold.toFixed(2)}s, warm ${current.gen.warm.toFixed(2)}s, incremental ${current.gen.incremental.toFixed(2)}s`,
  );

  for (const mode of MODES) {
    console.log(`  ${mode}: ${describe(current.measurement[mode])}`);
  }

  console.log(
    `  server program: ${(["ts6", "ts7", "ts71"] as const).map((compiler) => `${compiler} ${String(current.server[compiler].instantiations)} instantiations, ${String(current.server[compiler].types)} types`).join("; ")}`,
  );

  console.log(
    `  ts71 tsc: files ${current.mapper.files.toFixed(2)}s, mapper cold ${current.mapper.cold.toFixed(2)}s, warm ${current.mapper.warm.toFixed(2)}s, incremental ${current.mapper.incremental.toFixed(2)}s`,
  );

  if (update) {
    continue;
  }

  const previous = baseline.profiles[profileName];

  if (!previous) {
    console.error(
      `${profileName} has no baseline. Run \`pnpm --filter @better-supabase/types-perf update\`.`,
    );
    process.exitCode = 1;
    continue;
  }

  for (const mode of MODES) {
    const compiler = compilerOf(mode);
    const now = current.measurement[mode];
    const before = previous.measurement[mode];

    for (const metric of ["instantiations", "types"] as const) {
      if (now[metric] <= before[metric] * (1 + TOLERANCE)) {
        continue;
      }

      console.error(
        `${profileName} (${mode}): ${metric} grew from ${String(before[metric])} to ${String(now[metric])} (tolerance ${String(TOLERANCE * 100)}%). Run \`pnpm --filter @better-supabase/types-perf update\` if the growth is intended.`,
      );
      process.exitCode = 1;
    }

    const speed = Math.max(
      1,
      calibration[compiler] / baseline.calibration[compiler],
    );

    const expected = before.checkTime * speed;
    const limit = Math.max(expected * TIME_FACTOR, expected + TIME_SLACK);

    if (now.checkTime > limit) {
      console.error(
        `${profileName} (${mode}): check time grew from ${expected.toFixed(2)}s to ${now.checkTime.toFixed(2)}s (limit ${limit.toFixed(2)}s, baseline ${before.checkTime.toFixed(2)}s on a machine ${speed.toFixed(1)}x faster).`,
      );
      process.exitCode = 1;
    }
  }

  checkServer(profileName, current.server, previous.server);
  checkGen(profileName, current.gen, previous.gen);
  checkMapper(profileName, current.mapper, previous.mapper);
}

/** Mapper runs are TypeScript 7.1 runs, so its calibration scales them. */
function checkMapper(
  profileName: string,
  now: MapperTimes,
  before: MapperTimes | undefined,
): void {
  if (!before) {
    console.error(
      `${profileName} has no mapper baseline. Run \`pnpm --filter @better-supabase/types-perf update\`.`,
    );
    process.exitCode = 1;

    return;
  }

  const speed = Math.max(1, calibration.ts71 / baseline.calibration.ts71);

  for (const phase of ["files", "cold", "warm", "incremental"] as const) {
    const expected = before[phase] * speed;
    const limit = Math.max(expected * TIME_FACTOR, expected + TIME_SLACK);

    if (now[phase] <= limit) {
      continue;
    }

    console.error(
      `${profileName}: ${phase} tsc in mapper mode grew from ${expected.toFixed(2)}s to ${now[phase].toFixed(2)}s (limit ${limit.toFixed(2)}s).`,
    );
    process.exitCode = 1;
  }
}

/**
 * Gen runs in Node, so the TypeScript 6 calibration (tsc in JavaScript) is the
 * closer measure of how much slower this machine is.
 */
function checkServer(
  profileName: string,
  now: Readonly<Record<Compiler, Measurement>>,
  before: Readonly<Record<Compiler, Measurement>> | undefined,
): void {
  if (!before) {
    console.error(
      `${profileName} has no server baseline. Run \`pnpm --filter @better-supabase/types-perf update\`.`,
    );
    process.exitCode = 1;

    return;
  }

  for (const compiler of ["ts6", "ts7", "ts71"] as const) {
    for (const metric of ["instantiations", "types"] as const) {
      if (now[compiler][metric] > before[compiler][metric] * (1 + TOLERANCE)) {
        console.error(
          `${profileName} server (${compiler}): ${metric} grew from ${String(before[compiler][metric])} to ${String(now[compiler][metric])} (tolerance ${String(TOLERANCE * 100)}%).`,
        );
        process.exitCode = 1;
      }
    }
  }
}

function checkGen(
  profileName: string,
  now: GenTimes,
  before: GenTimes | undefined,
): void {
  if (!before) {
    console.error(
      `${profileName} has no gen baseline. Run \`pnpm --filter @better-supabase/types-perf update\`.`,
    );
    process.exitCode = 1;

    return;
  }

  const speed = Math.max(1, calibration.ts6 / baseline.calibration.ts6);

  for (const phase of ["cold", "warm", "incremental"] as const) {
    const expected = before[phase] * speed;
    const limit = Math.max(expected * TIME_FACTOR, expected + TIME_SLACK);

    if (now[phase] <= limit) {
      continue;
    }

    console.error(
      `${profileName}: ${phase} gen grew from ${expected.toFixed(2)}s to ${now[phase].toFixed(2)}s (limit ${limit.toFixed(2)}s).`,
    );
    process.exitCode = 1;
  }
}

/**
 * `upgrade` on a copy of the CentraKit fixture: a cold run with no module
 * files, a warm no-op and a run after one edit of an app file. The rendered
 * count comes from the command's own cache report (module files a fresh render
 * produced) and the written count from its receipt, so the render cache shows
 * up as fewer rendered modules, not only as less time.
 */
function upgradeRun(directory: string): UpgradeRun {
  const started = performance.now();

  const result = spawnSync(
    process.execPath,
    [cli, "upgrade", "--cwd", directory, "--agent", "no", "--json"],
    { encoding: "utf-8" },
  );

  const seconds = Number(((performance.now() - started) / 1000).toFixed(2));

  if (result.status !== 0) {
    throw new Error(`upgrade failed: ${result.stderr}`);
  }

  // SAFETY: `upgrade --json` prints the result document with the cache counts.
  const document = JSON.parse(result.stdout) as {
    readonly data: { readonly cache: { readonly rendered: number } };
  };

  const lines = result.stderr
    .split("\n")
    .filter((line) => / \(.+\)$/.test(line));

  return {
    seconds,
    rendered: document.data.cache.rendered,
    written: lines.filter((line) => !line.startsWith("Unchanged ")).length,
  };
}

function benchUpgrade(): UpgradeTimes {
  const fixture = join(here, "../../validation-centrakit");
  const directory = join(work, "upgrade");

  rmSync(directory, { recursive: true, force: true });
  mkdirSync(work, { recursive: true });
  cpSync(fixture, directory, {
    recursive: true,
    filter: (source) => !source.includes("node_modules"),
  });
  symlinkSync(join(fixture, "node_modules"), join(directory, "node_modules"));

  for (const folder of ["schemas", "better-supabase-data", "tests"]) {
    const path = join(directory, "supabase", folder);

    for (const file of readdirSync(path)) {
      if (file.startsWith("900_better_supabase_")) {
        rmSync(join(path, file));
      }
    }
  }

  // The fixture's node_modules is a link into the repo, so its cache outlives a
  // copy; purging it makes the first run cold.
  execFileSync(process.execPath, [cli, "cache", "purge", "--cwd", directory], {
    stdio: "pipe",
  });

  const cold = upgradeRun(directory);

  // The first run's files change what the second one sees (the tables the
  // modules own), so one unmeasured run settles the tree; the warm run after
  // it is a true no-op.
  upgradeRun(directory);
  const warm = upgradeRun(directory);

  const app = join(directory, "supabase", "schemas", "000_centrakit.sql");
  writeFileSync(
    app,
    `${readFileSync(app, "utf-8")}\ncomment on schema centrakit is 'bench';\n`,
  );
  const edit = upgradeRun(directory);

  // One more audited table in an app file changes the layout's
  // `auditedTables`, which only a few modules read: the per-module render cache
  // answers the rest without rendering them again.
  writeFileSync(
    app,
    `${readFileSync(app, "utf-8")}\ncreate table centrakit.bench_note (id uuid primary key);\nselect better_supabase.audit('centrakit.bench_note');\n`,
  );
  const audit = upgradeRun(directory);

  if (process.env["BENCH_KEEP"] !== "1") {
    rmSync(directory, { recursive: true, force: true });
  }

  return { cold, warm, edit, audit };
}

function checkUpgrade(
  now: UpgradeTimes,
  before: UpgradeTimes | undefined,
): void {
  if (!before) {
    console.error(
      "upgrade has no baseline. Run `pnpm --filter @better-supabase/types-perf update`.",
    );
    process.exitCode = 1;

    return;
  }

  const speed = Math.max(1, calibration.ts6 / baseline.calibration.ts6);

  for (const phase of ["cold", "warm", "edit", "audit"] as const) {
    const expected = before[phase].seconds * speed;
    const limit = Math.max(expected * TIME_FACTOR, expected + TIME_SLACK);

    if (now[phase].seconds > limit) {
      console.error(
        `upgrade ${phase} grew from ${expected.toFixed(2)}s to ${now[phase].seconds.toFixed(2)}s (limit ${limit.toFixed(2)}s).`,
      );
      process.exitCode = 1;
    }

    // The counts are exact, and they only shrink: a render cache lowers them.
    for (const count of ["rendered", "written"] as const) {
      if (now[phase][count] > before[phase][count]) {
        console.error(
          `upgrade ${phase}: ${count} grew from ${String(before[phase][count])} to ${String(now[phase][count])}.`,
        );
        process.exitCode = 1;
      }
    }
  }
}

/**
 * A `defineConfig` call typed against a provider with a large key union: 300
 * keys, 40 subjects that name keys, 20 roles that list them and 5 blocks that
 * rename an action. The permission typing is the one change that can grow the
 * config's check time, so it has its own gate (ADR 0323).
 */
function configProgram(): string {
  const keys = Array.from(
    { length: 300 },
    (_, i) => `"res${String(i % 40)}.act${String(i)}"`,
  );

  const key = (i: number): string => keys[i % keys.length]!;

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

function benchConfig(): Readonly<Record<Compiler, Measurement>> {
  const directory = join(work, "config");
  rmSync(directory, { recursive: true, force: true });
  mkdirSync(directory, { recursive: true });
  writeFileSync(join(directory, "config.ts"), configProgram());
  writeFileSync(
    join(directory, "tsconfig.json"),
    JSON.stringify({
      compilerOptions: {
        strict: true,
        exactOptionalPropertyTypes: true,
        module: "nodenext",
        moduleResolution: "nodenext",
        target: "es2024",
        lib: ["ES2024"],
        types: [],
        allowImportingTsExtensions: true,
        skipLibCheck: true,
        noEmit: true,
      },
      files: ["config.ts"],
    }),
  );

  const project = join(directory, "tsconfig.json");

  return {
    ts6: measure(compilers.ts6, [], project),
    ts7: measure(compilers.ts7, [], project),
    ts71: measure(compilers.ts71, [], project),
  };
}

function checkConfig(
  now: Readonly<Record<Compiler, Measurement>>,
  before: Readonly<Record<Compiler, Measurement>> | undefined,
): void {
  if (!before) {
    console.error(
      "config has no baseline. Run `pnpm --filter @better-supabase/types-perf update`.",
    );
    process.exitCode = 1;

    return;
  }

  for (const compiler of ["ts6", "ts7", "ts71"] as const) {
    for (const metric of ["instantiations", "types"] as const) {
      if (now[compiler][metric] > before[compiler][metric] * (1 + TOLERANCE)) {
        console.error(
          `config (${compiler}): ${metric} grew from ${String(before[compiler][metric])} to ${String(now[compiler][metric])} (tolerance ${String(TOLERANCE * 100)}%).`,
        );
        process.exitCode = 1;
      }
    }
  }
}

const upgradeNow = benchUpgrade();

console.log(
  `upgrade (centrakit): cold ${upgradeNow.cold.seconds.toFixed(2)}s (${String(upgradeNow.cold.rendered)} rendered, ${String(upgradeNow.cold.written)} written), warm ${upgradeNow.warm.seconds.toFixed(2)}s (${String(upgradeNow.warm.rendered)} rendered, ${String(upgradeNow.warm.written)} written), edit ${upgradeNow.edit.seconds.toFixed(2)}s (${String(upgradeNow.edit.rendered)} rendered, ${String(upgradeNow.edit.written)} written), audit ${upgradeNow.audit.seconds.toFixed(2)}s (${String(upgradeNow.audit.rendered)} rendered, ${String(upgradeNow.audit.written)} written)`,
);

const configNow = benchConfig();

console.log(
  `config (300 keys): ${(["ts6", "ts7", "ts71"] as const).map((compiler) => `${compiler} ${String(configNow[compiler].instantiations)} instantiations, ${String(configNow[compiler].types)} types`).join("; ")}`,
);

const runtimeNow = await benchRuntime();

console.log(
  `runtime (20000 chains): promise ${runtimeNow.promise.toFixed(2)}us, AsyncResult ${runtimeNow.asyncResult.toFixed(2)}us, ${String(runtimeNow.ratio)}x`,
);

if (!update) {
  checkUpgrade(upgradeNow, baseline.upgrade);
  checkConfig(configNow, baseline.config);

  for (const failure of checkRuntime(
    runtimeNow,
    baseline.runtime,
    Math.max(1, calibration.ts6 / baseline.calibration.ts6),
  )) {
    console.error(failure);
    process.exitCode = 1;
  }
}

if (update && only === undefined) {
  writeFileSync(
    baselinePath,
    `${JSON.stringify(
      {
        calibration,
        profiles: next,
        upgrade: upgradeNow,
        config: configNow,
        runtime: runtimeNow,
      },
      null,
      2,
    )}\n`,
  );
  console.log("baseline updated");
}
