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
    expect(sql).toContain('"metadata" jsonb not null default');
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
    expect(sql).toContain(
      "'notifications:' || new.\"recipient_user_id\"::text",
    );
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
    expect(minimal!.functions).toHaveLength(6);
  });
});
