import { describe, expect, it } from "vitest";

import { moduleBody } from "../../../src/sql/render.ts";

describe("webhook-inbox module", () => {
  const adopted = (columns: Record<string, string | null> = {}) =>
    moduleBody("webhook-inbox", {
      modules: {
        "webhook-inbox": {
          mode: "adopt",
          tables: { messages: "public.inbound_events" },
          columns: {
            messages: {
              messageId: "external_id",
              tenant: "organization_id",
              headers: null,
              maxAttempts: null,
              checkpoint: null,
              ...columns,
            },
          },
        },
      },
    })!;

  it("owns its table in managed mode and refuses renames there", () => {
    const sql = moduleBody("webhook-inbox")!;
    expect(sql).toContain(
      "create table if not exists better_supabase.webhook_inbox",
    );
    expect(sql).toContain("returns setof better_supabase.webhook_inbox");
    expect(() =>
      moduleBody("webhook-inbox", {
        modules: {
          "webhook-inbox": { columns: { messages: { tenant: "org_id" } } },
        },
      }),
    ).toThrow(/mode "adopt"/);
  });

  it("adopts an app's table with renamed and missing columns", () => {
    const sql = adopted();
    expect(sql).not.toContain("create table");
    expect(sql).toContain('insert into "public"."inbound_events"');
    expect(sql).toContain("pg_catalog.pg_advisory_xact_lock");
    expect(sql).toContain(
      'w."organization_id" is not distinct from receive_webhook.tenant',
    );
    expect(sql).toContain("returns table (id bigint, source text");
    expect(sql).toContain(
      `w."external_id", w."event_type", w."payload", '{}'::jsonb`,
    );
    expect(sql).toContain("then 'dead' else 'pending' end");
    expect(sql).toContain(">= 8");
    expect(sql).not.toContain('"checkpoint"');
    expect(sql).toContain(
      "drop function if exists better_supabase.claim_webhooks(text, text, integer, interval);",
    );
  });

  it("needs the columns its leases run on", () => {
    expect(() => adopted({ lockedUntil: null })).toThrow(/lockedUntil/);
  });
});
