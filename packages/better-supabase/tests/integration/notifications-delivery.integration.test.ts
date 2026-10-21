import type { StandardSchemaV1 } from "@standard-schema/spec";

import { Pool } from "pg";
import { afterAll, beforeEach, afterEach, describe, expect, it } from "vitest";

import type {
  DeliveryTransport,
  EmailMessage,
} from "../../src/blocks/notifications/index.ts";
import type { SubscriberPolicy } from "../../src/core/contracts/authorization-hooks.ts";
import type { ModuleLayout } from "../../src/sql/module-types.ts";
import type { TestUser } from "./block-session.ts";

import {
  createNotifications,
  sqlTransport,
} from "../../src/blocks/notifications/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();
const DENIED = /permission denied|Grant the required privileges/;

const LAYOUT: ModuleLayout = {
  modules: {
    notifications: {
      options: {
        topic: "organization:{tenantId}:notifications:{userId}",
        channels: ["in_app", "email"],
        channelDefaults: { email: true },
      },
    },
  },
};

const anything: StandardSchemaV1<{ title: string }> = {
  "~standard": {
    version: 1,
    vendor: "test",
    validate: (value) => ({ value: value as { title: string } }),
  },
};

describe.skipIf(!live)("notification email delivery", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  let s: BlockSession;
  let owner: TestUser;
  let member: TestUser;
  let bounced: TestUser;
  let organization: string;
  beforeEach(async () => {
    s = await BlockSession.open(pool);
    await s.install(["organizations", "notifications"], LAYOUT);
    owner = await s.user("owner");
    member = await s.user("member");
    bounced = await s.user("bounced");
    organization = await s.organization(owner, { member, member2: bounced });
  });
  afterEach(() => s.close());

  afterAll(() => pool.end());

  const mailer = (audience?: SubscriberPolicy) => {
    const sent: { message: EmailMessage; idempotencyKey: string }[] = [];

    const transport: DeliveryTransport = {
      apiVersion: 1,
      channel: "email",
      provider: "test",
      send(message, { idempotencyKey }) {
        sent.push({ message, idempotencyKey });

        return { providerMessageId: `m-${idempotencyKey}` };
      },
    };

    const notifications = createNotifications({
      transport: sqlTransport(s.sql),
      types: { "task.assigned": anything },
      render: (item) => ({ title: `Assigned: ${item.subject?.label ?? ""}` }),
      email: {
        transport,
        from: "Acme <hi@acme.test>",
        unsubscribe: () => ({ url: "https://acme.test/unsubscribe" }),
      },
      ...(audience === undefined ? {} : { audience }),
    });

    return { notifications, sent };
  };

  const notify = async (
    notifications: ReturnType<typeof mailer>["notifications"],
  ): Promise<void> => {
    await s.as(owner);
    await notifications
      .send("task.assigned", {
        tenant: organization,
        recipients: [member.id, bounced.id],
        subject: { type: "task", id: "t1", label: "Paint" },
        data: { title: "Paint" },
        channels: ["in_app", "email"],
      })
      .orThrow();
    await s.service();
  };

  const deliveries = () =>
    s.rows<{
      user_id: string;
      id: string;
      status: string;
      error: string | null;
    }>(
      `select r.user_id, d.id, d.status, d.error
         from better_supabase.notification_deliveries d
         join better_supabase.notification_recipients r on r.id = d.recipient_id
        where d.channel = 'email'
        order by r.user_id`,
    );

  it("skips a suppressed address, records why, and keys each send by its delivery id", async () => {
    const { notifications, sent } = mailer();
    await s.service();
    expect(
      await notifications
        .suppress({
          address: bounced.email.toUpperCase(),
          reason: "bounce",
          provider: "resend",
          providerEventId: "msg_1",
        })
        .orThrow(),
    ).toBe(true);
    expect(
      await notifications
        .suppress({ address: bounced.email, reason: "complaint" })
        .orThrow(),
    ).toBe(false);

    await notify(notifications);
    expect(await notifications.deliver()).toEqual({
      sent: 1,
      skipped: 1,
      failed: 0,
    });

    const rows = await deliveries();
    const memberRow = rows.find((row) => row.user_id === member.id)!;
    const bouncedRow = rows.find((row) => row.user_id === bounced.id)!;
    expect(bouncedRow).toMatchObject({
      status: "skipped",
      error: "suppressed: bounce",
    });
    expect(memberRow.status).toBe("sent");
    expect(sent).toHaveLength(1);
    expect(sent[0]!.idempotencyKey).toBe(memberRow.id);
    expect(sent[0]!.message).toMatchObject({
      to: member.email,
      subject: "Assigned: Paint",
      category: "notification",
      headers: {
        "Auto-Submitted": "auto-generated",
        "List-Unsubscribe": "<https://acme.test/unsubscribe>",
        "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
      },
    });

    expect(await notifications.unsuppress(bounced.email).orThrow()).toBe(true);
    expect(await notifications.suppressions().orThrow()).toEqual([]);
  });

  it("checks recipients through audience before sending", async () => {
    const { notifications, sent } = mailer((_event, subscribers) =>
      subscribers.filter((subscriber) => subscriber.principal !== bounced.id),
    );

    await notify(notifications);
    expect(await notifications.deliver()).toEqual({
      sent: 1,
      skipped: 1,
      failed: 0,
    });
    expect(sent.map((entry) => entry.message.to)).toEqual([member.email]);
    expect(
      (await deliveries()).find((row) => row.user_id === bounced.id),
    ).toMatchObject({ status: "skipped", error: "audience" });
  });

  it("shows users their own suppressions and lets only the service write them", async () => {
    await s.service();
    await s.value(
      "better_supabase.suppress_notification_address($1, 'bounce')",
      [bounced.email],
    );
    await s.value(
      "better_supabase.suppress_notification_address('nobody@example.test', 'manual')",
    );

    await s.asRole(bounced);
    expect(
      await s.rows(
        "select address, user_id, reason from better_supabase.notification_suppressions",
      ),
    ).toEqual([
      { address: bounced.email, user_id: bounced.id, reason: "bounce" },
    ]);
    expect(
      await s.value<unknown[]>(
        "better_supabase.list_notification_suppressions()",
      ),
    ).toMatchObject([{ address: bounced.email, reason: "bounce" }]);

    await s.asRole(member);
    expect(
      await s.rows("select 1 from better_supabase.notification_suppressions"),
    ).toEqual([]);
    expect(
      await s.hint(
        "insert into better_supabase.notification_suppressions (address, user_id, reason) values ($1, $2, 'manual')",
        [member.email, member.id],
      ),
    ).toMatch(DENIED);
    expect(
      await s.hint(
        "delete from better_supabase.notification_suppressions where address = $1",
        [bounced.email],
      ),
    ).toMatch(DENIED);
    expect(
      await s.hint(
        "better_supabase.suppress_notification_address($1, 'manual')",
        [member.email],
      ),
    ).toMatch(DENIED);
    expect(
      await s.hint("better_supabase.unsuppress_notification_address($1)", [
        bounced.email,
      ]),
    ).toMatch(DENIED);

    await s.client.query("reset role");
    await s.client.query("set local role service_role");
    expect(
      await s.value<boolean>(
        "better_supabase.suppress_notification_address($1, 'complaint')",
        [member.email],
      ),
    ).toBe(true);
    expect(
      await s.hint(
        "better_supabase.suppress_notification_address($1, 'spam')",
        [member.email],
      ),
    ).toBe("NOTIFICATION_SUPPRESSION_REASON");
    expect(
      await s.hint(
        "better_supabase.suppress_notification_address(' ', 'bounce')",
      ),
    ).toBe("NOTIFICATION_SUPPRESSION_ADDRESS");
  });
});
