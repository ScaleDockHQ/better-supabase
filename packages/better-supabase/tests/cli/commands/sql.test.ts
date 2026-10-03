import { cp, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { parseCommandArgs } from "../../../src/cli/command.ts";
import {
  sqlCommand,
  type SqlArgs,
  runSql,
} from "../../../src/cli/commands/sql.ts";
import { VERSION } from "../../../src/cli/version.ts";
import {
  type BetterSupabaseConfig,
  resolveConfig,
} from "../../../src/config/index.ts";
import { SQL_MODULES } from "../../../src/sql/index.ts";
import { kitLayout } from "../../../src/sql/index.ts";

const fixtures = resolve(import.meta.dirname, "../fixtures");

describe("kitLayout", () => {
  it("turns expose into grants per role and json schemas into column checks", () => {
    const config = resolveConfig(
      {
        expose: {
          "public.posts": {
            anon: ["select"],
            authenticated: ["select", "insert"],
          },
          "public.notes": ["select"],
        },
        json: {
          "public.posts.meta": { type: "Meta", schema: { type: "object" } },
          "public.posts.raw": { type: "unknown" },
        },
        plugins: { tenant: { column: "org_id" } },
      },
      "/p",
    );
    const kit = kitLayout(config, "tests/sql");
    expect(kit.grants).toEqual([
      { table: "public.posts", role: "anon", privileges: ["select"] },
      {
        table: "public.posts",
        role: "authenticated",
        privileges: ["select", "insert"],
      },
      { table: "public.notes", role: "anon", privileges: [] },
      { table: "public.notes", role: "authenticated", privileges: ["select"] },
    ]);
    expect(kit.jsonSchemas).toEqual([
      { table: "public.posts", column: "meta", schema: { type: "object" } },
    ]);
    expect(kit).toMatchObject({
      testsDir: "tests/sql",
      version: VERSION,
      tenantColumn: "org_id",
    });
    expect(kit).not.toHaveProperty("permdock");
  });
});

describe("runSql", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "better-supabase-sql-"));
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  const sql = (argv: string[], config: BetterSupabaseConfig = {}) =>
    runSql(
      resolveConfig(config, root),
      parseCommandArgs(sqlCommand, argv) as SqlArgs,
    );

  it("asks for an action and rejects unknown ones", async () => {
    const usage = "Run `better-supabase sql --help` for the actions.";
    expect(await sql([])).toEqual({
      code: 2,
      error: `Name an action.\n${usage}`,
    });
    expect(await sql(["drop"])).toEqual({
      code: 2,
      error: `Unknown sql action "drop".\n${usage}`,
    });
  });

  it("asks for module names", async () => {
    expect(await sql(["add"])).toEqual({
      code: 2,
      error:
        "Name at least one module.\nRun `better-supabase sql --help` for the actions.",
    });
    const names = Object.keys(SQL_MODULES).join(", ");
    expect(await sql(["print"])).toEqual({
      code: 2,
      error: `Name one module: ${names}`,
    });
    expect((await sql(["print", "nope"])).code).toBe(2);
  });

  it("has nothing to sync for an empty sql.kit", async () => {
    expect(await sql(["sync"])).toEqual({
      code: 0,
      output: "sql.kit is empty; nothing to sync.",
    });
  });

  it("prints a rendered module with the configured claims", async () => {
    const printed = await sql(["print", "tenant"], {
      claims: { scope: "workspace" },
    });
    expect(printed.code).toBe(0);
    expect(printed.output).toContain("'workspace'");
    expect(printed.output).not.toBe(SQL_MODULES["tenant"]!.sql);
    expect(await sql(["print", "mfa"])).toEqual({
      code: 0,
      output: SQL_MODULES["mfa"]!.sql,
    });
  });

  it("stops on an entitlements scope the manifest lacks", async () => {
    await writeFile(join(root, "permdock.config.ts"), "export default {};\n");
    await cp(
      join(fixtures, "permdock.manifest.json"),
      join(root, "permdock.manifest.json"),
    );
    await expect(
      sql(["list"], { entitlements: { permdock: { scope: "team" } } }),
    ).rejects.toThrow(/entitlements\.permdock\.scope is "team"/);
  });

  it("refuses to render entitlements for a scope id type it doesn't support", async () => {
    const manifest = JSON.parse(
      await readFile(join(fixtures, "permdock.manifest.json"), "utf8"),
    );
    manifest.rls.scopes[0].type = "numeric";
    await writeFile(join(root, "permdock.config.ts"), "export default {};\n");
    await writeFile(
      join(root, "permdock.manifest.json"),
      JSON.stringify(manifest),
    );
    await expect(sql(["print", "entitlements"])).rejects.toThrow(
      /scope "organization" the type numeric/,
    );
  });
});
