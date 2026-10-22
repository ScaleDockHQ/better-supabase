import { describe, expect, it } from "vitest";

import {
  legacyPrefixNames,
  legacyPrefixSql,
} from "../../../src/cli/sql/legacy-prefix.ts";

describe("legacyPrefixNames", () => {
  it("collects each bs_ name once, sorted, and skips bsb_ and longer words", () => {
    const text = `
      drop trigger if exists bs_audit on public.notes;
      create trigger bs_audit after insert on public.notes;
      create policy bs_session_active on public.notes;
      create policy bsb_already on public.notes;
      select subs_total, jobs_queue;
    `;

    expect(legacyPrefixNames(text)).toEqual(["bs_audit", "bs_session_active"]);
  });

  it("returns nothing for text without the old prefix", () => {
    expect(legacyPrefixNames("create trigger bsb_audit")).toEqual([]);
  });
});

describe("legacyPrefixSql", () => {
  const sql = legacyPrefixSql(["bs_audit", "bs_session_active"]);

  it("passes the installed names and the runtime prefixes", () => {
    expect(sql).toContain("array['bs_audit', 'bs_session_active']::text[]");
    expect(sql).toContain("'bs_broadcast_'");
    expect(sql).toContain("'bs_json_'");
  });

  it("renames to bsb_ only while the new name is free", () => {
    expect(sql).toContain("'bsb_' || substr(");
    expect(sql).toMatch(/not exists/u);
  });

  it("warns instead of failing on objects the migration role doesn't own", () => {
    expect(sql).toContain("exception when insufficient_privilege");
    expect(sql).toContain("raise warning");
  });
});
