import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { readSupabasePort } from "../src/config.ts";
import {
  parseTomlSubset,
  readSupabaseToml,
  schemaPaths,
  type SupabaseToml,
  tomlGet,
} from "../src/supabase-toml.ts";

describe("readSupabaseToml", () => {
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "better-supabase-toml-"));
    await mkdir(join(dir, "supabase"));
  });

  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it("parses with @supabase/config, including env() values", async () => {
    await writeFile(
      join(dir, "supabase/config.toml"),
      [
        'project_id = "demo"',
        "[db]",
        "port = 55422",
        "[auth]",
        'site_url = "env(BS_TOML_SITE_URL)"',
        "jwt_expiry = 7200",
        "",
      ].join("\n"),
    );
    process.env["BS_TOML_SITE_URL"] = "https://example.test";
    try {
      const toml = await readSupabaseToml(dir);
      expect(toml?.parser).toBe("@supabase/config");
      expect(tomlGet(toml!.document, ["auth", "site_url"])).toBe(
        "https://example.test",
      );
      expect(tomlGet(toml!.document, ["auth", "jwt_expiry"])).toBe(7200);
      expect(await readSupabasePort(dir, "db")).toBe(55422);
      expect(await readSupabasePort(dir, "api")).toBeUndefined();
    } finally {
      delete process.env["BS_TOML_SITE_URL"];
    }
  });

  it("returns undefined without a config.toml", async () => {
    expect(await readSupabaseToml(join(dir, "missing"))).toBeUndefined();
  });
});

describe("parseTomlSubset", () => {
  it("reads arrays over several lines, with comments", () => {
    const document = parseTomlSubset(
      [
        "[db.migrations]",
        "schema_paths = [",
        '  "./schemas/010_extensions.sql", # first',
        "  # the CRM tables",
        '  "./schemas/030_crm/*.sql",',
        "]",
        "enabled = true",
      ].join("\n"),
    );
    expect(tomlGet(document, ["db", "migrations", "schema_paths"])).toEqual([
      "./schemas/010_extensions.sql",
      "./schemas/030_crm/*.sql",
    ]);
    expect(tomlGet(document, ["db", "migrations", "enabled"])).toBe(true);
  });
});

describe("schemaPaths", () => {
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "better-supabase-schema-paths-"));
    await mkdir(join(dir, "supabase/schemas/030_crm"), { recursive: true });
    for (const file of [
      "010_extensions.sql",
      "020_types.sql",
      "030_crm/b.sql",
      "030_crm/a.sql",
      "999_unlisted.sql",
    ])
      await writeFile(join(dir, "supabase/schemas", file), "");
  });

  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  const tomlWith = (text: string): SupabaseToml => ({
    path: "supabase/config.toml",
    text,
    document: parseTomlSubset(text),
    parser: "builtin",
  });

  it("keeps the listed order, expands globs by name and puts unmatched files last", async () => {
    const order = await schemaPaths(
      dir,
      tomlWith(
        [
          "[db.migrations]",
          "schema_paths = [",
          '  "./schemas/030_crm/*.sql",',
          '  "./schemas/010_extensions.sql",',
          '  "./schemas/020_types.sql",',
          "]",
        ].join("\n"),
      ),
    );
    expect(order).toEqual({
      configured: true,
      files: [
        "supabase/schemas/030_crm/a.sql",
        "supabase/schemas/030_crm/b.sql",
        "supabase/schemas/010_extensions.sql",
        "supabase/schemas/020_types.sql",
        "supabase/schemas/999_unlisted.sql",
      ],
      unlisted: ["supabase/schemas/999_unlisted.sql"],
    });
  });

  it("reads supabase/schemas in name order without schema_paths", async () => {
    expect(await schemaPaths(dir, undefined)).toEqual({
      configured: false,
      files: [
        "supabase/schemas/010_extensions.sql",
        "supabase/schemas/020_types.sql",
        "supabase/schemas/030_crm/a.sql",
        "supabase/schemas/030_crm/b.sql",
        "supabase/schemas/999_unlisted.sql",
      ],
      unlisted: [],
    });
  });
});
