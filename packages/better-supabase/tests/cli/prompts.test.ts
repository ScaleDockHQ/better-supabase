import { existsSync } from "node:fs";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import type { Choice, Prompter } from "../../src/cli/prompts.ts";

import { run } from "../../src/cli/core/run.ts";

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

const { clackSpinner, createClackPrompter } =
  await import("../../src/cli/prompts.ts");

const clackPrompter = createClackPrompter(process.stderr);

interface Asked {
  readonly kind: string;
  readonly message: string;
  readonly initial?: unknown;
}

/** A prompter that answers from `answers` in order and records each question. */
function fake(answers: unknown[]): Prompter & { readonly asked: Asked[] } {
  const asked: Asked[] = [];

  return {
    asked,
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

/** The answers that keep every convention at its default. */
const DEFAULT_ANSWERS = [
  "snake",
  "tenant",
  "organization",
  "roles",
  "uuid",
  "none",
];

const runWith = (argv: readonly string[], prompts: Prompter) =>
  run([...argv, "--cwd", dir], {
    io: { stdout: () => {}, stderr: () => {}, prompts },
  });

describe("init prompts", () => {
  it("asks for the conventions in /create's order and the integrations, pre-checking detected ones", async () => {
    const prompts = fake([
      "none",
      "camel",
      "tenant",
      "workspace",
      "roles",
      "text",
      "api",
      ["mcp"],
    ]);

    const result = await runWith(["init"], prompts);
    expect(result.code).toBe(0);
    expect(prompts.asked).toEqual([
      { kind: "select", message: "Preset", initial: "none" },
      { kind: "select", message: "Casing", initial: "snake" },
      { kind: "select", message: "Row ownership", initial: "tenant" },
      { kind: "select", message: "Tenant name", initial: "organization" },
      { kind: "select", message: "Auth and permissions", initial: "roles" },
      { kind: "select", message: "ID type", initial: "uuid" },
      { kind: "select", message: "API schema", initial: "none" },
      { kind: "multiselect", message: "Integrations", initial: ["hono"] },
    ]);

    const config = await readFile(
      join(dir, "better-supabase.config.ts"),
      "utf-8",
    );

    expect(config).toContain("casing: 'camel'");
    expect(config).toContain(
      "sql: { api: 'api', naming: { tenant: 'workspace' } },",
    );
    expect(config).toContain("blocks: { access: { idType: 'text' } },");
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

    const prompts = fake([
      "none",
      "snake",
      "user",
      "roles",
      "uuid",
      "none",
      "apps/api",
      ["hono"],
    ]);

    const result = await runWith(["init"], prompts);
    expect(result.code).toBe(0);
    expect(prompts.asked).toEqual([
      { kind: "select", message: "Preset", initial: "none" },
      { kind: "select", message: "Casing", initial: "snake" },
      { kind: "select", message: "Row ownership", initial: "tenant" },
      { kind: "select", message: "Auth and permissions", initial: "roles" },
      { kind: "select", message: "ID type", initial: "uuid" },
      { kind: "select", message: "API schema", initial: "none" },
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
    expect(
      (await runWith(["init"], fake(["none", "snake", undefined]))).code,
    ).toBe(1);
  });

  it("asks nothing with --yes or when the flags answer", async () => {
    const prompts = fake([]);
    expect((await runWith(["init", "--yes", "--dry-run"], prompts)).code).toBe(
      0,
    );
    expect(
      (
        await runWith(
          ["init", "--casing", "camel", "--integration", "hono", "--force"],
          prompts,
        )
      ).code,
    ).toBe(0);
    expect(prompts.asked).toEqual([]);
  });

  it("confirms before overwriting existing files", async () => {
    await writeFile(join(dir, "better-supabase.config.ts"), "// mine\n");
    const keep = fake(["none", ...DEFAULT_ANSWERS, [], false]);
    const kept = await runWith(["init"], keep);
    expect(kept.stdout).toContain(
      "Skipped better-supabase.config.ts (exists; pass --force to overwrite)",
    );
    expect(keep.asked.at(-1)).toEqual({
      kind: "confirm",
      message: "better-supabase.config.ts exists. Overwrite?",
    });

    const replace = fake(["none", ...DEFAULT_ANSWERS, [], true]);
    await runWith(["init"], replace);
    expect(
      await readFile(join(dir, "better-supabase.config.ts"), "utf-8"),
    ).not.toBe("// mine\n");
  });

  it("stops when the person cancels", async () => {
    for (const answers of [
      [undefined],
      ["none", undefined],
      ["none", "camel", undefined],
    ]) {
      expect(await runWith(["init"], fake(answers))).toMatchObject({
        code: 1,
        stderr: "Cancelled.\n",
      });
    }

    await writeFile(join(dir, "better-supabase.config.ts"), "// mine\n");
    expect(
      (
        await runWith(
          ["init"],
          fake(["none", ...DEFAULT_ANSWERS, [], undefined]),
        )
      ).code,
    ).toBe(1);
  });

  it("starts from the preset the person picks", async () => {
    const prompts = fake(["minimal"]);
    const result = await runWith(["init", "--dry-run"], prompts);
    expect(result.code).toBe(0);
    expect(prompts.asked).toEqual([
      { kind: "select", message: "Preset", initial: "none" },
    ]);
    expect(result.stdout).toContain("Would create lib/blocks.ts");
    expect(result.stdout).toContain("(profiles)");
  });
});

describe("add prompts", () => {
  it("asks for integrations when none are named", async () => {
    const prompts = fake([["orpc"]]);
    const result = await runWith(["add", "--dry-run"], prompts);
    expect(result.stdout).toContain("Would create router.ts");
    expect(prompts.asked).toEqual([
      { kind: "multiselect", message: "Integrations", initial: [] },
    ]);
  });

  it("needs at least one integration, and stops on cancel", async () => {
    expect((await runWith(["add"], fake([[]]))).code).toBe(2);
    expect((await runWith(["add"], fake([undefined]))).code).toBe(1);
  });
});

describe("clackPrompter", () => {
  const choices = [
    { value: "a", label: "A", hint: "first" },
    { value: "b", label: "B" },
  ] as const;

  it("maps answers, and a cancel ends the run with exit code 130", async () => {
    clack.answers.push(
      "b",
      clack.cancel,
      ["a", "zz"],
      clack.cancel,
      true,
      clack.cancel,
    );
    const cancelled = { code: "cancelled", exitCode: 130 };
    expect(await clackPrompter.select("Pick", choices, "a")).toBe("b");
    await expect(
      clackPrompter.select("Pick", choices, "a"),
    ).rejects.toMatchObject(cancelled);
    expect(await clackPrompter.multiselect("Pick", choices, [])).toEqual(["a"]);
    await expect(
      clackPrompter.multiselect("Pick", choices, []),
    ).rejects.toMatchObject(cancelled);
    expect(await clackPrompter.confirm("Sure?")).toBe(true);
    await expect(clackPrompter.confirm("Sure?")).rejects.toMatchObject(
      cancelled,
    );
  });

  it("clears the spinner when stopped", () => {
    const stop = clackSpinner(process.stderr, "Loading");
    expect(clack.spinner.start).toHaveBeenCalledWith("Loading");
    stop();
    expect(clack.spinner.clear).toHaveBeenCalledWith();
  });
});
