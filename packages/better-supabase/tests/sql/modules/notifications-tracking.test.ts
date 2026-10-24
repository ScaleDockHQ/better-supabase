import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import {
  customContracts,
  moduleBody,
  renderBlocks,
} from "../../../src/sql/render.ts";
import { ownTablesOf } from "../../fixtures/own-tables.ts";

const body = (modules: AnyBlocksConfig = {}) =>
  moduleBody("notifications", { modules })!;

const overApp = (modules: AnyBlocksConfig) =>
  renderBlocks(["notifications"], { modules, ownTables: ownTablesOf(modules) })
    .filter((file) => file.module === "notifications")
    .map((file) => file.contents)
    .join("\n");

const rendered = (names: Parameters<typeof renderBlocks>[0]) =>
  renderBlocks(names)
    .filter((file) => file.module === "notifications")
    .map((file) => file.contents)
    .join("\n");

const DELIVERIES = '"better_supabase"."notification_deliveries"';
const EVENTS = '"better_supabase"."notification_delivery_events"';

const APP_TABLES: AnyBlocksConfig = {
  notifications: {
    schema: "public",
    idType: "uuid",
    columns: {
      events: { actor: "actor_user_id", data: "metadata" },
      recipients: { user: "recipient_user_id" },
    },
    options: { channels: ["in_app", "email"] },
  },
};

