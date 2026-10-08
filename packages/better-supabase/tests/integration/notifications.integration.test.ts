import type { StandardSchemaV1 } from "@standard-schema/spec";

import { Pool, type PoolClient } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { NotificationMessage } from "../../src/blocks/notifications/index.ts";
import type { SqlClient } from "../../src/postgres/executor.ts";
import type { ModuleLayout } from "../../src/sql/registry.ts";

import {
  createNotifications,
  sqlTransport,
} from "../../src/blocks/notifications/index.ts";
import { renderModules } from "../../src/sql/registry.ts";

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

const LAYOUT: ModuleLayout = {
  modules: {
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
      for (const file of renderModules(
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

      // A sender may add a level for another member, only where none is set.
      await client.query("savepoint follow");
      const follow = (target: string, level: string, ifAbsent: boolean) =>
        s.hint(
          "select better_supabase.set_notification_subscription('task', 'f1', $1, $2, $3, $4)",
          [level, organization, target, ifAbsent],
        );
      const levels = () =>
        s.value<Record<string, string>>(
          "(select coalesce(jsonb_object_agg(user_id, level), '{}') from better_supabase.notification_subscriptions where subject_id = 'f1')",
        );
      await s.as("member");
      expect(await follow(USERS.watcher, "participating", true)).toBe(
        "NOTIFICATION_FORBIDDEN",
      );
      expect(await follow(USERS.member, "ignore", false)).toBe("no error");
      await s.as("owner");
      expect(await follow(USERS.watcher, "participating", false)).toBe(
        "NOTIFICATION_FORBIDDEN",
      );
      expect(await follow(USERS.outsider, "participating", true)).toBe(
        "NOTIFICATION_FORBIDDEN",
      );
      expect(await follow(USERS.watcher, "participating", true)).toBe(
        "no error",
      );
      expect(await follow(USERS.member, "all", true)).toBe("no error");
      expect(await follow(USERS.watcher, "all", true)).toBe("no error");
      expect(await levels()).toEqual({
        [USERS.member]: "ignore",
        [USERS.watcher]: "participating",
      });
      await client.query("rollback to savepoint follow");

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
      await client.query("savepoint composers");
      const named = await s.notify({
        ...task,
        type: "task.mentioned",
        recipients: [USERS.member],
        watchers: false,
      });
      expect(await s.recipients(named!)).toEqual([USERS.member]);
      const skipping = await s.notify({
        ...task,
        type: "task.noted",
        recipients: [USERS.member],
        exclude: [USERS.member],
      });
      expect(await s.recipients(skipping!)).toEqual([USERS.watcher]);
      expect(
        await s.notify({
          ...task,
          type: "task.noted",
          recipients: [USERS.member],
          exclude: [USERS.member],
          watchers: false,
        }),
      ).toBeNull();
      await client.query("rollback to savepoint composers");
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
      ).toEqual({ unread: 2, actionable: 1, actionable_subjects: 1 });
      const [latest] = inbox as unknown as { id: string }[];
      expect(
        await s.value("better_supabase.mark_notifications_read($1)", [
          [latest!.id],
        ]),
      ).toMatchObject({
        count: 1,
        items: [{ id: latest!.id, read_at: expect.any(String) }],
      });
      expect(
        await s.value("better_supabase.list_notifications($1, 'unread')", [
          organization,
        ]),
      ).toHaveLength(1);
      expect(
        await s.value("better_supabase.dismiss_notifications($1)", [
          [latest!.id],
        ]),
      ).toMatchObject({ count: 1, items: [{ id: latest!.id }] });
      expect(
        await s.value("better_supabase.get_notification($1)", [latest!.id]),
      ).toMatchObject({ id: latest!.id, type: "approval.requested" });
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
      ).toEqual({ count: 1, items: [] });

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

  it("derives UUIDv8 event ids from the key without a key column", async () => {
    const client = await pool.connect();
    const s = new Session(client);
    try {
      await client.query("begin");
      for (const who of ["owner", "member"] as const) {
        await client.query(
          `insert into auth.users (id, email, aud, role, instance_id, email_confirmed_at)
           values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', now())`,
          [USERS[who], email(who)],
        );
      }
      for (const file of renderModules(["organizations", "notifications"], {
        modules: {
          notifications: { columns: { events: { key: null } } },
        },
      }))
        await client.query(file.contents);
      await s.as("owner");
      const organization = await s.value<string>(
        "better_supabase.create_organization($1)",
        [{ name: "Acme", slug: `acme-v8-${USERS.owner.slice(0, 8)}` }],
      );
      await client.query(
        "insert into better_supabase.memberships (organization_id, user_id, role) values ($1, $2, 'member')",
        [organization, USERS.member],
      );
      const keyed = {
        type: "task.assigned",
        tenant: organization,
        recipients: [USERS.member],
        key: "task-1",
      };
      const first = await s.notify(keyed);
      expect(first).toMatch(
        /^[0-9a-f]{8}-[0-9a-f]{4}-8[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
      );
      expect(await s.notify(keyed)).toBe(first);
      expect(
        await s.value("better_supabase.send_notification($1)", [keyed]),
      ).toEqual({ id: first, recipients: [USERS.member] });

      const legacy = await s.value<string>(
        "md5(coalesce($1::text, '') || ':' || 'task-2')::uuid",
        [organization],
      );
      await s.as("service");
      await client.query(
        "insert into better_supabase.notification_events (id, organization_id, type) values ($1, $2, 'task.assigned')",
        [legacy, organization],
      );
      await s.as("owner");
      expect(await s.notify({ ...keyed, key: "task-2" })).toBe(legacy);
      expect(await s.recipients(legacy)).toEqual([USERS.member]);
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
      avatars: { url: "http://127.0.0.1:55421", bucket: "users" },
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
      for (const file of renderModules(
        ["organizations", "profiles", "notifications"],
        LAYOUT,
      ))
        await client.query(file.contents);
      await client.query("select better_supabase.backfill_profiles()");
      await client.query(
        "update auth.users set raw_user_meta_data = jsonb_build_object('avatar_path', 'evil', 'picture', 'https://img.test/a.png') where id = $1",
        [USERS.owner],
      );
      await client.query(
        "update better_supabase.profiles set avatar_path = $2 where id = $1",
        [USERS.owner, `${USERS.owner}/avatar.webp`],
      );
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

      const stored = await notifications
        .send("task.assigned", {
          tenant: organization,
          recipients: [USERS.member, USERS.owner],
          subject: { type: "task", id: "t9", label: "Paint" },
          data: { title: "Paint" },
          channels: ["in_app", "email"],
        })
        .orThrow();
      expect(stored!.recipients).toEqual([USERS.member]);
      const id = stored!.id;
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
      const [withActor] = await notifications
        .list({ tenant: organization, include: ["actor"] })
        .orThrow();
      expect(withActor!.actor).toMatchObject({
        id: USERS.owner,
        username: expect.any(String),
        avatarPath: `${USERS.owner}/avatar.webp`,
        avatarUrl: `http://127.0.0.1:55421/storage/v1/object/public/users/${USERS.owner}/avatar.webp`,
      });
      expect(
        await notifications.counts({ tenant: organization }).orThrow(),
      ).toEqual({
        unread: 1,
        actionable: 0,
        actionableSubjects: 0,
      });
      const read = await notifications
        .markRead({ tenant: organization })
        .orThrow();
      expect(read.count).toBe(1);
      expect(read.items[0]).toMatchObject({ id: item!.id, eventId: id });
      expect(read.items[0]!.readAt).not.toBeNull();
      expect(
        await notifications.get(item!.id, { include: ["actor"] }).orThrow(),
      ).toMatchObject({
        id: item!.id,
        text: { title: "Assigned: Paint" },
        actor: { id: USERS.owner },
      });
      await s.as("owner");
      expect(await notifications.get(item!.id).orThrow()).toBeNull();

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
  it("pages, searches and settles the inbox and reads the caller's settings", async () => {
    const client = await pool.connect();
    const s = new Session(client);
    const sql: SqlClient = {
      async queryRaw<T>(text: string, params: unknown[] = []) {
        const { rows } = await client.query(text, params);
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
    const notifications = createNotifications({
      transport: sqlTransport(sql),
      types: { "task.assigned": anything, "approval.requested": anything },
      actionable: ["approval.requested"],
    });
    try {
      await client.query("begin");
      for (const who of ["owner", "member", "outsider"] as const) {
        await client.query(
          `insert into auth.users (id, email, aud, role, instance_id, email_confirmed_at)
           values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', now())`,
          [USERS[who], email(who)],
        );
      }
      for (const file of renderModules(
        ["organizations", "notifications"],
        LAYOUT,
      ))
        await client.query(file.contents);
      await s.as("owner");
      const organization = await s.value<string>(
        "better_supabase.create_organization($1)",
        [{ name: "Acme", slug: `acme-inbox-${USERS.owner.slice(0, 8)}` }],
      );
      await client.query(
        "insert into better_supabase.memberships (organization_id, user_id, role) values ($1, $2, 'member')",
        [organization, USERS.member],
      );
      const send = (
        type: "task.assigned" | "approval.requested",
        subject: { type: string; id: string; label: string },
        summary: string,
      ) =>
        notifications
          .send(type, {
            tenant: organization,
            recipients: [USERS.member],
            subject,
            summary,
            data: { title: summary },
          })
          .orThrow();
      await send(
        "task.assigned",
        { type: "task", id: "t1", label: "Fix the roof" },
        "Roof 100% done",
      );
      await send(
        "task.assigned",
        { type: "task", id: "t2", label: "Paint the fence" },
        "Fence",
      );
      await send(
        "approval.requested",
        { type: "invoice", id: "i1", label: "Invoice 7" },
        "Approve invoice",
      );
      await send(
        "approval.requested",
        { type: "invoice", id: "i1", label: "Invoice 7" },
        "Approve invoice again",
      );

      await s.as("member");
      const first = await notifications
        .page({ tenant: organization, limit: 2 })
        .orThrow();
      expect(first.total).toBe(4);
      expect(first.items).toHaveLength(2);
      const second = await notifications
        .page({ tenant: organization, limit: 2, offset: 2 })
        .orThrow();
      expect(second.total).toBe(4);
      expect(
        [...first.items, ...second.items].map((item) => item.summary),
      ).toEqual([
        "Approve invoice again",
        "Approve invoice",
        "Fence",
        "Roof 100% done",
      ]);
      expect(
        (
          await notifications
            .list({ tenant: organization, search: "roof" })
            .orThrow()
        ).map((item) => item.subject?.id),
      ).toEqual(["t1"]);
      expect(
        await notifications
          .page({ tenant: organization, search: "100%" })
          .orThrow(),
      ).toMatchObject({ total: 1 });
      expect(
        await notifications
          .page({ tenant: organization, search: "1_0" })
          .orThrow(),
      ).toMatchObject({ total: 0 });
      expect(
        (
          await notifications
            .list({ tenant: organization, subjectTypes: ["invoice"] })
            .orThrow()
        ).map((item) => item.summary),
      ).toEqual(["Approve invoice again", "Approve invoice"]);
      expect(
        await notifications.counts({ tenant: organization }).orThrow(),
      ).toEqual({ unread: 4, actionable: 2, actionableSubjects: 1 });

      const fence = second.items[0]!;
      expect(fence.summary).toBe("Fence");
      expect(
        await notifications.markRead({ ids: [fence.id] }).orThrow(),
      ).toMatchObject({ count: 1, items: [{ id: fence.id }] });
      expect(
        (
          await notifications
            .list({ tenant: organization, read: true })
            .orThrow()
        ).map((item) => item.summary),
      ).toEqual(["Fence"]);
      expect(
        await notifications.markUnread({ ids: [fence.id] }).orThrow(),
      ).toMatchObject({ count: 1, items: [{ id: fence.id, readAt: null }] });
      expect(
        await notifications.markUnread({ ids: [fence.id] }).orThrow(),
      ).toEqual({ count: 0, items: [] });
      await s.as("outsider");
      expect(
        await notifications.markUnread({ ids: [fence.id] }).orThrow(),
      ).toEqual({ count: 0, items: [] });
      expect(await notifications.get(fence.id).orThrow()).toBeNull();
      expect(
        await notifications.page({ tenant: organization }).orThrow(),
      ).toEqual({ items: [], total: 0 });

      await s.as("member");
      expect(await notifications.dismiss([fence.id]).orThrow()).toMatchObject({
        count: 1,
        items: [{ id: fence.id }],
      });
      await s.as("owner");
      expect(
        await notifications
          .resolve({
            type: "approval.requested",
            subject: { type: "invoice", id: "i1" },
            tenant: organization,
          })
          .orThrow(),
      ).toEqual({ count: 2, items: [] });
      await s.as("member");
      const settled = await notifications
        .page({ tenant: organization, status: "settled" })
        .orThrow();
      expect(settled.items.map((item) => item.summary)).toEqual([
        "Approve invoice again",
        "Approve invoice",
        "Fence",
      ]);
      const summaries = async (options: {
        readonly read?: boolean;
        readonly resolved?: boolean;
        readonly dismissed?: boolean | null;
      }) =>
        (
          await notifications
            .list({ tenant: organization, ...options })
            .orThrow()
        ).map((item) => item.summary);
      expect(await summaries({ resolved: true })).toEqual([
        "Approve invoice again",
        "Approve invoice",
      ]);
      expect(await summaries({ resolved: true, read: false })).toEqual([]);
      expect(await summaries({ resolved: false, read: false })).toEqual([
        "Roof 100% done",
      ]);
      expect(await summaries({ dismissed: true })).toEqual(["Fence"]);
      expect(await summaries({ dismissed: null })).toHaveLength(4);
      expect(
        (
          await notifications
            .page({ tenant: organization, resolved: false, dismissed: null })
            .orThrow()
        ).items.map((item) => item.summary),
      ).toEqual(["Fence", "Roof 100% done"]);
      expect(
        (await notifications.list({ tenant: organization }).orThrow()).map(
          (item) => item.summary,
        ),
      ).toEqual(["Approve invoice again", "Approve invoice", "Roof 100% done"]);
      expect(
        await notifications.counts({ tenant: organization }).orThrow(),
      ).toMatchObject({ actionable: 0, actionableSubjects: 0 });

      await notifications
        .subscribe({
          subject: { type: "task", id: "t1" },
          level: "all",
          tenant: organization,
        })
        .orThrow();
      await notifications
        .subscribe({
          subject: { type: "invoice", id: "i1" },
          level: "ignore",
          tenant: organization,
        })
        .orThrow();
      await notifications
        .setPreference({ type: "*", channel: "email", enabled: false })
        .orThrow();
      await notifications
        .setPreference({
          type: "task.assigned",
          channel: "email",
          enabled: true,
          tenant: organization,
        })
        .orThrow();
      const subscriptions = await notifications
        .subscriptions({ tenant: organization })
        .orThrow();
      expect(
        subscriptions
          .map((entry) => [entry.subject.id, entry.level])
          .toSorted((a, b) => a[0]!.localeCompare(b[0]!)),
      ).toEqual([
        ["i1", "ignore"],
        ["t1", "all"],
      ]);
      expect(
        await notifications
          .subscriptions({ subject: { type: "task", id: "t1" } })
          .orThrow(),
      ).toMatchObject([{ level: "all", tenant: organization }]);
      expect(
        await notifications.preferences({ tenant: organization }).orThrow(),
      ).toEqual([
        { type: "*", channel: "email", enabled: false, tenant: null },
        {
          type: "task.assigned",
          channel: "email",
          enabled: true,
          tenant: organization,
        },
      ]);
      await s.as("outsider");
      expect(await notifications.subscriptions().orThrow()).toEqual([]);
      expect(await notifications.preferences().orThrow()).toEqual([]);
    } finally {
      await client.query("rollback");
      client.release();
    }
  });
});
