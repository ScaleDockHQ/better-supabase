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

import type { Profile } from "./programs.ts";
import type { RuntimeTimes } from "./runtime.ts";

import {
  calibrationProgram,
  configProgram,
  consumer,
  name,
  serverProgram,
  snapshot,
} from "./programs.ts";
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
  /** After one column is added to a table a block owns (ADR 0591). */
  readonly ownedColumn: UpgradeRun;
  /** `upgrade --check`, which renders like `upgrade` and writes nothing. */
  readonly check: CheckTimes;
}

/** Seconds for `upgrade --check` on the CentraKit fixture. */
interface CheckTimes {
  /** With the render caches purged. */
  readonly cold: number;
  /** Again with nothing changed. */
  readonly warm: number;
  /** After one column is added to a table a block owns. */
  readonly ownedColumn: number;
}

const PROFILES = {
  default: { tables: 150, queried: 40, composite: false },
  centrakit: { tables: 250, queried: 40, composite: true },
  // Nearer CentraKit's size: the real app checks at 346,000 to 405,000 types
  // (ADR 0591), the 250 table profile at about 28,000 and this one at about
  // 126,000 with ts7. It shows how the cost grows with the schema.
  real: { tables: 1200, queried: 240, composite: true },
} satisfies Readonly<Record<string, Profile>>;

const TOLERANCE = 0.1;

/** Runs per tsc measurement; the check time is the smallest. */
const CHECK_RUNS = 3;

/**
 * Check time fails only past twice the baseline and at least half a second
 * more, after scaling the baseline by how much slower this machine checks the
 * calibration program.
 */
const TIME_FACTOR = 2;
const TIME_SLACK = 0.5;

/**
 * A program whose check time is not above this many times the calibration
 * program's is too small to gate on time. The native compilers check the
 * calibration program in about 20 ms, so a factor above 1 fails under load.
 */
const FLOOR_FACTOR = 1;

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

/**
 * One tsc run. The counts are exact. The check time is the smallest of `runs`
 * runs: a program this small checks in tens of milliseconds, so a single run is
 * mostly noise.
 */
function measure(
  tsc: string,
  flags: readonly string[] = [],
  project = join(work, "tsconfig.json"),
  runs = CHECK_RUNS,
): Measurement {
  const once = (): Measurement => {
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
  };

  const first = once();
  let best = first.checkTime;

  for (let run = 1; run < runs; run += 1) {
    best = Math.min(best, once().checkTime);
  }

  return { ...first, checkTime: best };
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

  const measured = {
    ts6: measure(compilers.ts6, [], project),
    ts7: measure(compilers.ts7, [], project),
    ts71: measure(compilers.ts71, [], project),
  } satisfies Readonly<Record<Compiler, Measurement>>;

  for (const compiler of ["ts6", "ts7", "ts71"] as const) {
    if (measured[compiler].checkTime <= calibration[compiler] * FLOOR_FACTOR) {
      console.error(
        `server program (${compiler}): check time ${measured[compiler].checkTime.toFixed(3)}s is not above the calibration program's ${calibration[compiler].toFixed(3)}s, so a time gate on it measures noise. Add queries to serverProgram.`,
      );
      process.exitCode = 1;
    }
  }

  return measured;
}

