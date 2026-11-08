import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import type { Generator, GeneratorInput } from "../../../src/config/index.ts";

import { setCacheEnabled } from "../../../src/cli/cache/store.ts";
import { runGenerators } from "../../../src/cli/generators/run.ts";
import { defineGenerator } from "../../../src/generators/kit.ts";

const pool = vi.hoisted(() => ({ calls: 0 }));

vi.mock(import("../../../src/cli/generators/pool.ts"), () => ({
  PoolError: Error,
  runInWorkers: (jobs: readonly { readonly id: number }[]) => {
    pool.calls += 1;

    return Promise.resolve(
      jobs.map((job) => ({
        ok: true,
        files: [{ path: `pool/${String(job.id)}.txt`, contents: "pooled" }],
      })),
    );
  },
}));

let root = "";

beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), "bsb-pool-gate-"));
  setCacheEnabled(false);
  pool.calls = 0;
});

afterEach(async () => {
  await rm(root, { recursive: true, force: true });
});

const input = (tables: number): GeneratorInput =>
  ({
    meta: {
      tables: Object.fromEntries(
        Array.from({ length: tables }, (_, index) => [`t${String(index)}`, {}]),
      ),
    },
  }) as unknown as GeneratorInput;

const generator = (name: string, workerSafe = true): Generator =>
  defineGenerator({
    name,
    version: "1",
    workerSafe,
    ...(workerSafe
      ? { module: { specifier: "file:///unused.js", export: "unused" } }
      : {}),
    generate: () => [{ path: `main/${name}.txt`, contents: "main" }],
  });

const run = (
  generators: readonly Generator[],
  tables: number,
  extra: { workerMinTables?: number } = {},
) =>
  runGenerators(generators, input(tables), {
    root,
    taken: new Set<string>(),
    workers: 2,
    ...extra,
  });

describe("when generators go to the pool", () => {
  it("uses it for two or more eligible generators on a large schema", async () => {
    const result = await run([generator("a"), generator("b")], 5, {
      workerMinTables: 5,
    });

    expect(pool.calls).toBe(1);
    expect(result.files.map((entry) => entry.file.path)).toEqual([
      "pool/0.txt",
      "pool/1.txt",
    ]);
  });

  it("keeps a schema below the table threshold on the main thread", async () => {
    const result = await run([generator("a"), generator("b")], 4, {
      workerMinTables: 5,
    });

    expect(pool.calls).toBe(0);
    expect(result.files.map((entry) => entry.file.path)).toEqual([
      "main/a.txt",
      "main/b.txt",
    ]);
  });

  it("keeps the default threshold at a size apps do not reach", async () => {
    await run([generator("a"), generator("b")], 400);

    expect(pool.calls).toBe(0);
  });

  it("keeps a lone eligible generator on the main thread", async () => {
    await run([generator("a"), generator("closure", false)], 9, {
      workerMinTables: 0,
    });

    expect(pool.calls).toBe(0);
  });

  it("keeps everything on the main thread with zero workers", async () => {
    await runGenerators([generator("a"), generator("b")], input(9), {
      root,
      taken: new Set<string>(),
      workers: 0,
      workerMinTables: 0,
    });

    expect(pool.calls).toBe(0);
  });
});
