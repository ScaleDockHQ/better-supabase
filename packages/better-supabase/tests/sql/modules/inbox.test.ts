import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { modulePermissionKeys } from "../../../src/sql/introspect.ts";
import { moduleContext } from "../../../src/sql/module-context.ts";
import { INBOX } from "../../../src/sql/modules/inbox.ts";
import {
  moduleBody,
  moduleTopics,
  renderModules,
} from "../../../src/sql/render.ts";
import { moduleProvider } from "../../fixtures/authorization-provider.ts";

const body = (modules: AnyBlocksConfig = {}) =>
  moduleBody("inbox", { modules })!;

const withJobs = (modules: AnyBlocksConfig = {}) =>
  renderModules(["inbox", "jobs"], { modules })
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
      'grant execute on function "better_supabase"."set_inbox_typing"(uuid, boolean, text) to authenticated, service_role;',
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
      `(assignee = (select auth.uid()) and coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'support.reply'), false))`,
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
