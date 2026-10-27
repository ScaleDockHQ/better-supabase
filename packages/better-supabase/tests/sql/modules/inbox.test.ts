import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { modulePermissionKeys } from "../../../src/sql/introspect.ts";
import { moduleContext } from "../../../src/sql/module-context.ts";
import { INBOX } from "../../../src/sql/modules/inbox.ts";
import {
  moduleBody,
  moduleTopics,
  renderBlocks,
} from "../../../src/sql/render.ts";
import { moduleProvider } from "../../fixtures/authorization-provider.ts";

const body = (modules: AnyBlocksConfig = {}) =>
  moduleBody("inbox", { modules })!;

const withJobs = (modules: AnyBlocksConfig = {}) =>
  renderBlocks(["inbox", "queue"], { modules })
    .filter((file) => file.kind === "schema" && file.module === "inbox")
    .map((file) => file.contents)
    .join("\n");

describe("inbox module", () => {
  it("owns its tables behind RLS", () => {
    const sql = body();

    for (const table of [
      "inboxes",
      "inbox_members",
      "contacts",
      "contact_identities",
      "inbox_conversations",
      "conversation_events",
      "inbox_message_details",
      "message_deliveries",
      "inbound_events",
      "message_templates",
    ]) {
      expect(sql).toContain(
        `alter table "better_supabase"."${table}" enable row level security;`,
      );
    }

    expect(sql).toContain("tenant_ids_with('inbox.read')");

    for (const table of [
      "inbox_messages",
      "conversation_participants",
      "conversation_reads",
      "inbox_mentions",
    ]) {
      expect(sql).not.toContain(
        `create table if not exists "better_supabase"."${table}"`,
      );
    }
  });

  it("hides notes from contacts", () => {
    expect(body()).toContain(
      `(m."kind" = 'message' or "better_supabase"."inbox_note_readable"(d."conversation_id"));`,
    );
  });

  it("queues bot and outbound jobs with dedupe keys when jobs is installed", () => {
    const sql = withJobs();
    expect(sql).toContain(`"enqueue_job"(queue => 'inbox_bot',`);
    expect(sql).toContain(`dedupe_key => 'inbox:' || v_conv."id"::text`);
    expect(sql).toContain(`"enqueue_job"(queue => 'inbox_outbound',`);

    const custom = withJobs({
      inbox: { options: { botQueue: "bots", outboundQueue: "out" } },
    });

    expect(custom).toContain(`"enqueue_job"(queue => 'bots',`);
    expect(custom).toContain(`"enqueue_job"(queue => 'out',`);
  });

  it("installs without jobs and queues nothing", () => {
    expect(body()).not.toContain("enqueue_job");
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
      'grant execute on function "better_supabase"."react_to_inbox_message"(uuid, text, boolean, text) to authenticated, service_role;',
    );
    expect(sql).not.toContain("set_inbox_typing");
  });

  it("checks its permission keys", () => {
    const keys = modulePermissionKeys({}, ["inbox"]).filter(
      (entry) => entry.module === "inbox",
    );

    expect(new Set(keys.map((entry) => entry.key))).toEqual(
      new Set(["inbox.read", "inbox.reply", "inbox.assign", "inbox.manage"]),
    );
  });

  it("publishes the organization topic and leaves conversations to messaging", () => {
    expect(moduleTopics(["inbox"])).toEqual([
      { module: "inbox", topic: "inbox:org:{organizationId}" },
      { module: "messaging", topic: "messages:{conversationId}" },
    ]);
    expect(body({ inbox: { options: { topic: "support" } } })).toContain(
      "'support:'",
    );
  });

  it("keeps files in attachments instead of a bucket of its own", () => {
    expect(
      INBOX.data?.(moduleContext("inbox", { modules: {} }), {}) ?? "",
    ).not.toContain("storage.buckets");
    expect(body()).not.toContain("inbox-files");
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

  it("checks commands against the provider's operations, then the renamed module key", () => {
    const guard = (sql: string, fn: string): string => {
      const start = sql.indexOf(`"${fn}"(`);

      return sql.slice(start, sql.indexOf("$$;", start));
    };

    const sql = moduleBody("inbox", {
      modules: { inbox: { permissions: { reply: "support.reply" } } },
      accessProvider: {
        ...moduleProvider,
        operations: {
          "inbox.command.assign": { permission: "tickets.assign" },
          "inbox.command.set_bot_mode": { permission: "" },
          "mcp.tool.assign": { permission: "tools.assign" },
        },
      },
    })!;

    const assign = guard(sql, "assign_conversation");
    expect(assign).toContain(
      `better_supabase.can('tenant', v_conv."tenant_id", 'tickets.assign')`,
    );
    expect(assign).toContain(
      `(coalesce(assignee = (select auth.uid()), false) and coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'support.reply'), false))`,
    );

    for (const fn of ["set_conversation_status", "set_bot_mode"]) {
      expect(guard(sql, fn)).toContain(
        `better_supabase.can('tenant', v_conv."tenant_id", 'support.reply')`,
      );
    }

    expect(sql).not.toContain("tools.assign");
    expect(sql).not.toContain("'inbox.reply'");
  });

  it("writes nothing in custom mode", () => {
    expect(
      moduleBody("inbox", { modules: { inbox: { mode: "custom" } } }),
    ).toBeUndefined();
  });
});
