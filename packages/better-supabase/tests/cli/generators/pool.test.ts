import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { Generator, GeneratorInput } from "../../../src/config/index.ts";

import { setCacheEnabled } from "../../../src/cli/cache/store.ts";
import { CliError } from "../../../src/cli/core/errors.ts";
import { runGenerators } from "../../../src/cli/generators/run.ts";
import { factories } from "../../../src/generators/factories/index.ts";
import { jsonSchema } from "../../../src/generators/json-schema/index.ts";
import { nuqs } from "../../../src/generators/nuqs/index.ts";
import { standardSchema } from "../../../src/generators/standard-schema/index.ts";
import { valibot } from "../../../src/generators/valibot/index.ts";
import { zod } from "../../../src/generators/zod/index.ts";
import { testGeneratorPlugin } from "../../../src/testing/generator.ts";
import { schema } from "../../fixtures/generated-camel.ts";
import { delayed } from "./fixtures/delayed.ts";

const fixtureUrl = pathToFileURL(
  join(import.meta.dirname, "fixtures/delayed.ts"),
).href;

const workerModule = new URL(
  "../../../src/cli/generators/worker.ts",
  import.meta.url,
);

// Resolves `better-supabase/generators/*` to the sources, as the package's
// `@better-supabase/source` export condition says.
const execArgv = ["--conditions=@better-supabase/source"];

let root = "";

beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), "bsb-pool-"));
  setCacheEnabled(true);
});

afterEach(async () => {
  await rm(root, { recursive: true, force: true });
});

const input = (): GeneratorInput =>
  ({
    meta: schema.meta,
    introspection: {
      version: 1,
      schemas: [],
      tables: [],
      foreignTables: [],
      views: [],
      materializedViews: [],
      columns: [],
      primaryKeys: [],
      relationships: [],
      functions: [],
      types: [],
    },
    extras: { tables: [], buckets: [], realtime: [] },
    config: {
      output: "src/generated.ts",
      databaseTypesOutput: "src/database.types.ts",
      casing: "camel",
      json: {},
    },
    imports: { runtime: "better-supabase" },
    model: { tables: [], enums: [], functions: [], blocks: [] },
  }) as unknown as GeneratorInput;

/** A fixture generator a worker loads from the fixture file. */
const onWorker = (
  id: string,
  extra: { delay?: number; fail?: string } = {},
): Generator => {
  const options = { id, ...extra };

  return {
    ...delayed(options),
    module: { specifier: fixtureUrl, export: "delayed" },
  };
};

/** The same generator without a module: it stays on the main thread. */
const inThread = (id: string, extra: { delay?: number } = {}): Generator =>
  delayed({ id, ...extra });

const run = (
  generators: readonly Generator[],
  workers: number,
  directory = root,
) =>
  runGenerators(generators, input(), {
    root: directory,
    taken: new Set<string>(),
    workers,
    workerMinTables: 0,
    workerModule,
    execArgv,
  });

