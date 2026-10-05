import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { printableConfig } from "../../../src/cli/commands/config.ts";
import { run } from "../../../src/cli/run.ts";
import { resolveConfig } from "../../../src/config/index.ts";

describe("config", () => {
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "better-supabase-config-"));
  });

  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it("prints the file it loaded and the resolved options", async () => {
    await writeFile(
      join(dir, "better-supabase.config.mjs"),
      `export default {
  casing: "camel",
  source: { dbUrl: "postgresql://postgres:secret@db.example.com:5432/postgres" },
  generators: [{ apiVersion: 1, name: "tables", generate: () => [] }],
};\n`,
    );
    const result = await run(["config", "--json", "--cwd", dir], { env: {} });
    expect(result.code).toBe(0);
    const printed = JSON.parse(result.stdout) as {
      file: string;
      config: Record<string, unknown>;
    };
    expect(printed.file).toBe("better-supabase.config.mjs");
    expect(printed.config).toMatchObject({
      casing: "camel",
      output: "src/lib/supabase/generated.ts",
      source: {
        dbUrl: "postgresql://postgres:redacted@db.example.com:5432/postgres",
      },
      generators: [{ name: "tables", apiVersion: 1 }],
    });
    expect(result.stdout).not.toContain("secret");
  });

  it("says when there is no config file", async () => {
    const result = await run(["config", "--cwd", dir], { env: {} });
    expect(result.stdout).toMatch(/^# no config file, defaults only\n\{/);
  });

  it("redacts a connection string it cannot parse", () => {
    const config = resolveConfig(
      { source: { dbUrl: "not a url" }, generators: [] },
      "/project",
    );
    expect(printableConfig(config)).toMatchObject({
      source: { dbUrl: "<redacted>" },
    });
    expect(
      printableConfig(
        resolveConfig(
          { source: { dbUrl: "postgresql://localhost/postgres" } },
          "/",
        ),
      ),
    ).toMatchObject({ source: { dbUrl: "postgresql://localhost/postgres" } });
  });
});
