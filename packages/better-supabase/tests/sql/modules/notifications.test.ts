import { describe, expect, it } from "vitest";

import type { KitsConfig } from "../../../src/config/kits.ts";

import {
  customContracts,
  moduleBody,
  renderKit,
} from "../../../src/sql/kit.ts";

const body = (kits: KitsConfig = {}) => moduleBody("notifications", { kits })!;

const CENTRAKIT: KitsConfig = {
  notifications: {
    mode: "adopt",
    schema: "public",
    idType: "uuid",
    columns: {
      events: { actor: "actor_user_id", data: "metadata" },
      recipients: { user: "recipient_user_id" },
    },
    options: {
      topic: "org:{tenantId}:notifications:{userId}",
      channels: ["in_app", "email"],
    },
  },
};

describe("notifications module", () => {
  it("owns its tables with RLS and keeps notify for the definer", () => {
    const sql = body();
    expect(sql).toContain(
      'create table if not exists "better_supabase"."notification_events" (',
    );
    expect(sql).toContain('"data" jsonb not null default');
    expect(sql).toContain("notification_events_key_idx");
    expect(sql).toContain(
      'grant update ("read_at", "dismissed_at") on "better_supabase"."notification_recipients" to authenticated;',
    );
    expect(sql).toContain("notification_deliveries");
    expect(sql).toContain("notification_subscriptions");
    expect(sql).toContain("notification_preferences");
    expect(sql).toMatch(/function "better_supabase"\."notify"\(.*jsonb\)/);
    expect(sql).toContain("security definer");
    expect(sql).toContain("perform realtime.send(");
    expect(sql).toContain("'notifications:' || new.\"user_id\"::text");
  });

  it("adopts CentraKit's tables and its tenant topic", () => {
    const sql = body(CENTRAKIT);
    expect(sql).not.toContain("create table if not exists");
    expect(sql).toContain('"public"."notification_events"');
    expect(sql).toContain(
      `'org:' || new."organization_id"::text || ':notifications:' || new."recipient_user_id"::text`,
    );
    expect(sql).toContain("'notification_created'");
    expect(sql).toContain("'notification_updated'");
  });

  it("drops the tables mapped to null and the columns it can live without", () => {
    const sql = body({
      notifications: {
        tables: { deliveries: null, subscriptions: null, preferences: null },
        columns: {
          events: { key: null, priority: null },
          recipients: { resolvedAt: null },
        },
        options: { realtime: "none" },
      },
    });
    expect(sql).not.toContain("notification_deliveries");
    expect(sql).not.toContain("notification_subscriptions");
    expect(sql).not.toContain('"idempotency_key"');
    expect(sql).not.toContain("realtime.send(");
    expect(sql).toContain("drop trigger if exists");
  });

  it("adds the recipients table to the publication in changes mode", () => {
    expect(
      body({ notifications: { options: { realtime: "changes" } } }),
    ).toContain("alter publication supabase_realtime add table");
  });

  it("checks permissions and emits through the outbox when they are installed", () => {
    const plain = renderKit(["notifications"]).at(-1)!.contents;
    expect(plain).not.toContain("member_can");
    expect(plain).not.toContain("emit_event");
    const files = renderKit(["access", "outbox", "notifications"]);
    const sql = files.find((file) =>
      file.path.includes("notifications"),
    )!.contents;
    expect(sql).toContain("member_can");
    expect(sql).toMatch(
      /create policy [\s\S]*better_supabase\.can\('tenant', /,
    );
    expect(sql).not.toMatch(/create policy [^;]*member_can/);
    expect(sql).toContain("'notifications.send'");
    expect(sql).toContain("emit_event('notification.created'");
  });

  it("retries deliveries with backoff and gives up after max attempts", () => {
    const sql = body();
    expect(sql).toContain(
      '"next_attempt_at" timestamptz not null default now()',
    );
    expect(sql).toContain('and d."next_attempt_at" <= now()');
    expect(sql).toMatch(/v_status := 'failed'/);
    expect(sql).toContain("'The lease ran out on the last attempt'");
    expect(sql).toContain(
      'drop function if exists "better_supabase"."complete_notification_delivery"(uuid, text, text, text, text);',
    );
    const plain = body({
      notifications: {
        columns: { deliveries: { nextAttemptAt: null, attempts: null } },
      },
    });
    expect(plain).not.toContain("next_attempt_at");
    expect(plain).not.toContain("v_status := 'failed'");
  });

  it("resolves preferences in one query, caps recipients and pages by (created_at, id)", () => {
    const sql = body();
    expect(sql).toContain("select distinct on (x, c)");
    expect(sql).toContain("case c when 'in_app' then true else false end");
    expect(sql).toContain("NOTIFICATION_TOO_MANY_RECIPIENTS");
    expect(sql).toContain("> 1000 then");
    expect(sql).toContain("before_id uuid default null");
    expect(sql).toContain('function "better_supabase"."purge_notifications"');
    expect(
      body({
        notifications: {
          options: { channelDefaults: { email: true }, maxRecipients: 50 },
        },
      }),
    ).toContain(
      "case c when 'email' then true when 'in_app' then true else false end",
    );
    expect(() =>
      body({ notifications: { options: { maxRecipients: 0 } } }),
    ).toThrow(/maxRecipients/);
  });

  it("rejects options it would splice into SQL or can't honor", () => {
    expect(() =>
      body({ notifications: { options: { topic: "notifications" } } }),
    ).toThrow(/\{userId\}/);
    expect(() =>
      body({ notifications: { options: { topic: "n:{userId}'; drop" } } }),
    ).toThrow(/topic/);
    expect(() =>
      body({
        notifications: {
          options: { topic: "org:{tenantId}:{userId}" },
          columns: { recipients: { tenant: null } },
        },
      }),
    ).toThrow(/no tenant column/);
    expect(() =>
      body({ notifications: { options: { realtime: "pusher" } } }),
    ).toThrow(/realtime/);
  });

  it("renders nothing in custom mode and lists the contract the app must provide", () => {
    const custom: KitsConfig = { notifications: { mode: "custom" } };
    expect(moduleBody("notifications", { kits: custom })).toBe(undefined);
    const [contract] = customContracts(["notifications"], { kits: custom });
    expect(contract!.functions.map((fn) => fn.name)).toEqual([
      "notify",
      "notification_enabled",
      "list_notifications",
      "notification_counts",
      "mark_notifications_read",
      "dismiss_notifications",
      "purge_notifications",
      "resolve_notifications",
      "set_notification_subscription",
      "set_notification_preference",
      "claim_notification_deliveries",
      "complete_notification_delivery",
    ]);
    const [minimal] = customContracts(["notifications"], {
      kits: {
        notifications: {
          mode: "custom",
          tables: { deliveries: null, subscriptions: null, preferences: null },
          columns: { recipients: { resolvedAt: null } },
        },
      },
    });
    expect(minimal!.functions).toHaveLength(7);
  });

  it("skips the recipient read filter under the permdock model", () => {
    const notify = (kits: KitsConfig) =>
      renderKit(["access", "notifications"], { kits }).find((file) =>
        file.path.includes("notifications"),
      )!.contents;
    expect(notify({})).toContain("better_supabase.member_can(x, v_tenant,");
    const permdock = notify({
      access: {
        model: "permdock",
        permdock: { schema: "permdock", scope: "organization" },
      },
    });
    expect(permdock).not.toContain("better_supabase.member_can(x,");
    expect(permdock).toContain(
      "better_supabase.member_can(auth.uid(), v_tenant,",
    );
    expect(permdock).toContain(
      "-- The permdock model answers for the caller only, so recipients are not",
    );
  });
});
