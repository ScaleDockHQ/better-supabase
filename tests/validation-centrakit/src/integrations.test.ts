import { sqlTransport, vaultCredentials } from "better-supabase/credentials";
import { defineTopic } from "better-supabase/realtime";
import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import {
  dbUrl,
  reachable,
  type Session,
  USERS,
  withCentraKit,
} from "./stack.ts";

const live = await reachable();

const createOrganization = async (s: Session): Promise<string> => {
  await s.as("owner");
  return s.value<string>("better_supabase.create_organization($1)", [
    { name: "Acme", slug: `acme-${USERS.owner.slice(0, 8)}` },
  ]);
};

describe.skipIf(!live)("integrations on CentraKit's tables", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("keeps credentials in integration_credentials with Vault ids", async () => {
    await withCentraKit(pool, async (s) => {
      const organization = await createOrganization(s);
      await s.as("service");
      const vault = vaultCredentials({
        transport: sqlTransport(s.sql),
        cacheMs: 0,
      });
      const ref = {
        provider: "vault",
        secret: "openai:api-key",
        tenant: organization,
      };
      const app = { subject: { type: "app" as const } };

      await vault.set(ref, "sk-1").orThrow();
      await vault.set(ref, "sk-2").orThrow();
      expect(
        await s.rows(
          `select provider, key, organization_id::text as organization, vault_secret_id is not null as vault
           from centrakit.integration_credentials`,
        ),
      ).toEqual([
        { provider: "openai", key: "api-key", organization, vault: true },
      ]);
      expect((await vault.getToken(ref, app).orThrow()).token).toBe("sk-2");

      const [row] = await s.rows<{ id: string }>(
        "select vault_secret_id::text as id from centrakit.integration_credentials",
      );
      expect(await vault.revoke(ref, app).orThrow()).toBe(true);
      expect(
        await s.rows(
          "select count(*)::int as n from vault.secrets where id = $1",
          [row?.id],
        ),
      ).toEqual([{ n: 0 }]);
    });
  });

  it("manages inbound webhooks per organization and stores their messages once", async () => {
    await withCentraKit(pool, async (s) => {
      const organization = await createOrganization(s);
      const endpoint = await s.value<{ id: string; token: string }>(
        "better_supabase.create_incoming_webhook($1, 'Stripe', 'none')",
        [organization],
      );
      expect(
        await s.rows(
          `select name, organization_id::text as organization, token_digest <> $1 as hashed
           from centrakit.inbound_webhooks`,
          [endpoint.token],
        ),
      ).toEqual([{ name: "Stripe", organization, hashed: true }]);

      await s.as("member");
      expect(
        await s.hint(
          "better_supabase.create_incoming_webhook($1, 'Other', 'none')",
          [organization],
        ),
      ).toBe("WEBHOOK_IN_FORBIDDEN");

      await s.as("service");
      expect(
        await s.rows(
          "select id::text, tenant from better_supabase.incoming_webhook_by_token($1)",
          [endpoint.token],
        ),
      ).toEqual([{ id: endpoint.id, tenant: organization }]);

      const receive = () =>
        s.rows<{ duplicate: boolean }>(
          `select duplicate from better_supabase.receive_webhook('stripe', 'evt_1', 'invoice.paid',
             '{"amount": 100}', tenant => $1)`,
          [organization],
        );
      expect(await receive()).toEqual([{ duplicate: false }]);
      expect(await receive()).toEqual([{ duplicate: true }]);
      expect(
        await s.rows(
          `select source, event_type, tenant, status from better_supabase.list_webhooks($1)`,
          [organization],
        ),
      ).toEqual([
        {
          source: "stripe",
          event_type: "invoice.paid",
          tenant: organization,
          status: "pending",
        },
      ]);

      const [claimed] = await s.rows<{ id: string; attempts: number }>(
        "select id, attempts from better_supabase.claim_webhooks('stripe', 'worker-1')",
      );
      expect(
        await s.value<boolean>(
          "better_supabase.complete_webhook($1, 'worker-1', $2)",
          [claimed?.id, claimed?.attempts],
        ),
      ).toBe(true);
      expect(
        await s.rows(
          "select status, organization_id::text as organization from centrakit.inbound_webhook_events",
        ),
      ).toEqual([{ status: "processed", organization }]);
    });
  });

  it("broadcasts endpoint changes to the organization's topic from a trigger", async () => {
    await withCentraKit(pool, async (s) => {
      const webhooks = defineTopic("organization:{organizationId}:webhooks");
      await s.rows(
        webhooks.trigger("centrakit.inbound_webhooks", {
          events: ["insert"],
          event: "webhook.created",
        }),
      );
      const organization = await createOrganization(s);
      await s.value("better_supabase.create_incoming_webhook($1, 'Stripe')", [
        organization,
      ]);
      expect(
        await s.rows(
          `select event, payload->'record'->>'name' as name, private
           from realtime.messages where topic = $1`,
          [webhooks.topic({ organizationId: organization })],
        ),
      ).toEqual([{ event: "webhook.created", name: "Stripe", private: true }]);
    });
  });
});
