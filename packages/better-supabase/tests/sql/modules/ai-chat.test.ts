import { describe, expect, it } from "vitest";

import type { ModulesConfig } from "../../../src/config/modules.ts";

import {
  moduleBody,
  moduleTopics,
  renderModules,
} from "../../../src/sql/registry.ts";

const body = (modules: ModulesConfig = {}) =>
  moduleBody("ai-chat", { modules })!;

const withModules = (names: readonly string[]): string =>
  renderModules([...names, "ai-chat"], { modules: {} })
    .filter((file) => file.contents.includes("ai_messages"))
    .map((file) => file.contents)
    .join("\n");

describe("ai-chat module", () => {
  it("owns the chat, message tree and run tables", () => {
    const sql = body();
    for (const table of [
      "ai_projects",
      "ai_chats",
      "ai_messages",
      "ai_runs",
      "ai_tool_approvals",
      "ai_tool_policies",
      "ai_pending_inputs",
      "ai_message_sources",
      "ai_message_feedback",
      "ai_chat_shares",
      "ai_model_catalog",
      "ai_moderation_events",
    ]) {
      expect(sql).toContain(
        `create table if not exists "better_supabase"."${table}" (`,
      );
    }
    expect(sql).toContain('primary key ("chat_id", "id")');
    expect(sql).toContain(
      'foreign key ("chat_id", "parent_id") references "better_supabase"."ai_messages" ("chat_id", "id")',
    );
  });

  it("checks part types against the canonical message format", () => {
    const sql = body();
    expect(sql).toContain('@.type == "tool-approval"');
    expect(sql).toContain("jsonb_path_exists");
  });

  it("stores only the hash of a share token", () => {
    const sql = body();
    expect(sql).toContain('"token_hash" text not null unique');
    expect(sql).toContain("encode(sha256(convert_to(v_token, 'UTF8')), 'hex')");
    expect(sql).toContain(
      'grant execute on function "better_supabase"."get_shared_ai_chat"(text) to anon, authenticated, service_role;',
    );
  });

  it("keeps replies, claims and the catalog for the service role", () => {
    const sql = body();
    for (const signature of [
      '"save_ai_assistant_message"(uuid, jsonb, text, text, text, text, jsonb, uuid)',
      '"claim_ai_chat_stream"(uuid, text, text, text, text)',
      '"release_ai_chat_stream"(uuid, text, text, jsonb, text, text, bigint)',
      '"upsert_ai_models"(jsonb, boolean)',
      '"purge_ai_chats"(integer)',
    ]) {
      expect(sql).toContain(
        `revoke execute on function "better_supabase".${signature} from public, anon, authenticated;`,
      );
    }
  });

  it("checks the default permission keys and takes overrides", () => {
    expect(body()).toContain("'ai_chat.create'");
    const sql = body({
      "ai-chat": { permissions: { create: "chat.write" } },
    });
    expect(sql).toContain("'chat.write'");
    expect(sql).not.toContain("'ai_chat.create'");
  });

  it("limits models by plan only with the entitlements module", () => {
    expect(body()).toContain('(cardinality(x."plans") = 0 or false)');
    expect(withModules(["organizations", "entitlements"])).toContain(
      "better_supabase.tenant_entitlements(v_tenant)",
    );
  });

  it("emits outbox events when the outbox is installed", () => {
    const sql = withModules(["outbox"]);
    expect(sql).toContain("emit_event('ai_chat.message.completed'");
    expect(sql).toContain("emit_event('ai_chat.shared'");
    expect(body()).not.toContain("emit_event(");
  });

  it("joins private topics per chat and per user", () => {
    const sql = body();
    expect(sql).toContain("like 'ai-chat:%'");
    expect(sql).toContain("= 'ai-chats:' || (select auth.uid())::text");
    expect(moduleTopics(["ai-chat"])).toEqual(
      expect.arrayContaining([
        { module: "ai-chat", topic: "ai-chat:{chatId}" },
        { module: "ai-chat", topic: "ai-chats:{userId}" },
      ]),
    );
  });

  it("takes topics, intervals and the id type from the config", () => {
    const sql = body({
      "ai-chat": {
        idType: "bigint",
        options: {
          topic: "chat",
          listTopic: "chats",
          temporaryTtl: "2 hours",
          staleAfter: "1 minute",
        },
      },
    });
    expect(sql).toContain("'chat:' || chat::text");
    expect(sql).toContain("interval '2 hours'");
    expect(sql).toContain("interval '1 minute'");
    expect(sql).toContain('"organization_id" bigint not null');
    expect(() =>
      body({ "ai-chat": { options: { topic: "Bad Topic" } } }),
    ).toThrow(/options.topic/);
    expect(() =>
      body({ "ai-chat": { options: { topic: "same", listTopic: "same" } } }),
    ).toThrow(/must differ/);
    expect(() =>
      body({ "ai-chat": { options: { staleAfter: "soon" } } }),
    ).toThrow(/options.staleAfter/);
  });

  it("writes nothing in custom mode", () => {
    expect(
      moduleBody("ai-chat", { modules: { "ai-chat": { mode: "custom" } } }),
    ).toBeUndefined();
  });
});