describe("notification delivery tracking", () => {
  it("adds the provider status, the template key and the provider lookup index to deliveries", () => {
    const sql = body();
    expect(sql).toContain(
      `alter table ${DELIVERIES} add column if not exists "provider_status" text check ("provider_status" in ('delayed', 'delivered', 'opened', 'clicked', 'bounced', 'complained'));`,
    );
    expect(sql).toContain(
      `alter table ${DELIVERIES} add column if not exists "provider_status_at" timestamptz;`,
    );
    expect(sql).toContain(
      `alter table ${DELIVERIES} add column if not exists "template_key" text;`,
    );
    expect(sql).toContain(
      `create index if not exists notification_deliveries_provider_message_idx on ${DELIVERIES} ("provider", "provider_message_id") where "provider_message_id" is not null;`,
    );
  });

  it("owns an events table that recipients read for their own deliveries", () => {
    const sql = body();
    expect(sql).toContain(`create table if not exists ${EVENTS} (`);
    expect(sql).toContain(
      `"delivery_id" uuid not null references ${DELIVERIES} ("id") on delete cascade`,
    );
    expect(sql).toContain(`"provider_event_id" text unique`);
    expect(sql).toContain(`grant select on ${EVENTS} to authenticated;`);
    expect(sql).not.toMatch(
      /grant (insert|update|delete)[^;]*notification_delivery_events"? to authenticated/,
    );
    expect(sql).toMatch(
      /create policy "bsb_notification_delivery_events_read"[^;]*r\."user_id" = \(select auth\.uid\(\)\)/,
    );
  });

  it("records provider events through a service-only function that suppresses and emits", () => {
    const sql = rendered(["outbox", "notifications"]);

    for (const kind of [
      "delivered",
      "opened",
      "clicked",
      "bounced",
      "complained",
      "delayed",
    ]) {
      expect(sql).toContain(`emit_event('notification.${kind}'`);
    }

    expect(sql).toContain(
      `create or replace function "better_supabase"."record_delivery_event"(provider text, provider_message_id text, kind text, provider_event_id text default null, occurred_at timestamptz default null, detail jsonb default '{}', suppress boolean default null)`,
    );
    expect(sql).toContain("NOTIFICATION_DELIVERY_EVENT_KIND");
    expect(sql).toContain("NOTIFICATION_DELIVERY_MESSAGE_ID");
    expect(sql).toContain(`on conflict ("provider_event_id") do nothing`);
    expect(sql).toContain(
      `perform "better_supabase"."suppress_notification_address"(`,
    );
    expect(sql).toContain("coalesce(record_delivery_event.suppress, true)");
    expect(sql).toMatch(
      /grant execute on function "better_supabase"\."record_delivery_event"\(text, text, text, text, timestamptz, jsonb, boolean\) to service_role/,
    );
    expect(sql).not.toMatch(
      /grant execute on function "better_supabase"\."record_delivery_event"[^;]*authenticated/,
    );
  });

  it("moves the provider status forward only", () => {
    expect(body()).toContain(
      `coalesce(array_position(array['delayed', 'delivered', 'opened', 'clicked', 'bounced', 'complained']::text[], d."provider_status"), 0) <= array_position(`,
    );
  });

  it("stores the template key the channel returns", () => {
    const sql = body();
    expect(sql).toContain(
      "max_attempts integer default 5, template_key text default null)",
    );
    expect(sql).toContain(
      `"template_key" = coalesce(complete_notification_delivery.template_key, d."template_key")`,
    );
    expect(sql).toContain(
      `drop function if exists "better_supabase"."complete_notification_delivery"(uuid, text, text, text, text, integer);`,
    );
  });

  it("lists a record's deliveries for the service, or for senders with access", () => {
    const service = body();
    expect(service).toContain(
      `create or replace function "better_supabase"."list_subject_deliveries"(subject_type text, subject_id text, tenant uuid default null, max_items integer default 50)`,
    );
    expect(service).toMatch(
      /grant execute on function "better_supabase"\."list_subject_deliveries"\(text, text, uuid, integer\) to service_role;/,
    );
    const members = rendered(["permissions", "notifications"]);
    expect(members).toMatch(
      /better_supabase\.member_can\(auth\.uid\(\), list_subject_deliveries\.tenant, 'notifications\.send'\)/,
    );
    expect(members).toContain(
      `grant execute on function "better_supabase"."list_subject_deliveries"(text, text, uuid, integer) to authenticated, service_role;`,
    );
  });

  it("leaves tracking out without deliveries and when mapped to null", () => {
    for (const modules of [
      { notifications: { tables: { deliveries: null } } },
      { notifications: { tables: { deliveryEvents: null } } },
    ] satisfies AnyBlocksConfig[]) {
      const sql = body(modules);
      expect(sql).not.toContain("notification_delivery_events");
      expect(sql).not.toContain("record_delivery_event");
      expect(sql).not.toContain("template_key");
    }
  });

  it("creates its own events table over the app's deliveries when the app maps none", () => {
    const sql = overApp(APP_TABLES);
    expect(sql).toContain(
      `create table if not exists "public"."notification_delivery_events" (`,
    );
    expect(sql).toContain(
      `references "public"."notification_deliveries" ("id") on delete cascade`,
    );
    expect(sql).not.toContain(
      `create table if not exists "public"."notification_deliveries" (`,
    );
    expect(sql).toContain("record_delivery_event");
  });

  it("adds the functions to a custom contract only when the table is mapped", () => {
    const contract = (modules: AnyBlocksConfig) =>
      customContracts(["notifications"], { modules })[0]!.functions;

    const names = (modules: AnyBlocksConfig) =>
      contract(modules).map((fn) => fn.name);

    expect(names({ notifications: { mode: "custom" } })).not.toContain(
      "record_delivery_event",
    );

    const mapped = contract({
      notifications: {
        mode: "custom",
        tables: { deliveryEvents: "public.email_events" },
      },
    });

    expect(mapped.slice(-2).map((fn) => fn.name)).toEqual([
      "record_delivery_event",
      "list_subject_deliveries",
    ]);
    expect(
      mapped.find((fn) => fn.name === "complete_notification_delivery")?.args,
    ).toHaveLength(7);
  });
});

describe("partitioned delivery events", () => {
  it("partitions only the delivery events and dedupes provider events with a lock", () => {
    const sql = body({ notifications: { options: { partitioned: true } } });
    expect(sql).toContain(`create table if not exists ${EVENTS} (`);
    expect(sql).toContain('primary key ("id", "created_at")');
    expect(sql).toContain(') partition by range ("created_at");');
    expect(sql).toContain(
      `create table if not exists "better_supabase"."notification_delivery_events_default" partition of ${EVENTS} default;`,
    );
    expect(sql).toContain(
      "pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('better_supabase.notification_delivery_events')",
    );
    expect(sql).toContain(
      `better_supabase.expired_partitions('${EVENTS}'::regclass`,
    );
    expect(sql).not.toContain("notification_deliveries_default");
    expect(sql).not.toContain(`${DELIVERIES} partition`);
    expect(body()).not.toContain("partition by range");
  });
});
