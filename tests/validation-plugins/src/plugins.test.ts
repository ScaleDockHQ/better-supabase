import type { Snapshot } from "better-supabase/cli";
import type { GeneratedFile, GeneratorInput } from "better-supabase/generators";

import { parseSnapshot, renderFiles } from "better-supabase/cli";
import { resolveConfig } from "better-supabase/config";
import { defineGenerator } from "better-supabase/generators";
import { frameworkRegistry } from "better-supabase/plugins";
import { testGeneratorPlugin } from "better-supabase/testing";
import { mkdtemp, readdir, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Worker } from "node:worker_threads";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { qwik } from "./acme-framework.ts";
import { acmeTables } from "./acme-generator.ts";

const SNAPSHOT = new URL("../../../supabase/snapshot.json", import.meta.url);

let root = "";
let snapshot: Snapshot;

beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), "bsb-plugins-"));
  snapshot = await parseSnapshot(
    JSON.parse(await readFile(SNAPSHOT, "utf-8")),
    "supabase/snapshot.json",
  );
});

afterEach(async () => {
  await rm(root, { recursive: true, force: true });
});

const render = (generators: Parameters<typeof resolveConfig>[0]["gen"]) =>
  renderFiles(
    resolveConfig(
      { gen: { file: "src/db/generated.ts", ...generators } },
      root,
    ),
    snapshot,
  );

describe("an external generator", () => {
  it("passes testGeneratorPlugin", async () => {
    const files = await render({ generators: [acmeTables()] });
    const schema = files.find((file) => file.path === "src/db/generated.ts");
    expect(schema?.contents).toContain("validators");

    // The conformance run needs the schema's meta, which the library's own
    // fixtures build; the capture below hands the generator a real input.
    let seen: GeneratorInput | undefined;

    await render({
      generators: [
        defineGenerator({
          name: "spy",
          version: "1.0.0",
          generate: (input) => {
            seen = input;

            return [];
          },
        }),
      ],
    });

    expect(seen).toBeDefined();

    await expect(
      testGeneratorPlugin(acmeTables(), { meta: seen!.meta }),
    ).resolves.toBeDefined();
  });

  it("provides the validators the generated module installs", async () => {
    const files = await render({ generators: [acmeTables()] });
    const main = files.find((file) => file.path === "src/db/generated.ts");

    expect(files.some((file) => file.path === "src/db/generated.acme.ts")).toBe(
      true,
    );
    expect(main?.contents).toContain('from "./generated.acme.ts"');
  });

  it("gives the same bytes from the cache as from a fresh run", async () => {
    const fresh = await render({ generators: [acmeTables()] });
    const cached = await render({ generators: [acmeTables()] });

    expect(cached).toEqual(fresh);

    const cacheFile = join(
      root,
      "node_modules/.cache/better-supabase/generators",
    );

    expect(
      (await readFile(join(cacheFile, await firstEntry(cacheFile)), "utf-8"))
        .length,
    ).toBeGreaterThan(0);

    const other = await render({
      generators: [acmeTables({ output: "src/db/other.ts" })],
    });

    expect(other.some((file) => file.path === "src/db/other.ts")).toBe(true);
  });

  it("runs on a worker thread and writes the bytes a fresh run writes", async () => {
    let seen: GeneratorInput | undefined;

    await render({
      generators: [
        defineGenerator({
          name: "spy",
          version: "1.0.0",
          generate: (input) => {
            seen = input;

            return [];
          },
        }),
      ],
    });

    const input = structuredClone(seen!);
    const fresh = await acmeTables().generate(input);

    const worker = new Worker(new URL("worker.ts", import.meta.url), {
      workerData: input,
      execArgv: ["--conditions=@better-supabase/source"],
    });

    const files = await new Promise<GeneratedFile[]>((resolve, reject) => {
      worker.once("message", (message: GeneratedFile[]) => {
        resolve(message);
      });
      worker.once("error", reject);
    });

    await worker.terminate();

    expect(files).toEqual([...fresh]);
  });
});

describe("an external framework binding", () => {
  it("is detected from the app's packages, after the built-in ones", () => {
    const registry = frameworkRegistry([qwik]);

    expect(registry.detect({ "@builder.io/qwik": "1" })?.name).toBe("qwik");
    expect(registry.detect({ vue: "3", "@builder.io/qwik": "1" })?.name).toBe(
      "vue",
    );
    expect(registry.detect({ express: "5" })).toBeUndefined();
  });

  it("resolves as gen.hooks and writes hooks.ts from its module", async () => {
    const config = resolveConfig(
      {
        gen: { frameworks: [qwik], hooks: "qwik", file: "src/db/generated.ts" },
      },
      root,
    );

    expect(config.hooks).toBe("qwik");

    const files = await renderFiles(config, snapshot);
    const hooks = files.find((file) => file.path === "src/db/hooks.ts");

    expect(hooks?.contents).toContain('"use qwik";');
    expect(hooks?.contents).toContain(
      'import { defineListHook, defineOneHook } from "@acme/qwik-hooks";',
    );
  });

  it("is refused by name when the config does not register it", () => {
    expect(() => resolveConfig({ gen: { hooks: "qwik" } }, root)).toThrow(
      'names framework "qwik", which nothing registers',
    );
  });
});

async function firstEntry(folder: string): Promise<string> {
  const [entry] = await readdir(folder);

  return entry ?? "";
}
