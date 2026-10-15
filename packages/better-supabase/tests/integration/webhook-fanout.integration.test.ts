import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

describe.skipIf(!live)("webhook fan-out read check", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("queues an event only for endpoints whose owner can read its subject", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["access", "organizations", "outbox", "webhooks-out"]);
      const owner = await s.user("owner");
      const admin = await s.user("admin");
      const organization = await s.organization(owner, { admin });

      const userEndpoint = async (
        who: typeof owner,
        name: string,
      ): Promise<string> => {
        await s.asRole(who);
        const [row] = await s.rows<{ id: string }>(
          `insert into better_supabase.webhook_endpoints (organization_id, name, url, event_types)
           values ($1, $2, $3, '{invoice.*}') returning id`,
          [organization, name, `https://${name}.example.com/hook`],
        );
        return row!.id;
      };
      const ownerHook = await userEndpoint(owner, "owner");
      const adminHook = await userEndpoint(admin, "admin");

      await s.service();
      const serviceEndpoint = async (
        name: string,
        permissions: string[] | null,
      ): Promise<string> => {
        const [row] = await s.rows<{ id: string }>(
          `insert into better_supabase.webhook_endpoints (organization_id, name, url, event_types, permissions)
           values ($1, $2, $3, '{invoice.*}', $4) returning id`,
          [organization, name, `https://${name}.example.com/hook`, permissions],
        );
        return row!.id;
      };
      const ledgerHook = await serviceEndpoint("ledger", ["ledgers.*"]);
      await serviceEndpoint("crm", null);
      await serviceEndpoint("search", ["projects.read"]);

      const owners = await s.rows<{ id: string; created_by: string | null }>(
        "select id, created_by from better_supabase.webhook_endpoints where organization_id = $1",
        [organization],
      );
      expect(owners.find((row) => row.id === ownerHook)?.created_by).toBe(
        owner.id,
      );
      expect(owners.find((row) => row.id === adminHook)?.created_by).toBe(
        admin.id,
      );
      expect(owners.filter((row) => row.created_by === null)).toHaveLength(3);

      const queued = await s.value<number>(
        "better_supabase.publish_webhook_event('invoice.paid', $1, $2, $3, 'invoices/1', 'ledgers.read')",
        [{ invoiceId: 1 }, organization, crypto.randomUUID()],
      );
      expect(queued).toBe(2);
      const deliveries = await s.rows<{ endpoint_id: string; subject: string }>(
        "select endpoint_id, subject from better_supabase.webhook_deliveries where organization_id = $1",
        [organization],
      );
      expect(deliveries.map((row) => row.endpoint_id).sort()).toEqual(
        [ownerHook, ledgerHook].sort(),
      );
      expect(deliveries.every((row) => row.subject === "invoices/1")).toBe(
        true,
      );

      const open = await s.value<number>(
        "better_supabase.publish_webhook_event('invoice.created', $1, $2, $3)",
        [{ invoiceId: 2 }, organization, crypto.randomUUID()],
      );
      expect(open).toBe(5);
    } finally {
      await s.close();
    }
  });
});
