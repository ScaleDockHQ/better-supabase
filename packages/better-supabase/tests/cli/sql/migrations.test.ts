import { describe, expect, it } from "vitest";

import { migrationStamp, stampAfter } from "../../../src/cli/sql/migrations.ts";

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
