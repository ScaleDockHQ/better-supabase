import { describe, expect, it } from "vitest";

import type { ModulesConfig } from "../../../src/config/modules.ts";

import {
  moduleBody,
  moduleTopics,
  renderModules,
  upgradePlan,
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
      '"claim_ai_chat_stream"(uuid, text, text, text, text, text)',
      '"release_ai_chat_stream"(uuid, text, text, jsonb, text, text, bigint)',
      '"upsert_ai_models"(jsonb, boolean)',
      '"purge_ai_chats"(integer)',
      '"attach_ai_run"(uuid, text)',
      '"record_ai_run_step"(uuid, jsonb)',
      '"load_ai_harness_session"(uuid, text)',
      '"save_ai_harness_session"(uuid, text, jsonb, text)',
      '"lock_ai_harness_session"(uuid, text, text, integer)',
      '"unlock_ai_harness_session"(uuid, text, text)',
      '"idle_ai_harness_sessions"(integer, integer)',
    ]) {
      expect(sql).toContain(
        `revoke execute on function "better_supabase".${signature} from public, anon, authenticated;`,
      );
    }
  });

  it("drops the claim's earlier signature so one overload remains", () => {
    expect(body()).toContain(
      'drop function if exists "better_supabase"."claim_ai_chat_stream"(uuid, text, text, text, text);',
    );
  });

  it("keeps durable runs, run steps and harness sessions", () => {
    const sql = body();
    expect(sql).toContain('"external_run_id" text');
    expect(sql).toContain('unique ("run_id", "step_key")');
    expect(sql).toContain('primary key ("chat_id", "harness_id")');
    expect(sql).not.toContain("create policy ai_harness_sessions_owner_read");
    expect(sql).not.toMatch(
      /grant select on "?[\w.]*"?\.?"?ai_harness_sessions"? to authenticated/,
    );
    expect(sql).toContain("for update skip locked");
    for (const signature of [
      '"get_ai_run"(uuid)',
      '"list_ai_runs"(uuid, boolean, integer)',
      '"list_pending_ai_tool_approvals"(integer)',
      '"list_ai_run_steps"(uuid)',
    ]) {
      expect(sql).toContain(
        `grant execute on function "better_supabase".${signature} to authenticated, service_role;`,
      );
    }
  });

  it("keeps every sandbox, a harness session's included, in ai_sandboxes", () => {
    const sql = body();
    expect(sql).toContain(
      'create table if not exists "better_supabase"."ai_sandboxes" (',
    );
    expect(sql).toMatch(/"harness_id" text check/);
    expect(sql).not.toMatch(/ai_harness_sessions" \([^;]*"sandbox_id"/);
    expect(sql).toContain("default 600");
    for (const signature of [
      '"register_ai_sandbox"(uuid, text, text, jsonb)',
      '"idle_ai_sandboxes"(integer, integer)',
      '"finish_ai_sandbox_stop"(uuid, boolean, text)',
    ]) {
      expect(sql).toContain(
        `revoke execute on function "better_supabase".${signature} from public, anon, authenticated;`,
      );
    }
    expect(() =>
      body({ "ai-chat": { options: { sandboxIdleAfter: 0 } } }),
    ).toThrow(/sandboxIdleAfter/);
  });

  it("upgrades run states and moves harness sandboxes from version 1", () => {
    const [plan] = upgradePlan([{ module: "ai-chat", version: 1 }]);
    expect(plan!.to).toBe(2);
    const sql = plan!.steps.map((step) => step.sql).join("\n");
    expect(sql).toContain("when 'error' then 'failed' else 'cancelled' end");
    expect(sql).toContain(
      'create table if not exists "better_supabase"."ai_sandboxes" (',
    );
    expect(sql.indexOf('add column if not exists "harness_id"')).toBeLessThan(
      sql.indexOf("ai_sandboxes_harness_idx"),
    );
    expect(sql).toContain("drop column sandbox_id");
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
    expect(sql).toContain("emit_event('ai_chat_message.completed'");
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

describe("ai-chat tool approvals with the provider's canApprove", () => {
  const withProvider = (distinctApprover?: boolean) =>
    moduleBody("ai-chat", {
      modules: { access: { model: "provider" } },
      accessProvider: {
        name: "stub",
        scope: "organization",
        idType: "uuid",
        functions: {
          idsWith: "authz.ids_with({permission}, {scope})",
          isPlatform: "authz.is_platform({permission})",
          canApprove: "authz.can_approve({tool}, {tenant})",
        },
        ...(distinctApprover === undefined
          ? {}
          : { approvals: { distinctApprover } }),
      },
    })!;

  it("lets the owner decide without canApprove", () => {
    const sql = body();
    const decide = sql.slice(sql.indexOf("decide_ai_tool_approval"));
    expect(decide).toContain("= (select auth.uid())");
    expect(decide).not.toContain("can_approve");
  });

  it("asks canApprove, and keeps the requester out with distinctApprover", () => {
    const shared = withProvider();
    expect(shared).toMatch(/coalesce\(\(authz\.can_approve\(v_row\."tool"/);
    expect(shared).not.toContain("is distinct from (select auth.uid())");
    expect(withProvider(true)).toMatch(
      /is distinct from \(select auth\.uid\(\)\) and coalesce\(\(authz\.can_approve/,
    );
  });
});
