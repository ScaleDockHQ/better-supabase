import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { moduleBody } from "../../../src/sql/render.ts";

const body = (options: Record<string, unknown>, more: AnyBlocksConfig = {}) =>
  moduleBody("ai-chat", { modules: { "ai-chat": { options }, ...more } })!;

describe("ai-chat message shapes", () => {
  it("keeps a text-keyed tree by default", () => {
    const sql = body({});

    expect(sql).toContain('"parent_id" text');
    expect(sql).not.toContain("ai_message_key");
    expect(sql).not.toContain("ai_messages_seq_idx");
    expect(sql).toContain("'canonical'");
  });

  it("keys messages by uuid through ai_message_key", () => {
    const sql = body({ messages: { key: "uuid" } });

    expect(sql).toContain('"id" uuid not null default gen_random_uuid()');
    expect(sql).toContain(
      'create or replace function "better_supabase"."ai_message_key"(value text)',
    );
    expect(sql).toContain("AI_MESSAGE_INVALID");
    expect(sql).toContain(
      'revoke execute on function "better_supabase"."ai_message_key"(text) from public, anon, authenticated;',
    );
    expect(sql).toContain(
      '"better_supabase"."ai_message_key"(rate_ai_message.message_id)',
    );
    expect(sql).toMatch(/"leaf_id" uuid/);
  });

  it("keeps one linear list without a parent column", () => {
    const sql = body({ messages: { key: "uuid", tree: false } });

    expect(sql).not.toContain('"parent_id" uuid');
    expect(sql).toContain("ai_messages_seq_idx");
    expect(sql).toContain("AI_CHAT_LINEAR");
    expect(sql).toContain("lag(");
  });

  it("stores the SDK's own parts with parts: native", () => {
    const sql = body({ messages: { parts: "native" } });

    expect(sql).toContain('@.type.type() != "string"');
    expect(sql).toContain("default 'native'");
    expect(sql).not.toContain('@.type == "tool-approval"');
  });

  it("defaults to a linear list when the app maps no parent column", () => {
    const sql = moduleBody("ai-chat", {
      modules: { "ai-chat": { columns: { messages: { parent: null } } } },
    })!;

    expect(sql).toContain("AI_CHAT_LINEAR");
  });

  it("refuses a malformed messages option", () => {
    expect(() => body({ messages: [] })).toThrow(/must be an object/);
    expect(() => body({ messages: { layout: "x" } })).toThrow(
      /no key "layout"/,
    );
    expect(() => body({ messages: { key: "int" } })).toThrow(/key must be/);
    expect(() => body({ messages: { tree: "yes" } })).toThrow(
      /tree must be a boolean/,
    );
    expect(() => body({ messages: { parts: "raw" } })).toThrow(/parts must be/);
    expect(() =>
      moduleBody("ai-chat", {
        modules: {
          "ai-chat": {
            columns: { messages: { parent: null } },
            options: { messages: { tree: true } },
          },
        },
      }),
    ).toThrow(/needs a parent column/);
  });

  it("records who wrote a message", () => {
    const sql = body({});

    expect(sql).toContain(
      '"author_id" uuid references auth.users (id) on delete set null',
    );
    expect(sql).toContain(
      'alter table "better_supabase"."ai_messages" add column if not exists "author_id"',
    );
  });
});

describe("ai-chat without a tenant", () => {
  it("makes the tenant columns nullable and lets any user start a chat", () => {
    const sql = body({ tenant: false });

    expect(sql).toContain(
      'alter table "better_supabase"."ai_chats" alter column "organization_id" drop not null;',
    );
    expect(sql).toContain(
      'alter table "better_supabase"."ai_projects" alter column "organization_id" drop not null;',
    );
    expect(sql).toContain("AI_CHAT_NO_TENANT");
    expect(sql).toContain("is not distinct from");
    expect(sql).toContain("case when");
  });

  it("keeps the tenant required by default", () => {
    const sql = body({});

    expect(sql).not.toContain('alter column "organization_id" drop not null');
    expect(sql).toContain('"organization_id" uuid not null');
  });
});

describe("ai-chat extra columns on every table", () => {
  it("adds the columns and returns them under fields", () => {
    const sql = body({
      projectExtraColumns: { color: "text" },
      messageExtraColumns: { thread_kind: "text" },
      participantExtraColumns: { note: "text" },
      moderationExtraColumns: { lang: "text" },
      runExtraColumns: { cost_center: "text" },
    });

    for (const [table, column] of [
      ["ai_projects", "color"],
      ["ai_messages", "thread_kind"],
      ["ai_chat_participants", "note"],
      ["ai_moderation_events", "lang"],
      ["ai_runs", "cost_center"],
    ]) {
      expect(sql).toContain(
        `alter table "better_supabase"."${table}" add column if not exists "${column}" text;`,
      );
    }

    expect(sql).toContain("'fields', jsonb_build_object('thread_kind'");
    expect(sql).toContain("append_ai_user_message.message -> 'fields'");
    expect(sql).toContain("record_ai_moderation_event.event -> 'fields'");
  });

  it("refuses a column a table already has", () => {
    expect(() => body({ messageExtraColumns: { role: "text" } })).toThrow(
      /shadows a column/,
    );
    expect(() =>
      body({ projectExtraColumns: { archived: "boolean" } }),
    ).toThrow(/shadows a column/);
  });
});
