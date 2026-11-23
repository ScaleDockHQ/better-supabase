import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { Generator } from "../../../src/config/index.ts";

import { printableConfig } from "../../../src/cli/commands/config.ts";
import { run } from "../../../src/cli/core/run.ts";
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
  database: {
    source: { dbUrl: "postgresql://postgres:secret@db.example.com:5432/postgres" },
  },
  gen: {
    casing: "camel",
    generators: [
      { apiVersion: 2, name: "tables", version: "1.0.0", generate: () => [] },
    ],
  },
};\n`,
    );
    const result = await run(["config", "--json", "--cwd", dir], { env: {} });
    expect(result.code).toBe(0);

    const { data: printed } = JSON.parse(result.stdout) as {
      data: { file: string; config: Record<string, unknown> };
    };

    expect(printed.file).toBe("better-supabase.config.mjs");
    expect(printed.config).toMatchObject({
      casing: "camel",
      output: "src/lib/supabase/generated.ts",
      source: {
        dbUrl: "postgresql://postgres:redacted@db.example.com:5432/postgres",
      },
      generators: [{ name: "tables", version: "1.0.0", apiVersion: 2 }],
    });
    expect(result.stdout).not.toContain("secret");
  });

  it("redacts the Management API token", async () => {
    await writeFile(
      join(dir, "better-supabase.config.mjs"),
      `export default { database: { source: { accessToken: "sbp_0123456789abcdef0123456789abcdef" } } };\n`,
    );

    for (const argv of [["config"], ["config", "--json"]]) {
      const result = await run([...argv, "--cwd", dir], { env: {} });

      expect(result.code).toBe(0);
      expect(result.stdout).not.toContain("sbp_0123456789abcdef");
      expect(result.stdout).toContain("<redacted>");
    }
  });

  it("lists the actions and the access policies as versioned JSON", async () => {
    await writeFile(
      join(dir, "better-supabase.config.mjs"),
      `export default { gen: { generators: [] }, blocks: ["audit"] };\n`,
    );
    await mkdir(join(dir, "supabase", "schemas"), { recursive: true });
    await writeFile(
      join(dir, "supabase", "schemas", "items.sql"),
      `create table public.items (id uuid primary key, tenant_id uuid);\ncomment on table public.items is '@bsb access read=items.read';\n`,
    );

    const actions = JSON.parse(
      (await run(["config", "actions", "--json", "--cwd", dir], { env: {} }))
        .stdout,
    ) as { data: { version: number; actions: { kind: string }[] } };

    expect(actions.data.version).toBe(1);
    expect(actions.data.actions.length).toBeGreaterThan(0);

    const policies = JSON.parse(
      (await run(["config", "policies", "--json", "--cwd", dir], { env: {} }))
        .stdout,
    ) as { data: { version: number; policies: { name: string }[] } };

    expect(policies.data.policies.map((row) => row.name)).toEqual([
      "bsb_access_items_read",
    ]);
  });

  it("says when there is no config file", async () => {
    const result = await run(["config", "--cwd", dir], { env: {} });
    expect(result.stdout).toMatch(/^# no config file, defaults only\n\{/);
  });

  it("redacts a connection string it cannot parse", () => {
    const config = resolveConfig(
      { database: { source: { dbUrl: "not a url" } }, gen: { generators: [] } },
      "/project",
    );

    expect(printableConfig(config)).toMatchObject({
      source: { dbUrl: "<redacted>" },
    });
    expect(
      printableConfig(
        resolveConfig(
          {
            database: { source: { dbUrl: "postgresql://localhost/postgres" } },
          },
          "/",
        ),
      ),
    ).toMatchObject({ source: { dbUrl: "postgresql://localhost/postgres" } });
  });

  it("refuses a generator that still targets API 1, naming the change", () => {
    const old = { name: "plain", generate: () => [] } as unknown as Generator;

    expect(() =>
      resolveConfig({ gen: { generators: [old] } }, "/project"),
    ).toThrow(/targets generator API 1; this better-supabase runs 2/);
  });
});
