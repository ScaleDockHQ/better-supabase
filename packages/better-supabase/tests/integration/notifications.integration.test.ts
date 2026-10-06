import type { StandardSchemaV1 } from "@standard-schema/spec";

import { Pool, type PoolClient } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { NotificationMessage } from "../../src/blocks/notifications/index.ts";
import type { SqlClient } from "../../src/postgres/executor.ts";
import type { BlockLayout } from "../../src/sql/blocks.ts";

import {
  createNotifications,
  sqlTransport,
} from "../../src/blocks/notifications/index.ts";
import { renderBlocks } from "../../src/sql/blocks.ts";

const dbUrl =
  process.env["SUPABASE_DB_URL"] ??
  "postgresql://postgres:postgres@127.0.0.1:55422/postgres";

async function reachable(): Promise<boolean> {
  const pool = new Pool({
    connectionString: dbUrl,
    max: 1,
    connectionTimeoutMillis: 1000,
  });
  try {
    await pool.query("select 1");
    return true;
  } catch {
    return false;
  } finally {
    await pool.end();
  }
}

const live = await reachable();

const USERS = {
  owner: crypto.randomUUID(),
  member: crypto.randomUUID(),
  watcher: crypto.randomUUID(),
  outsider: crypto.randomUUID(),
} as const;
type Who = keyof typeof USERS;
const email = (who: Who) => `${who}-${USERS[who]}@example.test`;

const LAYOUT: BlockLayout = {
  blocks: {
    notifications: {
      options: {
        topic: "organization:{tenantId}:notifications:{userId}",
        channels: ["in_app", "email"],
        channelDefaults: { email: false },
      },
    },
  },
};

class Session {
  private readonly client: PoolClient;

  constructor(client: PoolClient) {
    this.client = client;
  }

  async as(who: Who | "service"): Promise<void> {
    const claims =
      who === "service"
        ? { role: "service_role" }
        : { sub: USERS[who], role: "authenticated", email: email(who) };
    await this.client.query(
      "select set_config('request.jwt.claims', $1, true)",
      [JSON.stringify(claims)],
    );
  }

  async value<T>(sql: string, params: unknown[] = []): Promise<T> {
    const { rows } = await this.client.query<{ value: T }>(
      `select ${sql} as value`,
      params,
    );
    return rows[0]!.value;
  }

  async hint(sql: string, params: unknown[] = []): Promise<string> {
    await this.client.query("savepoint attempt");
    try {
      await this.client.query(sql, params);
    } catch (error) {
      await this.client.query("rollback to savepoint attempt");
      const failure = error as {
        code?: string;
        hint?: string;
        message: string;
      };
      return failure.code === "42501" &&
        !failure.hint?.startsWith("NOTIFICATION")
        ? "42501"
        : (failure.hint ?? failure.message);
    }
    await this.client.query("release savepoint attempt");
    return "no error";
  }

  notify(notification: Record<string, unknown>): Promise<string | null> {
    return this.value("better_supabase.notify($1)", [notification]);
  }

  recipients(event: string): Promise<string[]> {
    return this.value(
      "(select coalesce(array_agg(user_id order by user_id), '{}') from better_supabase.notification_recipients where event_id = $1)",
      [event],
    );
  }
}

