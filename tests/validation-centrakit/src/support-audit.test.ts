import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { dbUrl, reachable, USERS, withCentraKit } from "./stack.ts";

const live = await reachable();

describe.skipIf(!live)(
  "support sessions and audit on CentraKit's tables",
  () => {
    const pool = new Pool({ connectionString: dbUrl, max: 2 });
    afterAll(() => pool.end());

    it("lets system support view as a user and audits it in audit_logs", async () => {
      await withCentraKit(pool, async (s) => {
        await s.as("owner");
        const org = await s.value<string>(
          "better_supabase.create_organization($1)",
          [{ name: "Acme", slug: `acme-${USERS.owner.slice(0, 8)}` }],
        );

        await s.as("member");
        expect(
          await s.hint("better_supabase.start_support_session($1, 'curious')", [
            USERS.owner,
          ]),
        ).toBe("SUPPORT_FORBIDDEN");

        await s.as("support");
        const session = await s.value<{
          target_user_id: string;
          read_only: boolean;
        }>(
          "better_supabase.start_support_session($1, 'Ticket 42', tenant => $2)",
          [USERS.owner, org],
        );
        expect(session).toMatchObject({
          target_user_id: USERS.owner,
          read_only: true,
        });
        expect(
          await s.rows(
            `select event_type, category, source, scope, actor_kind, actor_id::text, target_id, organization_id::text
           from centrakit.audit_logs where event_type = 'support.started'`,
          ),
        ).toEqual([
          {
            event_type: "support.started",
            category: "security",
            source: "saas",
            scope: "organization",
            actor_kind: "user",
            actor_id: USERS.support,
            target_id: USERS.owner,
            organization_id: org,
          },
        ]);
      });
    });

    it("records semantic events once, with restricted details apart, readable per organization", async () => {
      await withCentraKit(pool, async (s) => {
        await s.as("owner");
        const org = await s.value<string>(
          "better_supabase.create_organization($1)",
          [{ name: "Acme", slug: `acme-${USERS.owner.slice(0, 8)}` }],
        );

        await s.as("service");
        const record = () =>
          s.value<string>(
            `better_supabase.audit_event('invoice.sent', 'billing', target_type => 'invoice', record_id => 'inv-1',
             tenant => $1, metadata => '{"amount": 100}', idempotency_key => 'invoice.sent:inv-1',
             restricted => '{"ip": "203.0.113.7"}', actor_id => $2)`,
            [org, USERS.owner],
          );
        const first = await record();
        expect(await record()).toBe(first);
        expect(
          await s.rows(
            `select l.event_type, l.category, l.safe_metadata, d.restricted_metadata
           from centrakit.audit_logs l join centrakit.audit_log_restricted_details d on d.event_id = l.id
           where l.id = $1`,
            [first],
          ),
        ).toEqual([
          {
            event_type: "invoice.sent",
            category: "billing",
            safe_metadata: { amount: 100 },
            restricted_metadata: { ip: "203.0.113.7" },
          },
        ]);

        await s.client.query("set local role authenticated");
        const visible = () =>
          s.value<number>(
            "(select count(*)::int from centrakit.audit_logs where event_type = 'invoice.sent')",
          );
        await s.as("owner");
        expect(await visible()).toBe(1);
        await s.as("member");
        expect(await visible()).toBe(0);
        await s.as("support");
        expect(await visible()).toBe(1);
        await s.client.query("reset role");
      });
    });
  },
);