describe("runGenerators on worker threads", () => {
  it("gives the files a single thread gives, in config order", async () => {
    const generators = ["a", "b", "c", "d", "e"].map((id) => onWorker(id));
    const single = await mkdtemp(join(tmpdir(), "bsb-pool-single-"));

    try {
      const serial = await run(generators, 0, single);
      const pooled = await run(generators, 3);

      expect(pooled.files).toEqual(serial.files);
      expect(pooled.files.map((entry) => entry.file.path)).toEqual([
        "out/a.json",
        "out/b.json",
        "out/c.json",
        "out/d.json",
        "out/e.json",
      ]);
    } finally {
      await rm(single, { recursive: true, force: true });
    }
  });

  it("keeps config order whatever order the workers finish in", async () => {
    // The first generator is the slowest, so it finishes last.
    const generators = [160, 120, 80, 40, 0].map((delay, index) =>
      onWorker(String(index), { delay }),
    );

    const pooled = await run(generators, 5);

    expect(pooled.files.map((entry) => entry.generator)).toEqual([
      "delayed-0",
      "delayed-1",
      "delayed-2",
      "delayed-3",
      "delayed-4",
    ]);
  });

  it("merges generators that stay on the main thread in config order", async () => {
    const generators = [
      onWorker("a", { delay: 60 }),
      inThread("b"),
      onWorker("c"),
      inThread("d"),
    ];

    const mixed = await run(generators, 2);

    expect(mixed.files.map((entry) => entry.file.path)).toEqual([
      "out/a.json",
      "out/b.json",
      "out/c.json",
      "out/d.json",
    ]);
  });

  it("caches what a worker produced", async () => {
    const generators = [onWorker("a"), onWorker("b")];

    const first = await run(generators, 2);
    const second = await run(generators, 2);

    expect(first.cached).toEqual([]);
    expect(second.cached).toEqual(["delayed-a", "delayed-b"]);
    expect(second.files).toEqual(first.files);
  });

  it("reports the first failing generator in config order", async () => {
    const generators = [
      onWorker("a"),
      onWorker("b", { fail: "second broke", delay: 80 }),
      onWorker("c", { fail: "third broke" }),
    ];

    const failure = await run(generators, 3).catch((cause: unknown) => cause);

    expect(failure).toBeInstanceOf(CliError);
    expect((failure as CliError).message).toBe(
      'generator "delayed-b" failed: second broke',
    );
  });

  it("generates on the main thread when a worker dies", async () => {
    const generators = [onWorker("a"), onWorker("b")];
    const single = await run(generators, 0);
    const dead = await mkdtemp(join(tmpdir(), "bsb-pool-dead-"));

    try {
      const fallback = await runGenerators(generators, input(), {
        root: dead,
        taken: new Set<string>(),
        workers: 2,
        workerMinTables: 0,
        workerModule: new URL("fixtures/crashing-worker.ts", import.meta.url),
      });

      expect(fallback.files).toEqual(single.files);
    } finally {
      await rm(dead, { recursive: true, force: true });
    }
  });

  it("generates on the main thread when the worker can't start", async () => {
    const generators = [onWorker("a"), onWorker("b")];

    const single = await run(generators, 0);

    const broken = await mkdtemp(join(tmpdir(), "bsb-pool-broken-"));

    try {
      const fallback = await runGenerators(generators, input(), {
        root: broken,
        taken: new Set<string>(),
        workers: 2,
        workerMinTables: 0,
        workerModule: new URL("fixtures/missing-worker.ts", import.meta.url),
      });

      expect(fallback.files).toEqual(single.files);
    } finally {
      await rm(broken, { recursive: true, force: true });
    }
  });
});

describe("the built-in generators on worker threads", () => {
  const builtIns = (): Generator[] => [
    zod(),
    valibot({ validators: false }),
    jsonSchema(),
    standardSchema({ validators: false }),
    factories(),
    nuqs(),
  ];

  it("write the bytes the main thread writes", async () => {
    const single = await mkdtemp(join(tmpdir(), "bsb-pool-builtin-"));

    try {
      const serial = await run(builtIns(), 0, single);
      const pooled = await run(builtIns(), 4);

      expect(pooled.files.length).toBeGreaterThanOrEqual(6);
      expect(pooled.files).toEqual(serial.files);
      expect(pooled.capabilities).toEqual(serial.capabilities);
    } finally {
      await rm(single, { recursive: true, force: true });
    }
  }, 60_000);

  it.each(builtIns().map((generator) => [generator.name, generator] as const))(
    "%s declares the module a worker loads",
    async (_name, generator) => {
      expect(generator.workerSafe).toBe(true);
      expect(generator.module?.specifier).toMatch(
        /^better-supabase\/generators\//,
      );

      const report = await testGeneratorPlugin(generator, {
        meta: schema.meta,
      });

      expect(report.checks.every((check) => check.ok)).toBe(true);
      expect(
        report.checks.some((check) => check.name.startsWith("builds again")),
      ).toBe(true);
    },
  );
});
