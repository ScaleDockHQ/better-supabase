import { describe, expect, it } from "vitest";

import { postgresCacheSql } from "../../src/cache-postgres/sql.ts";

describe("postgresCacheSql", () => {
  it("enables RLS and revokes the client roles on every table", () => {
    const sql = postgresCacheSql();

    expect(sql.match(/enable row level security/g)).toHaveLength(3);
    expect(sql).toContain('revoke all on "public"."bsb_cache_leases"');
    expect(sql).toContain(
      'grant execute on function "public"."bsb_cache_lease"(text, text, bigint, bigint) to service_role',
    );
    expect(sql).toContain("revoke all on");
    expect(sql).toContain("anon, authenticated");
    expect(sql).not.toContain("cron.schedule");
  });

  it("schedules pruning and honours names", () => {
    const sql = postgresCacheSql({
      schema: "private",
      entriesTable: "e",
      tagsTable: "t",
      prune: true,
    });

    expect(sql).toContain('"private"."e"');
    expect(sql).toContain("cron.schedule");
  });
});
