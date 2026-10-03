import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { readSupabasePort } from "../../src/cli/config.ts";
import {
  diffEngine,
  migrationCommand,
  parseToml,
  readSupabaseToml,
  schemaPaths,
  type SupabaseToml,
  tomlGet,
} from "../../src/cli/supabase-toml.ts";

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

  it("parses a file without env() with smol-toml and reuses the parse", async () => {
    const path = join(dir, "supabase/config.toml");
    await writeFile(path, "[db]\nport = 55422\n");
    const first = await readSupabaseToml(dir);
    expect(first?.parser).toBe("smol-toml");
    expect(await readSupabaseToml(dir)).toBe(first);
    await writeFile(path, "[db]\nport = 55432\n");
    const changed = await readSupabaseToml(dir);
    expect(changed).not.toBe(first);
    expect(tomlGet(changed!.document, ["db", "port"])).toBe(55432);
  });

  it("returns undefined without a config.toml", async () => {
    expect(await readSupabaseToml(join(dir, "missing"))).toBeUndefined();
  });
});

describe("parseToml", () => {
  it("reads arrays over several lines, with comments", () => {
    const document = parseToml(
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

  it("turns dates into ISO strings and invalid files into an empty table", () => {
    expect(
      parseToml("[auth]\nsince = 2026-01-02T03:04:05Z\nlimits = { rate = 10 }"),
    ).toEqual({
      auth: { since: "2026-01-02T03:04:05.000Z", limits: { rate: 10 } },
    });
    expect(parseToml("[auth\nbroken")).toEqual({});
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
    document: parseToml(text),
    parser: "smol-toml",
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

  it("ignores schema_paths under pg-delta and reads its schema directory", async () => {
    const pgdelta = tomlWith(
      [
        "[db.migrations]",
        'schema_paths = ["./schemas/020_types.sql"]',
        "[experimental.pgdelta]",
        "enabled = true",
      ].join("\n"),
    );
    expect(diffEngine(pgdelta)).toBe("pg-delta");
    expect(await schemaPaths(dir, pgdelta)).toEqual({
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
    const custom = tomlWith(
      [
        "[experimental.pgdelta]",
        'enabled = "true"',
        'declarative_schema_path = "./schemas/030_crm/"',
      ].join("\n"),
    );
    expect((await schemaPaths(dir, custom)).files).toEqual([
      "supabase/schemas/030_crm/a.sql",
      "supabase/schemas/030_crm/b.sql",
    ]);
    const missing = tomlWith(
      '[experimental.pgdelta]\nenabled = true\ndeclarative_schema_path = "./db"',
    );
    expect(await schemaPaths(dir, missing)).toEqual({
      configured: false,
      files: [],
      unlisted: [],
    });
  });
});

describe("migrationCommand", () => {
  const tomlWith = (text: string): SupabaseToml => ({
    path: "supabase/config.toml",
    text,
    document: parseToml(text),
    parser: "smol-toml",
  });

  it("names the command of the configured diff engine", () => {
    expect(diffEngine(undefined)).toBe("migra");
    expect(migrationCommand(undefined, "add_tags")).toBe(
      "supabase db diff -f add_tags",
    );
    expect(
      migrationCommand(tomlWith("[experimental.pgdelta]\nenabled = false")),
    ).toBe("supabase db diff");
    expect(
      migrationCommand(
        tomlWith("[experimental.pgdelta]\nenabled = true"),
        "add_tags",
      ),
    ).toBe("supabase db schema declarative sync -f add_tags");
  });
});