describe.skipIf(!live)("notifications", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("sends, filters, deduplicates and delivers notifications", async () => {
    const client = await pool.connect();
    const s = new Session(client);
    try {
      await client.query("begin");
      for (const who of Object.keys(USERS) as Who[]) {
        await client.query(
          `insert into auth.users (id, email, aud, role, instance_id, email_confirmed_at)
           values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', now())`,
          [USERS[who], email(who)],
        );
      }
      for (const file of renderBlocks(
        ["organizations", "outbox", "notifications"],
        LAYOUT,
      ))
        await client.query(file.contents);

      await s.as("owner");
      const organization = await s.value<string>(
        "better_supabase.create_organization($1)",
        [{ name: "Acme", slug: `acme-${USERS.owner.slice(0, 8)}` }],
      );
      await client.query(
        "insert into better_supabase.memberships (organization_id, user_id, role) values ($1, $2, 'member'), ($1, $3, 'member')",
        [organization, USERS.member, USERS.watcher],
      );
      const task = {
        type: "task.assigned",
        tenant: organization,
        subject_type: "task",
        subject_id: "t1",
        subject_label: "Fix the roof",
      };

      await s.as("member");
      expect(
        await s.hint("select better_supabase.notify($1)", [
          { ...task, recipients: [USERS.owner] },
        ]),
      ).toBe("NOTIFICATION_FORBIDDEN");

      // The actor and non-members are left out; the key makes it idempotent.
      await s.as("owner");
      const first = await s.notify({
        ...task,
        key: "assign-1",
        recipients: [USERS.owner, USERS.member, USERS.outsider],
      });
      expect(first).toMatch(/^[0-9a-f-]{36}$/);
      expect(await s.recipients(first!)).toEqual([USERS.member]);
      expect(
        await s.notify({
          ...task,
          key: "assign-1",
          recipients: [USERS.member],
        }),
      ).toBe(first);
      expect(
        await s.value("better_supabase.notify($1)", [
          { ...task, recipients: [USERS.owner] },
        ]),
      ).toBeNull();
      expect(
        await s.hint("select better_supabase.notify($1)", [
          { ...task, priority: "panic", recipients: [USERS.member] },
        ]),
      ).toBe("NOTIFICATION_PRIORITY_UNKNOWN");

      // Watching with "all" adds the watcher; "ignore" removes the member.
      await s.as("watcher");
      await client.query(
        "select better_supabase.set_notification_subscription('task', 't1', 'all', $1)",
        [organization],
      );
      await s.as("member");
      await client.query(
        "select better_supabase.set_notification_subscription('task', 't1', 'ignore', $1)",
        [organization],
      );
      await client.query(
        "select better_supabase.set_notification_preference('*', 'email', true, $1)",
        [organization],
      );
      await s.as("owner");
      const second = await s.notify({
        ...task,
        type: "task.updated",
        activity: "all",
        recipients: [USERS.member],
      });
      expect(await s.recipients(second!)).toEqual([USERS.watcher]);

      await s.as("member");
      await client.query(
        "select better_supabase.set_notification_subscription('task', 't1', null, $1)",
        [organization],
      );
      await s.as("owner");
      const third = await s.notify({
        ...task,
        type: "approval.requested",
        recipients: [USERS.member, USERS.watcher],
      });
      const deliveries = await s.value<
        { user: string; channel: string; status: string }[]
      >(
        `(select jsonb_agg(jsonb_build_object('user', r.user_id, 'channel', d.channel, 'status', d.status) order by d.channel, r.user_id)
          from better_supabase.notification_deliveries d
          join better_supabase.notification_recipients r on r.id = d.recipient_id
          where r.event_id = $1)`,
        [third],
      );
      expect(deliveries).toEqual(
        [
          { user: USERS.member, channel: "email", status: "pending" },
          { user: USERS.member, channel: "in_app", status: "sent" },
          { user: USERS.watcher, channel: "in_app", status: "sent" },
        ].sort((a, b) =>
          a.channel === b.channel
            ? a.user.localeCompare(b.user)
            : a.channel.localeCompare(b.channel),
        ),
      );

      // The member's inbox, counts, read and dismiss.
      await s.as("member");
      const inbox = await s.value<{ type: string; subject_label: string }[]>(
        "better_supabase.list_notifications($1)",
        [organization],
      );
      expect(inbox.map((item) => item.type)).toEqual([
        "approval.requested",
        "task.assigned",
      ]);
      expect(inbox[1]).toMatchObject({
        subject_label: "Fix the roof",
        actor_id: USERS.owner,
      });

      // Pages by (created_at, id), so items created at the same instant are not skipped.
      await s.as("service");
      await client.query(
        "update better_supabase.notification_recipients set created_at = '2026-01-01T00:00:00Z' where user_id = $1",
        [USERS.member],
      );
      await s.as("member");
      const tied = await s.value<{ id: string }[]>(
        "better_supabase.list_notifications($1)",
        [organization],
      );
      const page = await s.value<{ id: string }[]>(
        "better_supabase.list_notifications($1, 'all', null, '2026-01-01T00:00:00Z', 50, $2)",
        [organization, tied[0]!.id],
      );
      expect(page.map((item) => item.id)).toEqual([tied[1]!.id]);
      expect(
        await s.value("better_supabase.notification_counts($1, $2)", [
          organization,
          ["approval.requested"],
        ]),
      ).toEqual({ unread: 2, actionable: 1 });
      const [latest] = inbox as unknown as { id: string }[];
      expect(
        await s.value("better_supabase.mark_notifications_read($1)", [
          [latest!.id],
        ]),
      ).toBe(1);
      expect(
        await s.value("better_supabase.list_notifications($1, 'unread')", [
          organization,
        ]),
      ).toHaveLength(1);
      expect(
        await s.value("better_supabase.dismiss_notifications($1)", [
          [latest!.id],
        ]),
      ).toBe(1);
      expect(
        await s.value("better_supabase.list_notifications($1)", [organization]),
      ).toHaveLength(1);

      // Clients read only their own rows and can't write events.
      await client.query("set local role authenticated");
      expect(
        await s.value(
          "(select count(*)::int from better_supabase.notification_recipients)",
        ),
      ).toBe(2);
      expect(
        await s.hint(
          "insert into better_supabase.notification_events (type) values ('spoof')",
        ),
      ).toBe("42501");
      await client.query("reset role");

      // A worker claims the email delivery with the address, then completes it.
      await s.as("service");
      const claimed = await s.value<
        { delivery_id: string; email: string; notification: { type: string } }[]
      >("better_supabase.claim_notification_deliveries('email')");
      expect(claimed).toHaveLength(1);
      expect(claimed[0]).toMatchObject({
        email: email("member"),
        notification: { type: "approval.requested" },
      });
      expect(
        await s.value<unknown[]>(
          "better_supabase.claim_notification_deliveries('email')",
        ),
      ).toEqual([]);
      await client.query(
        "select better_supabase.complete_notification_delivery($1, 'sent', 'resend', 'msg_1')",
        [claimed[0]!.delivery_id],
      );
      expect(
        await s.value(
          "(select status || '/' || provider_message_id from better_supabase.notification_deliveries where id = $1)",
          [claimed[0]!.delivery_id],
        ),
      ).toBe("sent/msg_1");

      // A retry waits for its backoff, and the last attempt fails the delivery.
      const id = claimed[0]!.delivery_id;
      await client.query(
        "update better_supabase.notification_deliveries set status = 'pending', attempts = 0, attempted_at = null where id = $1",
        [id],
      );
      const claimRetry =
        "better_supabase.claim_notification_deliveries('email', 50, '5 minutes', 2)";
      expect(await s.value<unknown[]>(claimRetry)).toHaveLength(1);
      expect(
        await s.value(
          "better_supabase.complete_notification_delivery($1, 'pending', null, null, 'smtp down', 2)",
          [id],
        ),
      ).toBe("pending");
      expect(
        await s.value(
          "(select next_attempt_at > now() from better_supabase.notification_deliveries where id = $1)",
          [id],
        ),
      ).toBe(true);
      expect(await s.value<unknown[]>(claimRetry)).toEqual([]);
      await client.query(
        "update better_supabase.notification_deliveries set next_attempt_at = now() - interval '1 second' where id = $1",
        [id],
      );
      expect(await s.value<unknown[]>(claimRetry)).toHaveLength(1);
      expect(
        await s.value(
          "better_supabase.complete_notification_delivery($1, 'pending', null, null, 'smtp down', 2)",
          [id],
        ),
      ).toBe("failed");

      // A worker that died on the last attempt leaves a failed delivery.
      await client.query(
        "update better_supabase.notification_deliveries set status = 'pending', attempted_at = now() - interval '1 hour' where id = $1",
        [id],
      );
      expect(await s.value<unknown[]>(claimRetry)).toEqual([]);
      expect(
        await s.value(
          "(select status || '/' || error from better_supabase.notification_deliveries where id = $1)",
          [id],
        ),
      ).toBe("failed/The lease ran out on the last attempt");

      await s.as("owner");
      expect(
        await s.value(
          "better_supabase.resolve_notifications('approval.requested', 'task', 't1', $1)",
          [organization],
        ),
      ).toBe(1);

      // Broadcasts reach the private topic, and the outbox has the event.
      expect(
        await s.value(
          "(select count(*)::int from realtime.messages where topic = $1 and event = 'notification_created')",
          [`organization:${organization}:notifications:${USERS.member}`],
        ),
      ).toBe(2);
      expect(
        await s.value(
          "(select count(*)::int from better_supabase.outbox_events where type = 'notification.created')",
        ),
      ).toBeGreaterThanOrEqual(3);

      // The purge deletes old notifications with their recipients and deliveries.
      await s.as("service");
      await client.query(
        "update better_supabase.notification_events set created_at = now() - interval '100 days'",
      );
      expect(
        await s.value<number>("better_supabase.purge_notifications()"),
      ).toBeGreaterThanOrEqual(2);
      expect(
        await s.value(
          "(select count(*)::int from better_supabase.notification_deliveries)",
        ),
      ).toBe(0);
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("works end to end through createNotifications and sqlTransport", async () => {
    const client = await pool.connect();
    const s = new Session(client);
    const sql: SqlClient = {
      async queryRaw<T>(text: string, params: unknown[] = []) {
        const { rows } = await client.query(text, params);
        // SAFETY: the test reads only the `value` column sqlTransport selects.
        return rows as T[];
      },
    };
    const anything: StandardSchemaV1<{ title: string }> = {
      "~standard": {
        version: 1,
        vendor: "test",
        validate: (value) => ({ value: value as { title: string } }),
      },
    };
    const sent: NotificationMessage[] = [];
    const notifications = createNotifications({
      transport: sqlTransport(sql),
      types: { "task.assigned": anything },
      render: (item) => ({ title: `Assigned: ${item.subject?.label ?? ""}` }),
      channels: [
        {
          apiVersion: 1,
          name: "email",
          send: (message) => {
            sent.push(message);
            return { provider: "test", providerMessageId: "m1" };
          },
        },
      ],
    });
    try {
      await client.query("begin");
      for (const who of ["owner", "member"] as const) {
        await client.query(
          `insert into auth.users (id, email, aud, role, instance_id, email_confirmed_at)
           values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', now())`,
          [USERS[who], email(who)],
        );
      }
      for (const file of renderBlocks(
        ["organizations", "notifications"],
        LAYOUT,
      ))
        await client.query(file.contents);
      await s.as("owner");
      const organization = await s.value<string>(
        "better_supabase.create_organization($1)",
        [{ name: "Acme", slug: `acme-e2e-${USERS.owner.slice(0, 8)}` }],
      );
      await client.query(
        "insert into better_supabase.memberships (organization_id, user_id, role) values ($1, $2, 'member')",
        [organization, USERS.member],
      );
      await client.query(
        "insert into better_supabase.notification_preferences (user_id, organization_id, type, channel, enabled) values ($1, null, '*', 'email', true)",
        [USERS.member],
      );

      const id = await notifications
        .send("task.assigned", {
          tenant: organization,
          recipients: [USERS.member],
          subject: { type: "task", id: "t9", label: "Paint" },
          data: { title: "Paint" },
          channels: ["in_app", "email"],
        })
        .orThrow();
      expect(id).toMatch(/^[0-9a-f-]{36}$/);

      await s.as("member");
      const [item] = await notifications
        .list({ tenant: organization })
        .orThrow();
      expect(item).toMatchObject({
        eventId: id,
        type: "task.assigned",
        subject: { type: "task", id: "t9", label: "Paint" },
        text: { title: "Assigned: Paint" },
        readAt: null,
      });
      expect(
        await notifications.counts({ tenant: organization }).orThrow(),
      ).toEqual({
        unread: 1,
        actionable: 0,
      });
      expect(
        await notifications.markRead({ tenant: organization }).orThrow(),
      ).toBe(1);

      await s.as("service");
      expect(await notifications.deliver()).toEqual({
        sent: 1,
        skipped: 0,
        failed: 0,
      });
      expect(sent[0]).toMatchObject({
        email: email("member"),
        text: { title: "Assigned: Paint" },
      });
    } finally {
      await client.query("rollback");
      client.release();
    }
  });
});
