import { describe, expect, it } from "vitest";

import type { ModulesConfig } from "../../../src/config/modules.ts";

import { INBOX } from "../../../src/sql/modules/inbox.ts";
import {
  moduleBody,
  moduleContext,
  modulePermissionKeys,
  moduleTopics,
} from "../../../src/sql/registry.ts";

const body = (modules: ModulesConfig = {}) => moduleBody("inbox", { modules })!;

describe("inbox module", () => {
  it("owns its tables behind RLS", () => {
    const sql = body();
    for (const table of [
      "inboxes",
      "inbox_members",
      "inbox_teams",
      "inbox_team_members",
      "contacts",
      "contact_identities",
      "conversations",
      "conversation_participants",
      "conversation_events",
      "conversation_reads",
      "inbox_messages",
      "message_deliveries",
      "inbox_mentions",
      "inbound_events",
      "message_templates",
    ]) {
      expect(sql).toContain(
        `alter table "better_supabase"."${table}" enable row level security;`,
      );
    }
    expect(sql).toContain("tenant_ids_with('inbox.read')");
  });

  it("hides notes from contacts", () => {
    expect(body()).toContain(
      `("kind" = 'message' and "conversation_id" in (select "better_supabase"."inbox_contact_conversation_ids"()))`,
    );
  });

  it("queues bot and outbound jobs with dedupe keys", () => {
    const sql = body();
    expect(sql).toContain(`"enqueue_job"('inbox_bot',`);
    expect(sql).toContain(`'inbox:' || v_conv."id"::text`);
    expect(sql).toContain(`"enqueue_job"('inbox_outbound',`);
    const custom = body({
      inbox: { options: { botQueue: "bots", outboundQueue: "out" } },
    });
    expect(custom).toContain(`"enqueue_job"('bots',`);
    expect(custom).toContain(`"enqueue_job"('out',`);
  });

  it("keeps webhook and delivery functions for the service role", () => {
    const sql = body();
    for (const signature of [
      '"record_inbound"(jsonb)',
      '"record_delivery"(uuid, text, text, text, text)',
      '"store_inbound_event"(text, text, text, jsonb, uuid, uuid)',
      '"pending_inbound_events"(integer, integer)',
      '"wake_snoozed_conversations"()',
    ]) {
      expect(sql).toContain(
        `grant execute on function "better_supabase".${signature} to service_role;`,
      );
    }
    expect(sql).toContain(
      'grant execute on function "better_supabase"."set_typing"(uuid, boolean, text) to authenticated, service_role;',
    );
  });

  it("checks its permission keys", () => {
    const keys = modulePermissionKeys({}, ["inbox"]).filter(
      (entry) => entry.module === "inbox",
    );
    expect(new Set(keys.map((entry) => entry.key))).toEqual(
      new Set(["inbox.read", "inbox.reply", "inbox.assign", "inbox.manage"]),
    );
  });

  it("publishes conversation and organization topics", () => {
    expect(
      moduleTopics(["inbox"]).filter((entry) => entry.module === "inbox"),
    ).toEqual([
      { module: "inbox", topic: "inbox:{conversationId}" },
      { module: "inbox", topic: "inbox:org:{organizationId}" },
    ]);
    expect(body({ inbox: { options: { topic: "support" } } })).toContain(
      "'support:'",
    );
  });

  it("creates its private bucket", () => {
    const data = INBOX.data?.(moduleContext("inbox", { modules: {} }), {});
    expect(data).toContain(
      "values ('inbox-files', 'inbox-files', false, 26214400)",
    );
    expect(
      INBOX.data?.(
        moduleContext("inbox", { modules: { inbox: { mode: "custom" } } }),
        {},
      ),
    ).toBe("");
  });

  it("rejects bad options", () => {
    for (const [options, message] of [
      [{ topic: "Bad Topic" }, /options.topic/],
      [{ bucket: "Bad Bucket" }, /options.bucket/],
      [{ maxBodyLength: 0 }, /options.maxBodyLength/],
      [{ botQueue: "Bad" }, /options.botQueue/],
    ] as const) {
      expect(() => body({ inbox: { options } })).toThrow(message);
    }
  });

  it("writes nothing in custom mode", () => {
    expect(
      moduleBody("inbox", { modules: { inbox: { mode: "custom" } } }),
    ).toBeUndefined();
  });
});
