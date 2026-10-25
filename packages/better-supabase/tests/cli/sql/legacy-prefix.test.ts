import { describe, expect, it } from "vitest";

import {
  legacyBlocksTableSql,
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

  it("skips the old permission cap claim the access functions still read", () => {
    expect(
      legacyPrefixNames(
        "coalesce(jwt -> 'bsb_permission_cap', jwt -> 'bs_permission_cap')",
      ),
    ).toEqual([]);
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

  it("renames event triggers such as the audit block's sql_drop trigger", () => {
    expect(sql).toContain("from pg_event_trigger e");
    expect(sql).toContain(
      "select 1 from pg_event_trigger f where f.evtname = 'bsb_' || substr(e.evtname, 4)",
    );
    expect(sql).toContain(
      "execute format('alter event trigger %I rename to %I', r.name, 'bsb_' || substr(r.name, 4));",
    );
  });

  it("warns instead of failing on objects the migration role doesn't own", () => {
    expect(sql).toContain("exception when insufficient_privilege");
    expect(sql).toContain("raise warning");
  });
});

describe("legacyBlocksTableSql", () => {
  it("creates better_supabase.blocks and copies the rows of the old table", () => {
    expect(legacyBlocksTableSql).toContain(
      "create table if not exists better_supabase.blocks",
    );
    expect(legacyBlocksTableSql).toContain(
      "if to_regclass('better_supabase.modules') is not null",
    );
    expect(legacyBlocksTableSql).toContain("on conflict (name) do nothing");
  });
});
