import { describe, expect, it } from "vitest";

import { moduleBody } from "../../../src/sql/render.ts";
import { unnamedChecks } from "../unnamed-checks.ts";

const body = (): string => moduleBody("notifications", { modules: {} })!;

describe("notification digests", () => {
  it("adds a cadence to the preferences", () => {
    const sql = body();

    expect(unnamedChecks(sql)).toContain(
      `"cadence" text not null default 'immediate' check ("cadence" in ('immediate', 'daily', 'weekly', 'off'))`,
    );
    expect(sql).toContain("'cadence', p.\"cadence\"");
  });

  it("holds a daily or weekly delivery and lets off drop the channel", () => {
    const sql = body();

    expect(sql).toContain(
      "in ('pending', 'sent', 'failed', 'skipped', 'held', 'digested')",
    );
    expect(sql).toContain("in ('daily', 'weekly') then 'held' else 'pending'");
    expect(sql).toContain(`"cadence" is distinct from 'off'`);
  });

  it("folds held deliveries into one digest per member and channel", () => {
    const sql = body();

    expect(sql).toContain("create table");
    expect(sql).toContain('"notification_digests"');
    expect(sql).toContain("run_notification_digests");
    expect(sql).toContain(`"status" = 'digested'`);
    expect(sql).toContain("for update of d skip locked");
  });

  it("keeps the sender's functions to the service role", () => {
    const sql = body();

    expect(sql).toMatch(
      /revoke execute on function "better_supabase"\."?claim_notification_digests"?\(integer, interval, integer\) from public, anon, authenticated;/,
    );
    expect(sql).toMatch(
      /grant execute on function "better_supabase"\."?complete_notification_digest"?\(uuid, text, text, text, integer\) to service_role;/,
    );
  });
});
