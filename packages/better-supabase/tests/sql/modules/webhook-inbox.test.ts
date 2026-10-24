import { describe, expect, it } from "vitest";

import { moduleBody, renderBlocks } from "../../../src/sql/render.ts";

describe("webhook-inbox module", () => {
  const overApp = (columns: Record<string, string | null> = {}) =>
    renderBlocks(["webhook-inbox"], {
      ownTables: { "public.inbound_events": "app.sql" },
      modules: {
        "webhook-inbox": {
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
    })
      .filter((file) => file.module === "webhook-inbox")
      .map((file) => file.contents)
      .join("\n");

  it("owns its table in managed mode and refuses renames there", () => {
    const sql = moduleBody("webhook-inbox")!;
    expect(sql).toContain(
      "create table if not exists better_supabase.webhook_inbox",
    );
    expect(sql).toContain("returns jsonb");
    expect(sql).toContain("'id', w.id, 'source', w.source");
    expect(() =>
      moduleBody("webhook-inbox", {
        modules: {
          "webhook-inbox": { columns: { messages: { tenant: "org_id" } } },
        },
      }),
    ).toThrow(/declare your own table/);
  });

  it("runs over the app's table with renamed and missing columns", () => {
    const sql = overApp();
    expect(sql).not.toContain('create table if not exists "public"');
    expect(sql).toContain('insert into "public"."inbound_events"');
    expect(sql).toContain("pg_catalog.pg_advisory_xact_lock");
    expect(sql).toContain(
      'w."organization_id"::text is not distinct from receive_webhook.tenant',
    );
    expect(sql).toContain(
      `(jsonb_populate_record(null::"public"."inbound_events", jsonb_build_object('organization_id', receive_webhook.tenant)))."organization_id"`,
    );
    expect(sql).not.toContain("returns table");
    expect(sql).toContain(
      `'message_id', w."external_id", 'event_type', w."event_type", 'payload', w."payload", 'headers', '{}'::jsonb`,
    );
    expect(sql).toContain("then 'dead' else 'pending' end");
    expect(sql).toContain(">= 8");
    expect(sql).not.toContain('"checkpoint"');
    expect(sql).toContain(
      "drop function if exists better_supabase.claim_webhooks(text, text, integer, interval);",
    );
  });

  it("needs the columns its leases run on", () => {
    expect(() => overApp({ lockedUntil: null })).toThrow(/lockedUntil/);
  });
});