function run(profile: Profile): Run {
  rmSync(work, { recursive: true, force: true });
  mkdirSync(work, { recursive: true });
  writeFileSync(join(work, "snapshot.json"), JSON.stringify(snapshot(profile)));
  writeConfig(profile, false);
  writeFileSync(join(work, "consumer.ts"), consumer(profile));
  writeTsconfig(false);
  const cold = gen();

  const ts71 = timed(() => measure(compilers.ts71, [], undefined, 1));

  const measurement = {
    ts6: measure(compilers.ts6),
    ts7: measure(compilers.ts7),
    ts71: measure(compilers.ts71),
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
    measure(compilers.ts71, ["--runExternalCode"], undefined, 1);

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
    `  server program: ${(["ts6", "ts7", "ts71"] as const).map((compiler) => `${compiler} ${String(current.server[compiler].instantiations)} instantiations, ${String(current.server[compiler].types)} types, check ${current.server[compiler].checkTime.toFixed(3)}s`).join("; ")}`,
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

    const speed = Math.max(
      1,
      calibration[compiler] / baseline.calibration[compiler],
    );

    const expected = before[compiler].checkTime * speed;
    const limit = Math.max(expected * TIME_FACTOR, expected + TIME_SLACK);

    if (now[compiler].checkTime > limit) {
      console.error(
        `${profileName} server (${compiler}): check time grew from ${expected.toFixed(2)}s to ${now[compiler].checkTime.toFixed(2)}s (limit ${limit.toFixed(2)}s).`,
      );
      process.exitCode = 1;
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

  // A column on a table a block owns changes `layout.ownColumns`. `ctx.has`
  // reads the column list of each owned table a module asks about, and
  // data-lifecycle asks about all of them, so this case re-renders more than
  // the one module that owns the table (ADR 0591).
  const addOwnedColumn = (column: string): void => {
    writeFileSync(
      app,
      `${readFileSync(app, "utf-8")}\nalter table centrakit.teams add column ${column} text;\n`,
    );
  };

  addOwnedColumn("bench_first");
  const ownedColumn = upgradeRun(directory);

  const check = (): number => {
    const started = performance.now();

    const result = spawnSync(
      process.execPath,
      [cli, "upgrade", "--check", "--cwd", directory, "--agent", "no"],
      { encoding: "utf-8" },
    );

    // 1 means the check found pending changes, which is what a stale tree gives.
    if (result.status !== 0 && result.status !== 1) {
      throw new Error(`upgrade --check failed: ${result.stderr}`);
    }

    return Number(((performance.now() - started) / 1000).toFixed(2));
  };

  execFileSync(process.execPath, [cli, "cache", "purge", "--cwd", directory], {
    stdio: "pipe",
  });

  const checkCold = check();
  const checkWarm = check();
  addOwnedColumn("bench_second");
  const checkOwnedColumn = check();

  if (process.env["BENCH_KEEP"] !== "1") {
    rmSync(directory, { recursive: true, force: true });
  }

  return {
    cold,
    warm,
    edit,
    audit,
    ownedColumn,
    check: { cold: checkCold, warm: checkWarm, ownedColumn: checkOwnedColumn },
  };
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

  for (const phase of [
    "cold",
    "warm",
    "edit",
    "audit",
    "ownedColumn",
  ] as const) {
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

  const checkBefore = before.check;

  for (const phase of ["cold", "warm", "ownedColumn"] as const) {
    const expected = checkBefore[phase] * speed;
    const limit = Math.max(expected * TIME_FACTOR, expected + TIME_SLACK);

    if (now.check[phase] > limit) {
      console.error(
        `upgrade --check ${phase} grew from ${expected.toFixed(2)}s to ${now.check[phase].toFixed(2)}s (limit ${limit.toFixed(2)}s).`,
      );
      process.exitCode = 1;
    }
  }
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
  `upgrade (centrakit): cold ${upgradeNow.cold.seconds.toFixed(2)}s (${String(upgradeNow.cold.rendered)} rendered, ${String(upgradeNow.cold.written)} written), warm ${upgradeNow.warm.seconds.toFixed(2)}s (${String(upgradeNow.warm.rendered)} rendered, ${String(upgradeNow.warm.written)} written), edit ${upgradeNow.edit.seconds.toFixed(2)}s (${String(upgradeNow.edit.rendered)} rendered, ${String(upgradeNow.edit.written)} written), audit ${upgradeNow.audit.seconds.toFixed(2)}s (${String(upgradeNow.audit.rendered)} rendered, ${String(upgradeNow.audit.written)} written), owned column ${upgradeNow.ownedColumn.seconds.toFixed(2)}s (${String(upgradeNow.ownedColumn.rendered)} rendered, ${String(upgradeNow.ownedColumn.written)} written)`,
);

console.log(
  `upgrade --check (centrakit): cold ${upgradeNow.check.cold.toFixed(2)}s, warm ${upgradeNow.check.warm.toFixed(2)}s, owned column ${upgradeNow.check.ownedColumn.toFixed(2)}s`,
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
