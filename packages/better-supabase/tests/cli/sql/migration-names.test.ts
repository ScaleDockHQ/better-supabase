import { describe, expect, it } from "vitest";

import {
  hasMigrationSuffix,
  migrationFile,
  migrationStamp,
  stampAfter,
} from "../../../src/cli/sql/migration-names.ts";

describe("migrationStamp", () => {
  it("is the UTC timestamp the Supabase CLI prefixes migrations with", () => {
    expect(migrationStamp(new Date("2026-03-04T05:06:07.890Z"))).toBe(
      "20260304050607",
    );
  });
});

describe("stampAfter", () => {
  const now = new Date("2026-03-04T05:06:07.000Z");

  it("uses the clock when no migration is newer", () => {
    expect(stampAfter(["20250101000000_init.sql"], now)).toBe("20260304050607");
  });

  it("moves one second past a migration with the same stamp", () => {
    expect(stampAfter(["20260304050607_schema.sql"], now)).toBe(
      "20260304050608",
    );
  });

  it("counts any name that starts with 14 digits", () => {
    expect(stampAfter(["20260304050700-seeds.sql", "notes.md"], now)).toBe(
      "20260304050701",
    );
  });
});

describe("migrationFile", () => {
  const now = new Date("2026-03-04T05:06:07.000Z");
  const suffix = "_better_supabase_block_upgrade.sql";

  it("puts a hash of the statements before .sql and a free stamp first", () => {
    const first = migrationFile(
      ["20260304050607_other.sql"],
      now,
      suffix,
      "select 1;",
    );

    expect(first.exists).toBe(false);
    expect(first.name).toMatch(
      /^20260304050608_better_supabase_block_upgrade_[0-9a-f]{8}\.sql$/,
    );
  });

  it("returns the file an earlier run wrote for the same statements", () => {
    const written = migrationFile([], now, suffix, "-- a\nselect  1;").name;

    expect(
      migrationFile(
        [written],
        new Date(now.getTime() + 9e6),
        suffix,
        "-- b\nselect 1;",
      ),
    ).toEqual({ name: written, exists: true });
  });

  it("writes a new file when the statements change", () => {
    const written = migrationFile([], now, suffix, "select 1;").name;
    const next = migrationFile([written], now, suffix, "select 2;");

    expect(next.exists).toBe(false);
    expect(next.name).not.toBe(written);
    expect(next.name.slice(0, 14) > written.slice(0, 14)).toBe(true);
  });
});

describe("hasMigrationSuffix", () => {
  it("matches names with and without the hash", () => {
    const suffix = "_better_supabase_module_data.sql";

    expect(hasMigrationSuffix(`20260304050607${suffix}`, suffix)).toBe(true);
    expect(
      hasMigrationSuffix(
        "20260304050607_better_supabase_module_data_0a1b2c3d.sql",
        suffix,
      ),
    ).toBe(true);
    expect(hasMigrationSuffix("20260304050607_other.sql", suffix)).toBe(false);
  });
});
