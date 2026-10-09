import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { AUDIT_CATEGORIES } from "../../src/sql/context.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const ACTION_MODULES = [
  "organizations",
  "invitations",
  "settings",
  "flags",
  "billing",
  "credentials",
  "connectors",
  "agents",
  "ai-providers",
  "ai-chat",
  "webhooks-in",
  "webhooks-out",
  "announcements",
  "api-keys",
  "waitlist",
  "sso",
] as const;

/** The event types `actions` records, each once. */
const RECORDED = [
  "organization.created",
  "organization_setting.updated",
  "organization_setting.reset",
  "flag.saved",
  "flag.override_set",
  "flag.deleted",
  "billing.customer_linked",
  "credential.set",
  "credential.deleted",
  "connector.saved",
  "connector.deleted",
  "agent.saved",
  "agent.published",
  "agent.deleted",
  "ai_provider_key.saved",
  "ai_provider_key.deleted",
  "ai_tool_policy.set",
  "incoming_webhook.created",
  "incoming_webhook.deleted",
  "webhook.secret_rotated",
  "announcement.saved",
  "announcement.deleted",
  "api_key.created",
  "api_key.revoked",
  "invitation.created",
  "waitlist.approved",
  "invite_code.created",
  "organization.domain_added",
] as const;

/** Runs one security-relevant action of each module; returns the tenant. */
async function actions(s: BlockSession): Promise<string> {
  const suffix = crypto.randomUUID().slice(0, 8);
  const owner = await s.user("owner");
  const organization = await s.organization(owner);

  await s.as(owner);
  await s.value(
    "better_supabase.set_organization_setting($1, 'theme', '\"dark\"'::jsonb)",
    [organization],
  );
  await s.value("better_supabase.reset_organization_setting($1, 'theme')", [
    organization,
  ]);
  const agent = await s.value<{ id: string }>(
    "better_supabase.save_agent($1, null, $2)",
    [organization, { slug: `agent-${suffix}`, name: "Agent" }],
  );
  await s.value("better_supabase.publish_agent($1, 'organization')", [
    agent.id,
  ]);
  await s.value("better_supabase.delete_agent($1)", [agent.id]);
  await s.value("better_supabase.create_invitation($1, $2)", [
    organization,
    `invitee-${suffix}@example.test`,
  ]);
  await s.value("better_supabase.add_organization_domain($1, $2)", [
    organization,
    `acme-${suffix}.test`,
  ]);

  await s.service();
  await s.value("better_supabase.save_flag($1, '{}')", [`beta-${suffix}`]);
  await s.value("better_supabase.set_flag_override($1, 'on', $2)", [
    `beta-${suffix}`,
    organization,
  ]);
  await s.value("better_supabase.delete_flag($1)", [`beta-${suffix}`]);
  await s.value("better_supabase.link_billing_customer($1, $2)", [
    organization,
    `cus_${suffix}`,
  ]);
  await s.value("better_supabase.credential_set('vault', $1, 'secret')", [
    `acme-${suffix}`,
  ]);
  await s.value("better_supabase.credential_delete('vault', $1)", [
    `acme-${suffix}`,
  ]);
  const server = await s.value<{ id: string }>(
    "better_supabase.save_connector_server($1, null, $2)",
    [organization, { name: "Docs", url: "https://mcp.example.com/mcp" }],
  );
  await s.value("better_supabase.delete_connector_server($1)", [server.id]);
  const key = await s.value<{ key: { id: string } }>(
    "better_supabase.save_ai_provider_key($1, 'openai', $2)",
    [organization, { provider: "vault", name: `openai-${suffix}` }],
  );
  await s.value("better_supabase.delete_ai_provider_key($1)", [key.key.id]);
  await s.value("better_supabase.set_ai_tool_policy($1, 'send_email', 'ask')", [
    organization,
  ]);
  const hook = await s.value<{ id: string }>(
    "better_supabase.create_incoming_webhook($1, 'Form')",
    [organization],
  );
  await s.value("better_supabase.delete_incoming_webhook($1)", [hook.id]);
  const [endpoint] = await s.rows<{ id: string }>(
    `insert into better_supabase.webhook_endpoints (organization_id, name, url, event_types)
     values ($1, 'Hook', 'https://hooks.example.com', '{*}') returning id`,
    [organization],
  );
  await s.value("better_supabase.rotate_webhook_secret($1)", [endpoint!.id]);
  const announcement = await s.value<{ id: string }>(
    'better_supabase.save_announcement(null, \'{"title": "Hi", "body": "Hello"}\')',
  );
  await s.value("better_supabase.delete_announcement($1)", [announcement.id]);
  const apiKey = await s.value<{ id: string }>(
    "better_supabase.create_api_key('CI', $1, encode(sha256('secret'::bytea), 'hex'), $2)",
    [crypto.randomUUID().replaceAll("-", "").slice(0, 16), organization],
  );
  await s.value("better_supabase.revoke_api_key($1)", [apiKey.id]);
  await s.value("better_supabase.join_waitlist($1)", [
    `waiting-${suffix}@example.test`,
  ]);
  const entry = await s.value<string>(
    "(select id from better_supabase.waitlist_entries where email = $1)",
    [`waiting-${suffix}@example.test`],
  );
  await s.value("better_supabase.decide_waitlist_entry($1, true)", [entry]);
  await s.value("better_supabase.create_invite_code($1)", [`CODE-${suffix}`]);
  return organization;
}

describe.skipIf(!live)("audited module actions", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("records each action once in the audit log and once in the outbox", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install([...ACTION_MODULES, "audit", "outbox"]);
      const started = await s.value<string>("now()::text");
      await actions(s);
      await s.service();
      const audited = await s.rows<{
        type: string;
        category: string;
        count: string;
      }>(
        `select event_type as type, category, count(*)::text as count
         from better_supabase.audit_events
         where occurred_at >= $1::timestamptz and event_type = any ($2)
         group by event_type, category`,
        [started, RECORDED],
      );
      const emitted = await s.rows<{ type: string; count: string }>(
        `select type, count(*)::text as count from better_supabase.outbox_events
         where created_at >= $1::timestamptz and type = any ($2)
         group by type`,
        [started, RECORDED],
      );
      const once = (rows: readonly { type: string; count: string }[]) =>
        Object.fromEntries(rows.map((row) => [row.type, row.count]));
      const expected = Object.fromEntries(RECORDED.map((type) => [type, "1"]));
      expect(once(audited)).toEqual(expected);
      expect(once(emitted)).toEqual(expected);
      for (const row of audited) {
        expect(AUDIT_CATEGORIES).toContain(row.category);
      }
    } finally {
      await s.close();
    }
  });

  it("runs the same actions without the audit and outbox modules", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(ACTION_MODULES);
      const started = await s.value<string>("now()::text");
      await expect(actions(s)).resolves.toBeTypeOf("string");
      await s.service();
      // The local stack keeps both tables from its own schema; nothing writes to them here.
      expect(
        await s.value<number>(
          `(select count(*)::int from better_supabase.audit_events
            where occurred_at >= $1::timestamptz and event_type = any ($2))
           + (select count(*)::int from better_supabase.outbox_events
            where created_at >= $1::timestamptz and type = any ($2))`,
          [started, RECORDED],
        ),
      ).toBe(0);
    } finally {
      await s.close();
    }
  });
});
