import { mkdtemp, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { Generator, GeneratorInput } from "../../../src/config/index.ts";

import { setCacheEnabled } from "../../../src/cli/cache/store.ts";
import {
  generatorKey,
  runGenerators,
} from "../../../src/cli/generators/run.ts";
import { defineGenerator } from "../../../src/generators/kit.ts";

let root = "";

beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), "bsb-generators-"));
  setCacheEnabled(true);
});

afterEach(async () => {
  await rm(root, { recursive: true, force: true });
});

const input = (name = "a"): GeneratorInput =>
  ({
    meta: { tables: {}, name },
    imports: { runtime: "better-supabase" },
  }) as unknown as GeneratorInput;

function counting(extra: Partial<Generator> = {}) {
  const calls = { count: 0 };

  const generator = defineGenerator({
    name: "counting",
    version: "1.0.0",
    pure: true,
    generate: (given) => {
      calls.count += 1;

      return [{ path: "out.txt", contents: JSON.stringify(given.meta) }];
    },
    ...extra,
  });

  return { calls, generator };
}

const options = () => ({ root, taken: new Set<string>() });

describe("runGenerators", () => {
  it("serves a pure generator from the cache, and keys on the input", async () => {
    const { calls, generator } = counting();

    const first = await runGenerators([generator], input(), options());
    const second = await runGenerators([generator], input(), options());

    expect(calls.count).toBe(1);
    expect(first.cached).toEqual([]);
    expect(second.cached).toEqual(["counting"]);
    expect(second.files).toEqual(first.files);

    await runGenerators([generator], input("b"), options());
    expect(calls.count).toBe(2);
  });

  it("keys on the version and the options", () => {
    const { generator } = counting();

    const base = generatorKey(generator, input());
    expect(generatorKey({ ...generator, version: "1.0.1" }, input())).not.toBe(
      base,
    );
    expect(
      generatorKey({ ...generator, options: { flavor: "mini" } }, input()),
    ).not.toBe(base);
    expect(generatorKey(generator, input())).toBe(base);
  });

  it("runs a generator that declares no purity on every pass", async () => {
    const { calls, generator } = counting({ pure: false });

    await runGenerators([generator], input(), options());
    await runGenerators([generator], input(), options());

    expect(calls.count).toBe(2);
    expect(await readdir(root)).toEqual([]);
  });

  it("does not cache under --no-cache", async () => {
    const { calls, generator } = counting();
    setCacheEnabled(false);

    await runGenerators([generator], input(), options());
    await runGenerators([generator], input(), options());

    expect(calls.count).toBe(2);
  });

  it("refuses two generators that provide one capability", async () => {
    const provide = (name: string) =>
      defineGenerator({
        name,
        version: "1.0.0",
        provides: ["validators"],
        generate: () => [],
      });

    await expect(
      runGenerators([provide("a"), provide("b")], input(), options()),
    ).rejects.toThrow('both provide "validators"');
  });

  it("returns who provides a capability", async () => {
    const generator = defineGenerator({
      name: "v",
      version: "1.0.0",
      provides: ["validators"],
      generate: () => [{ path: "v.ts", contents: "" }],
    });

    const run = await runGenerators([generator], input(), options());
    expect(run.capabilities.get("validators")).toBe("v");
  });
});
