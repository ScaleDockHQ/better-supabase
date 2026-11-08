import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { dbUrl, reachable, ROLES, USERS, withCentraKit } from "./stack.ts";

const live = await reachable();

describe.skipIf(!live)(
  "notification digests on CentraKit's delivery table",
  () => {
    const pool = new Pool({ connectionString: dbUrl, max: 2 });

    afterAll(() => pool.end());

    it("holds a daily email and folds it into a digest", async () => {
      await withCentraKit(pool, async (s) => {
        await s.as("owner");

        const organization = await s.value<string>(
          "better_supabase.create_organization($1)",
          [{ name: "Acme", slug: `acme-${USERS.owner.slice(0, 8)}` }],
        );

        await s.as("service");
        await s.rows(
          "insert into centrakit.organization_users (organization_id, user_id, role_id) values ($1, $2, $3)",
          [organization, USERS.member, ROLES.member],
        );

        await s.as("owner");
        await s.client.query(
          "select better_supabase.set_notification_cadence('task.assigned', 'email', 'daily')",
        );

        await s.as("member");

        const sent = await s.value<{ id: string } | null>(
          "better_supabase.send_notification($1)",
          [
            {
              type: "task.assigned",
              tenant: organization,
              recipients: [USERS.owner],
              subject_type: "task",
              subject_id: "t1",
              subject_label: "Close the books",
              channels: ["in_app", "email"],
            },
          ],
        );

        expect(sent?.id).toEqual(expect.any(String));
        await s.as("service");
        expect(
          await s.rows(
            "select channel, status from centrakit.notification_deliveries where organization_id = $1 order by channel",
            [organization],
          ),
        ).toEqual([
          { channel: "email", status: "held" },
          { channel: "in_app", status: "sent" },
        ]);

        await s.client.query(
          "update centrakit.notification_deliveries set created_at = now() - interval '2 days' where organization_id = $1 and channel = 'email'",
          [organization],
        );

        expect(
          await s.value<{ digests: number; items: number }>(
            "better_supabase.run_notification_digests()",
          ),
        ).toEqual({ digests: 1, items: 1 });

        expect(
          await s.rows(
            "select status from centrakit.notification_deliveries where organization_id = $1 and channel = 'email'",
            [organization],
          ),
        ).toEqual([{ status: "digested" }]);
        expect(
          await s.rows(
            "select channel, cadence, item_count, status from better_supabase.notification_digests where tenant_id = $1",
            [organization],
          ),
        ).toEqual([
          {
            channel: "email",
            cadence: "daily",
            item_count: 1,
            status: "pending",
          },
        ]);
      });
    });
  },
);
