import { describe, expect, it } from "vitest";

import {
  DECLARED_DEFAULTS,
  DECLARED_DEFAULTS_FN,
  declaredRank,
} from "../../src/sql/declared-defaults.ts";

describe("declared defaults", () => {
  it("keeps the table behind a security definer reader", () => {
    expect(DECLARED_DEFAULTS).toContain(
      "create table better_supabase.declared_defaults",
    );
    expect(DECLARED_DEFAULTS).toContain("enable row level security");
    expect(DECLARED_DEFAULTS).toContain("security definer");
    expect(DECLARED_DEFAULTS).toContain(DECLARED_DEFAULTS_FN.split(".")[1]);
  });

  it("derives a two digit rank from the ordinal", () => {
    expect(declaredRank("d.ord")).toContain("|| 'V'");
  });
});
