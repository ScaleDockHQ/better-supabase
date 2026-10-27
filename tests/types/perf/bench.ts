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
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";

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
}

interface Baseline {
  /**
   * Check time of the calibration program on the machine that wrote the
   * baseline.
   */
  readonly calibration: Readonly<Record<Compiler, number>>;
  readonly profiles: Readonly<Record<string, BaselineEntry>>;
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
    "import { defineSupabase } from 'better-supabase';",
    "import { membershipsExtension } from 'better-supabase/blocks/memberships';",
    "import { schema } from './generated.ts';",
    "declare const client: SupabaseClient;",
    "const db = defineSupabase(schema).use(membershipsExtension()).connect(client);",
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

function measure(tsc: string, flags: readonly string[] = []): Measurement {
  const result = spawnSync(
    process.execPath,
    [tsc, "-p", join(work, "tsconfig.json"), "--extendedDiagnostics", ...flags],
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
        output: "generated.ts",
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

for (const [profileName, profile] of Object.entries(PROFILES)) {
  const current = run(profile);
  next[profileName] = {
    ...profile,
    measurement: current.measurement,
    gen: current.gen,
    mapper: current.mapper,
  };
  console.log(
    `${profileName}: ${String(profile.tables)} tables, ${String(profile.queried)} queried, gen cold ${current.gen.cold.toFixed(2)}s, warm ${current.gen.warm.toFixed(2)}s, incremental ${current.gen.incremental.toFixed(2)}s`,
  );

  for (const mode of MODES) {
    console.log(`  ${mode}: ${describe(current.measurement[mode])}`);
  }

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

if (update) {
  writeFileSync(
    baselinePath,
    `${JSON.stringify({ calibration, profiles: next }, null, 2)}\n`,
  );
  console.log("baseline updated");
}
