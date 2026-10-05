import { existsSync } from "node:fs";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import type { Choice, Prompter } from "../../src/cli/prompts.ts";

import { run } from "../../src/cli/run.ts";

const clack = vi.hoisted(() => ({
  cancel: Symbol("cancel"),
  answers: [] as unknown[],
  spinner: { start: vi.fn(), clear: vi.fn() },
}));

vi.mock("@clack/prompts", () => {
  const next = (): unknown => clack.answers.shift();
  return {
    select: vi.fn(next),
    multiselect: vi.fn(next),
    confirm: vi.fn(next),
    isCancel: (value: unknown) => value === clack.cancel,
    spinner: () => clack.spinner,
  };
});

const { clackPrompter, withSpinner } = await import("../../src/cli/prompts.ts");

interface Asked {
  readonly kind: string;
  readonly message: string;
  readonly initial?: unknown;
}

/** A prompter that answers from `answers` in order and records each question. */
function fake(answers: unknown[]): Prompter & {
  readonly asked: Asked[];
  readonly spun: string[];
} {
  const asked: Asked[] = [];
  const spun: string[] = [];
  return {
    asked,
    spun,
    select: async <T extends string>(
      message: string,
      _choices: readonly Choice<T>[],
      initial: T,
    ) => {
      asked.push({ kind: "select", message, initial });
      return answers.shift() as T | undefined;
    },
    multiselect: async <T extends string>(
      message: string,
      _choices: readonly Choice<T>[],
      initial: readonly T[],
    ) => {
      asked.push({ kind: "multiselect", message, initial });
      return answers.shift() as T[] | undefined;
    },
    confirm: async (message) => {
      asked.push({ kind: "confirm", message });
      return answers.shift() as boolean | undefined;
    },
    spinner: (message) => {
      spun.push(message);
      return () => spun.push(`done: ${message}`);
    },
  };
}

let dir: string;

beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), "better-supabase-prompts-"));
  await writeFile(
    join(dir, "package.json"),
    JSON.stringify({ name: "app", dependencies: { hono: "4" } }),
  );
});

afterEach(async () => {
  await rm(dir, { recursive: true, force: true });
});

const runWith = (argv: readonly string[], prompts: Prompter) =>
  run([...argv, "--cwd", dir], {
    io: { stdout: () => {}, stderr: () => {}, prompts },
  });

