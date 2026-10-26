import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { run } from "../../../src/cli/core/run.ts";

describe("add", () => {
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "better-supabase-add-"));
    await writeFile(
      join(dir, "better-supabase.config.json"),
      JSON.stringify({ blocks: [] }),
    );
  });

  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it.each([
    [["audit", "--preset", "saas"], "Pass blocks or --preset, not both"],
    [["audit", "--package", "apps/web"], "--package works with --preset"],
    [["--adopt", "audit", "tags"], "Adopt one block at a time"],
    [
      ["--adopt", "--tables", "public.t"],
      "--tables works with --adopt and one block",
    ],
    [["audit", "--tables", "public.t"], "--tables works with --adopt"],
    [["--over", "public.t"], "--over works with one block"],
    [["audit", "tags", "--over", "public.t"], "--over works with one block"],
    [["audit", "--over", "public.t", "--adopt"], "--over replaces --adopt"],
    [
      ["audit", "--over", "public.t", "--tables", "public.t"],
      "--over replaces",
    ],
  ])("refuses add %j", async (argv, message) => {
    const result = await run(["add", ...argv, "--cwd", dir]);

    expect(result.code).toBe(2);
    expect(result.stderr).toContain(message);
  });

  it("prints the next step that turns the schema files into a migration", async () => {
    const result = await run(["add", "audit", "--json", "--cwd", dir]);

    const envelope = JSON.parse(result.stdout) as {
      next: { command: string }[];
    };

    expect(result.code).toBe(0);
    expect(envelope.next.map((step) => step.command).join("\n")).toContain(
      "better_supabase_module",
    );
  });

  it("renders an installed block again when one it integrates with lands", async () => {
    await writeFile(
      join(dir, "better-supabase.config.json"),
      JSON.stringify({ blocks: ["promotions"] }),
    );

    const result = await run(["add", "outbox", "--cwd", dir]);

    expect(result.code).toBe(0);
    expect(result.stdout).toContain(
      "Re-rendered promotions: it integrates with outbox.",
    );
  });

  it("writes the data migration with --adopt and no block", async () => {
    const result = await run(["add", "--adopt", "--dry-run", "--cwd", dir]);

    expect(result.code).not.toBe(2);
  });
});
