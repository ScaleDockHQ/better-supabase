import {
  chmod,
  mkdir,
  mkdtemp,
  readFile,
  rm,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import {
  combineResults,
  configuredTasks,
  parseTasks,
  runSteps,
  selectTasks,
  stepInputs,
} from "../../../src/cli/commands/gen-pipeline.ts";
import { run } from "../../../src/cli/core/run.ts";
import { plain } from "../../../src/cli/style.ts";
import {
  type BetterSupabaseConfig,
  resolveConfig,
} from "../../../src/config/index.ts";

let root = "";

beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), "better-supabase-pipeline-"));
});

afterEach(async () => {
  await rm(root, { recursive: true, force: true });
});

const resolved = (config: BetterSupabaseConfig = {}) =>
  resolveConfig(config, root);

const touch = async (path: string): Promise<void> => {
  await mkdir(join(root, path, ".."), { recursive: true });
  await writeFile(join(root, path), "export {};\n");
};

describe("gen tasks", () => {
  it("runs only types for a config that sets nothing else up", () => {
    expect(configuredTasks(resolved())).toEqual(["types"]);
  });

  it("adds every task the config sets up, never env", async () => {
    await touch("src/lib/openapi.ts");
    await touch("supabase/seed.ts");
    expect(
      configuredTasks(
        resolved({
          blocks: ["audit"],
          scaffold: { api: { framework: "hono" } },
        }),
      ),
    ).toEqual(["types", "sql", "spec", "seed", "scaffold"]);
  });

  it("counts realtime.policies as SQL to sync", () => {
    expect(
      configuredTasks(
        resolved({
          realtime: {
            policies: {
              from: ["src/lib/topics.ts"],
              output: "supabase/schemas/905_topics.sql",
            },
          },
        }),
      ),
    ).toContain("sql");
  });

  it("prefers --tasks, then gen.tasks, and keeps the pipeline order", () => {
    const config = resolved({ gen: { tasks: ["env", "types"] } });
    expect(selectTasks(config, undefined)).toEqual(["types", "env"]);
    expect(selectTasks(config, ["seed", "sql", "sql"])).toEqual([
      "sql",
      "seed",
    ]);
  });

  it("rejects an unknown task", () => {
    expect(parseTasks(["types", "lint"])).toBe(
      'Unknown gen task "lint". Available: types, sql, spec, seed, scaffold, env.',
    );
  });

  it("watches the spec entry, its overlays and the seed entry", () => {
    const config = resolved({
      specs: {
        entry: "src/api.ts",
        outputs: [{ format: "openapi", overlays: ["overlay.yaml"] }],
      },
    });

    expect(
      stepInputs(config, ["types", "sql", "spec", "seed", "scaffold", "env"]),
    ).toEqual([
      join(root, "src/api.ts"),
      join(root, "overlay.yaml"),
      join(root, "supabase/seed.ts"),
    ]);
  });
});

describe("gen steps", () => {
  const steps = (check: boolean) =>
    runSteps(["types", "seed", "env"], {
      config: resolved(),
      env: {},
      check,
      paint: plain,
    });

  it("stops a write run at the first failing step", async () => {
    const results = await steps(false);
    expect(results.map(({ task }) => task)).toEqual(["seed"]);
    expect(results[0]?.result.code).toBe(1);
    expect(results[0]?.result.error).toContain("Module not found");
  });

  it("runs every step under --check and leaves env out", async () => {
    const results = await steps(true);
    expect(results.map(({ task }) => task)).toEqual(["seed", "env"]);
    expect(results[1]?.result).toEqual({
      code: 0,
      output: "Skipped: env writes local keys, so --check leaves it out.",
    });
  });

  it("returns one task's result unchanged", () => {
    const result = { code: 0, output: "Created a.ts", data: { a: 1 } };
    expect(combineResults([{ task: "types", result }])).toBe(result);
  });

  it("gives several tasks a section each and the first failing code", () => {
    expect(
      combineResults([
        {
          task: "types",
          result: { code: 0, output: "Created a.ts\nCreated b.ts" },
        },
        { task: "sql", result: { code: 0 } },
        { task: "seed", result: { code: 1, error: "no seed" } },
      ]),
    ).toEqual({
      code: 1,
      output:
        "[types]\n  Created a.ts\n  Created b.ts\n[sql] done\n[seed] done",
      error: "[seed] no seed",
      data: {
        tasks: { types: { code: 0 }, sql: { code: 0 }, seed: { code: 1 } },
      },
    });
  });
});

describe("gen sql and env steps", () => {
  it("syncs SQL and writes the env file from supabase status", async () => {
    const bin = join(root, "fake-supabase");
    await writeFile(
      bin,
      `#!/bin/sh\necho '${JSON.stringify({ API_URL: "http://127.0.0.1:54321", PUBLISHABLE_KEY: "sb_publishable_test" })}'\n`,
    );
    await chmod(bin, 0o755);

    const results = await runSteps(["sql", "env"], {
      config: resolved({ env: { output: ".env.test", prefix: "VITE_" } }),
      env: { SUPABASE_BIN: bin },
      check: false,
      paint: plain,
    });

    expect(results.map(({ task, result }) => [task, result.code])).toEqual([
      ["sql", 0],
      ["env", 0],
    ]);
    expect(await readFile(join(root, ".env.test"), "utf-8")).toContain(
      "VITE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_test",
    );
  });
});

describe("gen spec step", () => {
  it("emits the spec from the configured entry and reports its errors", async () => {
    const [step] = await runSteps(["spec"], {
      config: resolved({ specs: { entry: "src/missing.ts" } }),
      env: {},
      check: false,
      paint: plain,
    });

    expect(step?.task).toBe("spec");
    expect(step?.result.code).not.toBe(0);
  });
});

describe("gen --only", () => {
  it("refuses an empty task list", async () => {
    const result = await run(["gen", "--only", "", "--cwd", root]);
    expect(result.code).toBe(2);
    expect(result.stderr).toContain("--only names no task.");
  });

  it("rejects an unknown task before reading the schema", async () => {
    const result = await run(["gen", "--only", "lint", "--cwd", root]);
    expect(result.code).toBe(2);
    expect(result.stderr).toContain('Unknown gen task "lint"');
  });
});