describe("init prompts", () => {
  it("asks for the casing and the integrations, pre-checking detected ones", async () => {
    const prompts = fake(["snake", ["mcp"]]);
    const result = await runWith(["init"], prompts);
    expect(result.code).toBe(0);
    expect(prompts.asked).toEqual([
      { kind: "select", message: "Row keys", initial: "camel" },
      { kind: "multiselect", message: "Integrations", initial: ["hono"] },
    ]);
    expect(
      await readFile(join(dir, "better-supabase.config.ts"), "utf8"),
    ).toContain("snake");
    expect(existsSync(join(dir, "supabase/functions/mcp/index.ts"))).toBe(true);
  });

  it("asks for the package at a workspace root", async () => {
    await writeFile(
      join(dir, "pnpm-workspace.yaml"),
      "packages:\n  - apps/*\n",
    );
    await mkdir(join(dir, "apps/api"), { recursive: true });
    await writeFile(
      join(dir, "apps/api/package.json"),
      JSON.stringify({ name: "api", dependencies: { hono: "4" } }),
    );
    const prompts = fake(["camel", "apps/api", ["hono"]]);
    const result = await runWith(["init"], prompts);
    expect(result.code).toBe(0);
    expect(prompts.asked).toEqual([
      { kind: "select", message: "Row keys", initial: "camel" },
      {
        kind: "select",
        message: "Package that owns the runtime",
        initial: "apps/api",
      },
      { kind: "multiselect", message: "Integrations", initial: ["hono"] },
    ]);
    expect(existsSync(join(dir, "apps/api/better-supabase.config.ts"))).toBe(
      true,
    );
    expect((await runWith(["init"], fake(["camel", undefined]))).code).toBe(1);
  });

  it("asks nothing with --yes or when the flags answer", async () => {
    const prompts = fake([]);
    expect((await runWith(["init", "--yes", "--dry-run"], prompts)).code).toBe(
      0,
    );
    expect(
      (
        await runWith(
          ["init", "--casing", "camel", "--with", "hono", "--force"],
          prompts,
        )
      ).code,
    ).toBe(0);
    expect(prompts.asked).toEqual([]);
  });

  it("confirms before overwriting existing files", async () => {
    await writeFile(join(dir, "better-supabase.config.ts"), "// mine\n");
    const keep = fake(["camel", [], false]);
    const kept = await runWith(["init"], keep);
    expect(kept.stdout).toContain("Kept    better-supabase.config.ts (exists)");
    expect(keep.asked.at(-1)).toEqual({
      kind: "confirm",
      message: "better-supabase.config.ts exists. Overwrite?",
    });

    const replace = fake(["camel", [], true]);
    await runWith(["init"], replace);
    expect(
      await readFile(join(dir, "better-supabase.config.ts"), "utf8"),
    ).not.toBe("// mine\n");
  });

  it("stops when the person cancels", async () => {
    for (const answers of [[undefined], ["camel", undefined]]) {
      expect(await runWith(["init"], fake(answers))).toMatchObject({
        code: 1,
        stderr: "Cancelled.\n",
      });
    }
    await writeFile(join(dir, "better-supabase.config.ts"), "// mine\n");
    expect((await runWith(["init"], fake(["camel", [], undefined]))).code).toBe(
      1,
    );
  });
});

describe("add prompts", () => {
  it("asks for integrations when none are named", async () => {
    const prompts = fake([["orpc"]]);
    const result = await runWith(["add", "--dry-run"], prompts);
    expect(result.stdout).toContain("Would write router.ts");
    expect(prompts.asked).toEqual([
      { kind: "multiselect", message: "Integrations", initial: [] },
    ]);
  });

  it("needs at least one integration, and stops on cancel", async () => {
    expect((await runWith(["add"], fake([[]]))).code).toBe(2);
    expect((await runWith(["add"], fake([undefined]))).code).toBe(1);
  });
});

describe("withSpinner", () => {
  it("stops the spinner after the task, also when it throws", async () => {
    const prompts = fake([]);
    expect(await withSpinner(prompts, "Working", async () => 1)).toBe(1);
    await expect(
      withSpinner(prompts, "Failing", () => Promise.reject(new Error("x"))),
    ).rejects.toThrow("x");
    expect(prompts.spun).toEqual([
      "Working",
      "done: Working",
      "Failing",
      "done: Failing",
    ]);
    expect(await withSpinner(undefined, "Quiet", async () => 2)).toBe(2);
  });
});

describe("clackPrompter", () => {
  const choices = [
    { value: "a", label: "A", hint: "first" },
    { value: "b", label: "B" },
  ] as const;

  it("maps answers and cancels", async () => {
    clack.answers.push(
      "b",
      clack.cancel,
      ["a", "zz"],
      clack.cancel,
      true,
      clack.cancel,
    );
    expect(await clackPrompter.select("Pick", choices, "a")).toBe("b");
    expect(await clackPrompter.select("Pick", choices, "a")).toBeUndefined();
    expect(await clackPrompter.multiselect("Pick", choices, [])).toEqual(["a"]);
    expect(
      await clackPrompter.multiselect("Pick", choices, []),
    ).toBeUndefined();
    expect(await clackPrompter.confirm("Sure?")).toBe(true);
    expect(await clackPrompter.confirm("Sure?")).toBeUndefined();
  });

  it("clears the spinner when stopped", () => {
    const stop = clackPrompter.spinner("Loading");
    expect(clack.spinner.start).toHaveBeenCalledWith("Loading");
    stop();
    expect(clack.spinner.clear).toHaveBeenCalled();
  });
});
