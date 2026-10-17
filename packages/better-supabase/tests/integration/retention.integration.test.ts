import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import {
  createRetention,
  sqlTransport,
} from "../../src/blocks/data-lifecycle/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

describe.skipIf(!live)("retention policies and legal holds", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("keeps rows for a tenant's policy and skips held tenants in the purges", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["outbox", "audit", "data-lifecycle"]);
      const [a, b] = [crypto.randomUUID(), crypto.randomUUID()];

      const emit = async (tenant: string, age: string) => {
        const id = await s.value<string>(
          "better_supabase.emit_event('test.retained', '{}'::jsonb, tenant => $1)",
          [tenant],
        );

        await s.client.query("set local session_replication_role = replica");
        await s.client.query(
          `update better_supabase.outbox_events set created_at = now() - $2::interval where id = $1`,
          [id, age],
        );
        await s.client.query("set local session_replication_role = origin");

        return id;
      };

      await emit(a, "10 days");
      await emit(b, "10 days");
      await emit(b, "100 days");

      await s.service();
      await s.client.query("set local role service_role");
      const retention = createRetention({ transport: sqlTransport(s.sql) });

      const policy = await retention
        .setPolicy("outbox", "60 days", { organizationId: b })
        .orThrow();

      expect(policy).toMatchObject({
        kind: "outbox",
        keep: "60 days",
        organizationId: b,
        plan: undefined,
      });
      await retention.setPolicy("outbox", "1 day").orThrow();
      expect(await retention.policies("outbox").orThrow()).toHaveLength(2);

      // The global policy beats the 30-day default for a, and b keeps 60 days.
      expect(
        await s.value<number>(
          "better_supabase.purge_outbox(older_than => '30 days')",
        ),
      ).toBe(2);

      const left = await s.rows<{ organization_id: string }>(
        "select organization_id from better_supabase.outbox_events where type = 'test.retained'",
      );

      expect(left).toEqual([{ organization_id: b }]);

      const hold = await retention
        .placeHold({ reason: "Litigation", organizationId: b })
        .orThrow();

      expect(hold).toMatchObject({ organizationId: b, kind: undefined });
      await s.client.query("reset role");
      await emit(b, "200 days");
      await s.client.query("set local role service_role");
      expect(await s.value<number>("better_supabase.purge_outbox()")).toBe(0);

      const released = await retention.releaseHold(hold.id).orThrow();
      expect(released?.releasedAt).toBeDefined();
      expect(await retention.releaseHold(hold.id).orThrow()).toBeUndefined();
      expect(await retention.holds().orThrow()).toEqual([]);
      expect(
        await retention.holds({ includeReleased: true }).orThrow(),
      ).toHaveLength(1);
      expect(await s.value<number>("better_supabase.purge_outbox()")).toBe(1);
      expect(
        await retention.removePolicy("outbox", { organizationId: b }).orThrow(),
      ).toBe(true);
      expect(await retention.removePolicy("outbox").orThrow()).toBe(true);
      expect(await retention.removePolicy("outbox").orThrow()).toBe(false);
    } finally {
      await s.close();
    }
  });

  it("holds audit events and refuses to purge a held organization", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["audit", "data-lifecycle"]);
      const tenant = crypto.randomUUID();
      await s.client.query(
        "select better_supabase.audit_event('system.retained', tenant => $1)",
        [tenant],
      );
      await s.client.query("set local session_replication_role = replica");
      await s.client.query(
        "update better_supabase.audit_events set occurred_at = now() - interval '3 years' where organization_id = $1",
        [tenant],
      );
      await s.client.query("set local session_replication_role = origin");
      await s.service();
      await s.client.query("set local role service_role");
      const retention = createRetention({ transport: sqlTransport(s.sql) });
      await retention.placeHold({ reason: "Audit", kind: "audit" }).orThrow();
      const purge = "better_supabase.purge_audit_log(older_than => '1 year')";
      expect(await s.value<number>(purge)).toBe(0);
      await retention
        .setPolicy("audit", "5 years", { organizationId: tenant })
        .orThrow();
      const [active] = await retention.holds().orThrow();
      await retention.releaseHold(active!.id).orThrow();
      expect(await s.value<number>(purge)).toBe(0);
      await retention
        .removePolicy("audit", { organizationId: tenant })
        .orThrow();
      expect(await s.value<number>(purge)).toBe(1);

      await retention
        .placeHold({ reason: "Dispute", organizationId: tenant })
        .orThrow();
      await s.client.query("reset role");
      await s.client.query(
        "insert into better_supabase.organization_deletions (organization_id, requested_by, purge_after) values ($1, null, now() - interval '1 day')",
        [tenant],
      );
      await s.client.query("set local role service_role");
      expect(
        await s.hint("select better_supabase.purge_organization($1)", [tenant]),
      ).toBe("ORGANIZATION_LEGAL_HOLD");
    } finally {
      await s.close();
    }
  });

  it("runs every module purge with the helpers in place", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install([
        "outbox",
        "webhooks-out",
        "webhook-inbox",
        "jobs",
        "usage",
        "notifications",
        "workflows",
        "trash",
        "audit",
        "data-lifecycle",
      ]);
      await s.client.query(
        "select better_supabase.ensure_job_queue('retained')",
      );
      await s.service();
      await s.client.query("set local role service_role");

      for (const purge of [
        "purge_outbox()",
        "purge_webhook_deliveries()",
        "purge_webhooks()",
        "purge_job_archive('retained')",
        "purge_usage_history()",
        "purge_notifications()",
        "purge_workflow_runs()",
        "purge_expired_trash()",
        "purge_audit_log()",
      ]) {
        await expect(
          s.rows(`select better_supabase.${purge}`),
        ).resolves.toHaveLength(1);
      }
    } finally {
      await s.close();
    }
  });
});
