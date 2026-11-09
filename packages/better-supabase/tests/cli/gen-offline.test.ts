import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { CliIo } from "../../src/cli/core/io.ts";

import { run } from "../../src/cli/core/run.ts";
import { snapshotFixture } from "./fixtures/library.ts";

describe("gen --offline", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "better-supabase-gen-offline-"));

    await writeFile(
      join(root, "better-supabase.config.ts"),
      `export default { gen: { casing: "camel", file: "src/db/generated.ts" } };\n`,
    );

    await writeFile(
      join(root, "snapshot.json"),
      JSON.stringify(snapshotFixture),
    );
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  const gen = async (args: readonly string[]) => {
    const out: string[] = [];

    const io: CliIo = {
      stdout: (text) => {
        out.push(text);
      },
      stderr: (text) => {
        out.push(text);
      },
      stdin: () => Promise.resolve(""),
    };

    const result = await run(["gen", ...args, "--cwd", root], { io });

    return { code: result.code, output: out.join("") };
  };

  it("fails without a saved snapshot and never reaches for a database", async () => {
    const result = await gen(["--check", "--offline"]);

    expect(result.code).not.toBe(0);
    expect(result.output).toContain("--offline needs a saved snapshot");
  });

  it("refuses a live source flag", async () => {
    const result = await gen([
      "--check",
      "--offline",
      "--project-ref",
      "abcdefghijklmnopqrst",
    ]);

    expect(result.code).not.toBe(0);
    expect(result.output).toContain("--offline never connects");
  });

  it("generates from the given snapshot", async () => {
    const result = await gen([
      "--offline",
      "--snapshot",
      join(root, "snapshot.json"),
    ]);

    expect(result.output).not.toContain("--offline needs");
    expect(result.code).toBe(0);
  });
});
