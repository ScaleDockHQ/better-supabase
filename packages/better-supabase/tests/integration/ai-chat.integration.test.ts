import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { BlockTransport } from "../../src/blocks/ai-chat/index.ts";

import { createAiChat, sqlTransport } from "../../src/blocks/ai-chat/index.ts";
import {
  BlockSession,
  dbUrl,
  reachable,
  type TestUser,
} from "./block-session.ts";

const live = await reachable();

const text = (value: string) => [{ type: "text", text: value }];

interface Path {
  readonly id: string;
  readonly parent_id: string | null;
  readonly role: string;
  readonly sibling_count: number;
  readonly sibling_index: number;
}

async function setUp(s: BlockSession) {
  await s.install(["organizations", "outbox", "ai-chat"]);
  const owner = await s.user("owner");
  const member = await s.user("member");
  const outsider = await s.user("outsider");
  const tenant = await s.organization(owner, { member });
  return { owner, member, outsider, tenant };
}

describe.skipIf(!live)("ai-chat module", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("stores a branching tree, edits and regenerates as siblings", async () => {
    const s = await BlockSession.open(pool);
    try {
      const { owner, outsider, tenant } = await setUp(s);
      await s.as(owner);
      const chat = await s.value<{ id: string }>(
        "better_supabase.create_ai_chat($1, $2)",
        [tenant, { title: "Plans" }],
      );
      const append = (message: object, trigger?: string, id?: string) =>
        s.value<{
          message_id: string;
          parent_id: string | null;
          created: boolean;
        }>("better_supabase.append_ai_user_message($1, $2, $3, $4)", [
          chat.id,
          message,
          trigger ?? "submit-message",
          id ?? null,
        ]);

      const first = await append({ id: "u1", role: "user", parts: text("Hi") });
      expect(first).toEqual({
        message_id: "u1",
        parent_id: null,
        created: true,
      });
      expect(
        await append({ id: "u1", role: "user", parts: text("Hi") }),
      ).toMatchObject({ message_id: "u1", created: false });

      await s.service();
      expect(
        await s.value("better_supabase.save_ai_assistant_message($1, $2, $3)", [
          chat.id,
          {
            id: "a1",
            role: "assistant",
            parts: [
              ...text("Hello"),
              {
                type: "source",
                sourceType: "url",
                id: "s1",
                url: "https://example.com",
                title: "Example",
              },
            ],
          },
          "u1",
        ]),
      ).toMatchObject({ message_id: "a1", created: true });
      expect(
        await s.rows(
          "select source_id, url from better_supabase.ai_message_sources",
        ),
      ).toEqual([{ source_id: "s1", url: "https://example.com" }]);
      expect(
        await s.rows(
          "select type from better_supabase.outbox_events where type like 'ai_chat.%'",
        ),
      ).toEqual([{ type: "ai_chat.message.completed" }]);

      await s.as(owner);
      const second = await append({
        id: "u2",
        role: "user",
        parts: text("More"),
      });
      expect(second.parent_id).toBe("a1");

      const edited = await append(
        { id: "u2b", role: "user", parts: text("Less") },
        "submit-message",
        "u2",
      );
      expect(edited).toMatchObject({ message_id: "u2b", parent_id: "a1" });
      const sameId = await append({
        id: "u2b",
        role: "user",
        parts: text("Other"),
      });
      expect(sameId.message_id).not.toBe("u2b");
      expect(sameId.parent_id).toBe("a1");

      const path = await s.value<Path[]>(
        "better_supabase.ai_message_path($1)",
        [chat.id],
      );
      expect(path.map((m) => m.id)).toEqual(["u1", "a1", sameId.message_id]);
      expect(path[2]).toMatchObject({ sibling_count: 3, sibling_index: 2 });

      expect(
        await s.value("better_supabase.switch_ai_branch($1, 'u2')", [chat.id]),
      ).toEqual({ leaf_id: "u2" });
      expect(
        (
          await s.value<Path[]>("better_supabase.ai_message_path($1)", [
            chat.id,
          ])
        ).map((m) => m.id),
      ).toEqual(["u1", "a1", "u2"]);
      expect(
        await s.value("better_supabase.switch_ai_branch($1, 'u1')", [chat.id]),
      ).toEqual({ leaf_id: sameId.message_id });

      expect(await append({}, "regenerate-message", "a1")).toMatchObject({
        parent_id: "u1",
        created: false,
      });
      const siblings = await s.value<{ id: string }[]>(
        "better_supabase.ai_message_siblings($1, 'u2')",
        [chat.id],
      );
      expect(siblings.map((m) => m.id)).toEqual([
        "u2",
        "u2b",
        sameId.message_id,
      ]);

      expect(
        await s.hint("better_supabase.append_ai_user_message($1, $2)", [
          chat.id,
          { id: "u9", role: "assistant", parts: [] },
        ]),
      ).toBe("AI_MESSAGE_INVALID");
      expect(
        await s.hint("better_supabase.append_ai_user_message($1, $2)", [
          chat.id,
          { id: "u9", role: "user", parts: [{ type: "bogus" }] },
        ]),
      ).toMatch(/check constraint/);

      await s.as(outsider);
      expect(
        await s.hint("better_supabase.ai_message_path($1)", [chat.id]),
      ).toBe("AI_CHAT_NOT_FOUND");
      expect(
        await s.hint("better_supabase.append_ai_user_message($1, $2)", [
          chat.id,
          { id: "x", role: "user", parts: [] },
        ]),
      ).toBe("AI_CHAT_NOT_FOUND");
    } finally {
      await s.close();
    }
  });

  it("lists, searches and pages the caller's chats", async () => {
    const s = await BlockSession.open(pool);
    try {
      const { owner, member, tenant } = await setUp(s);
      await s.as(owner);
      const ids: string[] = [];
      for (const title of ["Alpha", "Beta", "Gamma"]) {
        const chat = await s.value<{ id: string }>(
          "better_supabase.create_ai_chat($1, $2)",
          [tenant, { title }],
        );
        ids.push(chat.id);
      }
      await s.value("better_supabase.create_ai_chat($1, $2)", [
        tenant,
        { title: "Scratch", is_temporary: true },
      ]);
      await s.value("better_supabase.append_ai_user_message($1, $2)", [
        ids[0],
        { id: "m1", role: "user", parts: text("pelicans fly") },
      ]);
      const page = await s.value<{
        items: { id: string }[];
        next: string | null;
      }>("better_supabase.list_ai_chats($1, size => 2)", [tenant]);
      expect(page.items.map((c) => c.id)).toEqual([ids[0], ids[2]]);
      const rest = await s.value<{
        items: { id: string }[];
        next: string | null;
      }>("better_supabase.list_ai_chats($1, after => $2, size => 2)", [
        tenant,
        page.next,
      ]);
      expect(rest).toEqual({
        items: [expect.objectContaining({ id: ids[1] })],
        next: null,
      });
      const found = await s.value<{ items: { title: string }[] }>(
        "better_supabase.list_ai_chats($1, search => 'pelicans')",
        [tenant],
      );
      expect(found.items.map((c) => c.title)).toEqual(["Alpha"]);
      expect(
        (
          await s.value<{ items: unknown[] }>(
            "better_supabase.list_ai_chats($1, search => 'gamma')",
            [tenant],
          )
        ).items,
      ).toHaveLength(1);

      await s.value("better_supabase.update_ai_chat($1, $2)", [
        ids[1],
        { pinned: true, archived: true, title: "Beta 2" },
      ]);
      const archived = await s.value<{
        items: { title: string; pinned: boolean }[];
      }>("better_supabase.list_ai_chats($1, archived => true)", [tenant]);
      expect(archived.items).toEqual([
        expect.objectContaining({ title: "Beta 2", pinned: true }),
      ]);

      await s.as(member);
      expect(
        (
          await s.value<{ items: unknown[] }>(
            "better_supabase.list_ai_chats($1)",
            [tenant],
          )
        ).items,
      ).toEqual([]);
      expect(await s.hint("better_supabase.get_ai_chat($1)", [ids[0]])).toBe(
        "AI_CHAT_NOT_FOUND",
      );
      await s.as(owner);
      await s.value("better_supabase.update_ai_chat($1, $2)", [
        ids[0],
        { visibility: "organization" },
      ]);
      await s.asRole(member);
      expect(
        await s.rows("select title from better_supabase.ai_chats"),
      ).toEqual([{ title: "Alpha" }]);
      expect(
        await s.rows("select id from better_supabase.ai_messages"),
      ).toEqual([{ id: "m1" }]);

      await s.as(owner);
      expect(
        await s.value("better_supabase.delete_ai_chat($1)", [ids[2]]),
      ).toBe(true);
      await s.service();
      await s.rows(
        "update better_supabase.ai_chats set expires_at = now() - interval '1 minute' where is_temporary",
      );
      expect(await s.value("better_supabase.purge_ai_chats()")).toBe(1);
    } finally {
      await s.close();
    }
  });

  it("claims one stream per chat and stops it", async () => {
    const s = await BlockSession.open(pool);
    try {
      const { owner, outsider, tenant } = await setUp(s);
      await s.as(owner);
      const chat = await s.value<{ id: string }>(
        "better_supabase.create_ai_chat($1)",
        [tenant],
      );
      await s.service();
      await s.value("better_supabase.stream_open('s1', $1)", [owner.id]);
      const claim = await s.value<{ claimed: boolean; run_id: string }>(
        "better_supabase.claim_ai_chat_stream($1, 's1', 'openai/gpt-5')",
        [chat.id],
      );
      expect(claim.claimed).toBe(true);
      expect(
        await s.value("better_supabase.claim_ai_chat_stream($1, 's2')", [
          chat.id,
        ]),
      ).toMatchObject({ claimed: false, stream_id: "s1" });
      expect(
        await s.value("better_supabase.claim_ai_chat_stream($1, 's1')", [
          chat.id,
        ]),
      ).toMatchObject({ claimed: true, run_id: claim.run_id });

      await s.as(outsider);
      expect(
        await s.hint("better_supabase.request_ai_chat_stop($1)", [chat.id]),
      ).toBe("AI_CHAT_NOT_FOUND");
      await s.as(owner);
      expect(
        await s.value("better_supabase.request_ai_chat_stop($1)", [chat.id]),
      ).toEqual({ stream_id: "s1", run_id: claim.run_id });
      await s.service();
      expect(
        await s.value<{ cancelled: boolean }>(
          "better_supabase.stream_status('s1')",
        ),
      ).toMatchObject({ cancelled: true });
      expect(
        await s.value(
          "better_supabase.release_ai_chat_stream($1, 's1', 'stopped', $2, 'gen-1')",
          [chat.id, { inputTokens: 3 }],
        ),
      ).toBe(true);
      expect(
        await s.value("better_supabase.set_ai_run_cost('gen-1', 1200)"),
      ).toBe(true);
      expect(
        await s.rows(
          "select status, cost_micro_usd, usage from better_supabase.ai_runs",
        ),
      ).toEqual([
        {
          status: "stopped",
          cost_micro_usd: "1200",
          usage: { inputTokens: 3 },
        },
      ]);

      await s.value("better_supabase.claim_ai_chat_stream($1, 's3')", [
        chat.id,
      ]);
      await s.rows(
        "update better_supabase.ai_runs set started_at = now() - interval '1 hour' where stream_id = 's3'",
      );
      expect(
        await s.value("better_supabase.claim_ai_chat_stream($1, 's4')", [
          chat.id,
        ]),
      ).toMatchObject({ claimed: true, stream_id: "s4" });
      await s.as(owner);
      expect(
        await s.hint("better_supabase.claim_ai_chat_stream($1, 's5')", [
          chat.id,
        ]),
      ).toBe("AI_CHAT_FORBIDDEN");
    } finally {
      await s.close();
    }
  });

  it("decides approvals once and answers questions", async () => {
    const s = await BlockSession.open(pool);
    try {
      const { owner, member, tenant } = await setUp(s);
      await s.as(owner);
      const chat = await s.value<{ id: string }>(
        "better_supabase.create_ai_chat($1)",
        [tenant],
      );
      await s.service();
      await s.value("better_supabase.record_ai_tool_approval($1, $2)", [
        chat.id,
        {
          approval_id: "ap1",
          tool: "send_email",
          tool_call_id: "tc1",
          input: { to: "a@b.c" },
        },
      ]);
      const input = await s.value<{ id: string }>(
        "better_supabase.open_ai_pending_input($1, $2)",
        [chat.id, { question: "Which plan?", schema: { type: "string" } }],
      );
      await s.as(member);
      expect(
        await s.hint("better_supabase.decide_ai_tool_approval('ap1', true)"),
      ).toBe("AI_APPROVAL_NOT_FOUND");
      await s.as(owner);
      expect(
        await s.value(
          "better_supabase.decide_ai_tool_approval('ap1', true, 'ok')",
        ),
      ).toMatchObject({
        decision: "approved",
        reason: "ok",
        decided_by: owner.id,
      });
      expect(
        await s.value("better_supabase.decide_ai_tool_approval('ap1', true)"),
      ).toMatchObject({ decision: "approved" });
      expect(
        await s.hint("better_supabase.decide_ai_tool_approval('ap1', false)"),
      ).toBe("AI_APPROVAL_DECIDED");
      expect(
        await s.value<unknown[]>("better_supabase.get_ai_tool_approvals($1)", [
          chat.id,
        ]),
      ).toHaveLength(1);
      expect(
        await s.value(
          "better_supabase.answer_ai_pending_input($1, '\"pro\"')",
          [input.id],
        ),
      ).toMatchObject({ answer: "pro" });
      expect(
        await s.hint(
          "better_supabase.answer_ai_pending_input($1, '\"free\"')",
          [input.id],
        ),
      ).toBe("AI_INPUT_ANSWERED");

      expect(
        await s.value(
          "better_supabase.set_ai_tool_policy($1, 'send_email', 'ask')",
          [tenant],
        ),
      ).toEqual({ tool: "send_email", policy: "ask" });
      await s.as(member);
      expect(
        await s.value("better_supabase.ai_tool_policies_for($1)", [tenant]),
      ).toEqual({ send_email: "ask" });
      expect(
        await s.hint(
          "better_supabase.set_ai_tool_policy($1, 'send_email', 'auto')",
          [tenant],
        ),
      ).toBe("AI_CHAT_FORBIDDEN");
    } finally {
      await s.close();
    }
  });

  it("shares a branch by token and rates replies", async () => {
    const s = await BlockSession.open(pool);
    try {
      const { owner, tenant } = await setUp(s);
      await s.as(owner);
      const chat = await s.value<{ id: string }>(
        "better_supabase.create_ai_chat($1, $2)",
        [tenant, { title: "Shared" }],
      );
      expect(await s.hint("better_supabase.share_ai_chat($1)", [chat.id])).toBe(
        "AI_MESSAGE_NOT_FOUND",
      );
      await s.value("better_supabase.append_ai_user_message($1, $2)", [
        chat.id,
        { id: "u1", role: "user", parts: text("Hi") },
      ]);
      await s.service();
      await s.value("better_supabase.save_ai_assistant_message($1, $2, 'u1')", [
        chat.id,
        { id: "a1", role: "assistant", parts: text("Hello") },
      ]);
      await s.as(owner);
      const share = await s.value<{ id: string; token: string }>(
        "better_supabase.share_ai_chat($1)",
        [chat.id],
      );
      expect(share.token).toMatch(/^[0-9a-f]{64}$/);
      expect(
        await s.rows(
          "select token_hash from better_supabase.ai_chat_shares where token_hash = $1",
          [share.token],
        ),
      ).toEqual([]);

      await s.asRole("anon");
      const shared = await s.value<{
        chat: { title: string };
        messages: { id: string; native?: unknown }[];
      }>("better_supabase.get_shared_ai_chat($1)", [share.token]);
      expect(shared.chat.title).toBe("Shared");
      expect(shared.messages.map((m) => m.id)).toEqual(["u1", "a1"]);
      expect(
        await s.value("better_supabase.get_shared_ai_chat('nope')"),
      ).toBeNull();

      await s.as(owner);
      expect(
        await s.value(
          "better_supabase.rate_ai_message($1, 'a1', -1, 'wrong')",
          [chat.id],
        ),
      ).toMatchObject({ rating: -1, reason: "wrong" });
      expect(
        await s.value("better_supabase.rate_ai_message($1, 'a1', null)", [
          chat.id,
        ]),
      ).toBeNull();
      expect(
        await s.value("better_supabase.revoke_ai_chat_share($1)", [share.id]),
      ).toBe(true);
      expect(
        await s.value("better_supabase.get_shared_ai_chat($1)", [share.token]),
      ).toBeNull();
      expect(
        await s.value<unknown[]>("better_supabase.list_ai_chat_shares($1)", [
          chat.id,
        ]),
      ).toHaveLength(1);
      await s.service();
      expect(
        await s.rows(
          "select type from better_supabase.outbox_events where type = 'ai_chat.shared'",
        ),
      ).toHaveLength(1);
    } finally {
      await s.close();
    }
  });

  it("filters the model catalog and records moderation", async () => {
    const s = await BlockSession.open(pool);
    try {
      const { owner, member, tenant } = await setUp(s);
      await s.service();
      await s.rows("delete from better_supabase.ai_model_catalog");
      expect(
        await s.value("better_supabase.upsert_ai_models($1)", [
          JSON.stringify([
            { id: "openai/gpt-5", name: "GPT-5" },
            { id: "anthropic/claude", plans: ["pro"] },
            { id: "x/old", enabled: false },
          ]),
        ]),
      ).toBe(3);
      await s.as(member);
      expect(
        (
          await s.value<{ model_id: string }[]>(
            "better_supabase.allowed_ai_models($1)",
            [tenant],
          )
        ).map((m) => m.model_id),
      ).toEqual(["openai/gpt-5"]);
      await s.service();
      expect(
        await s.value("better_supabase.upsert_ai_models($1, true)", [
          JSON.stringify([{ id: "openai/gpt-5" }]),
        ]),
      ).toBe(1);
      expect(
        await s.rows("select model_id from better_supabase.ai_model_catalog"),
      ).toEqual([{ model_id: "openai/gpt-5" }]);

      await s.value("better_supabase.record_ai_moderation_event($1)", [
        {
          organization_id: tenant,
          user_id: member.id,
          stage: "input",
          category: "pii",
          action: "redact",
          score: 0.9,
        },
      ]);
      await s.as(member);
      expect(
        await s.hint("better_supabase.list_ai_moderation_events($1)", [tenant]),
      ).toBe("AI_CHAT_FORBIDDEN");
      await s.as(owner);
      expect(
        await s.value("better_supabase.list_ai_moderation_events($1)", [
          tenant,
        ]),
      ).toEqual([
        expect.objectContaining({ category: "pii", action: "redact" }),
      ]);

      const project = await s.value<{ id: string }>(
        "better_supabase.save_ai_project(null, $1, $2)",
        [tenant, { name: "Research", instructions: "Be brief" }],
      );
      await s.value("better_supabase.save_ai_project($1, $2, $3)", [
        project.id,
        tenant,
        { pinned: true },
      ]);
      const chat = await s.value<{ project_id: string }>(
        "better_supabase.create_ai_chat($1, $2)",
        [tenant, { project_id: project.id }],
      );
      expect(chat.project_id).toBe(project.id);
      expect(
        await s.value<{ pinned: boolean }[]>(
          "better_supabase.list_ai_projects($1)",
          [tenant],
        ),
      ).toEqual([expect.objectContaining({ name: "Research", pinned: true })]);
      expect(
        await s.value("better_supabase.delete_ai_project($1)", [project.id]),
      ).toBe(true);
    } finally {
      await s.close();
    }
  });
  it("drives the block client over both transports", async () => {
    const s = await BlockSession.open(pool);
    try {
      const { owner, tenant } = await setUp(s);
      const user = sqlTransport(s.sql);
      let caller: TestUser = owner;
      const service: BlockTransport = {
        async call(schema, fn, args) {
          await s.service();
          try {
            return await user.call(schema, fn, args);
          } finally {
            await s.as(caller);
          }
        },
      };
      const ai = createAiChat({ transport: user, service });
      caller = owner;
      await s.as(owner);

      const chat = await ai.chats.create(tenant, { title: "Plans" }).orThrow();
      expect(chat).toMatchObject({ title: "Plans", visibility: "private" });
      const appended = await ai.messages
        .appendUser(chat.id, {
          id: "u1",
          role: "user",
          parts: [{ type: "text", text: "Hi" }],
        })
        .orThrow();
      expect(appended).toEqual({
        messageId: "u1",
        parentId: undefined,
        created: true,
      });

      const claim = await ai.runs
        .claim(chat.id, "stream-1", { model: "openai/gpt-5" })
        .orThrow();
      expect(claim.claimed).toBe(true);
      await ai.messages
        .saveAssistant(
          chat.id,
          {
            id: "a1",
            role: "assistant",
            parts: [{ type: "text", text: "Hello" }],
          },
          {
            parentId: "u1",
            format: "ai-sdk-ui",
            native: { id: "a1", parts: [] },
            runId: claim.runId,
          },
        )
        .orThrow();
      expect(
        await ai.runs
          .release(chat.id, "stream-1", { usage: { totalTokens: 3 } })
          .orThrow(),
      ).toBe(true);

      const path = await ai.messages.path(chat.id, { native: true }).orThrow();
      expect(path.map((message) => message.id)).toEqual(["u1", "a1"]);
      expect(path[1]).toMatchObject({
        format: "ai-sdk-ui",
        native: { id: "a1", parts: [] },
      });

      const approval = await ai.approvals
        .request(chat.id, {
          approvalId: "ap-1",
          tool: "search",
          toolCallId: "t1",
          input: { q: "x" },
        })
        .orThrow();
      expect(approval.decision).toBe("pending");
      expect(
        (await ai.approvals.decide("ap-1", false, "no").orThrow()).decision,
      ).toBe("denied");
      expect(await ai.approvals.list(chat.id, ["ap-1"]).orThrow()).toHaveLength(
        1,
      );
      expect(
        await ai.approvals.setPolicy(tenant, "search", "deny").orThrow(),
      ).toBe("deny");
      expect(await ai.approvals.policies(tenant).orThrow()).toEqual({
        search: "deny",
      });

      const input = await ai.inputs
        .open(chat.id, { question: "Which?" })
        .orThrow();
      expect(
        (await ai.inputs.answer(input.id, "this one").orThrow()).answer,
      ).toBe("this one");

      expect((await ai.feedback.rate(chat.id, "a1", 1).orThrow()).rating).toBe(
        1,
      );
      expect((await ai.feedback.rate(chat.id, "a1", 0).orThrow()).rating).toBe(
        0,
      );

      const link = await ai.shares.create(chat.id).orThrow();
      expect((await ai.shares.get(link.token).orThrow()).messages).toHaveLength(
        2,
      );
      expect(await ai.shares.revoke(link.id).orThrow()).toBe(true);

      expect(
        await ai.models
          .upsert([{ id: "openai/gpt-5" }, { id: "x/hidden", enabled: false }])
          .orThrow(),
      ).toBe(2);
      expect(
        (await ai.models.allowed(tenant).orThrow()).map((model) => model.id),
      ).toContain("openai/gpt-5");

      const event = await ai.moderation
        .record({
          organizationId: tenant,
          chatId: chat.id,
          stage: "output",
          action: "flag",
          category: "pii",
          score: 0.5,
        })
        .orThrow();
      expect(event.score).toBe(0.5);
      expect(await ai.moderation.list(tenant).orThrow()).toHaveLength(1);

      const page = await ai.chats.list({ organizationId: tenant }).orThrow();
      expect(page.items.map((item) => item.id)).toEqual([chat.id]);
      const missing = await ai.chats.get(
        "00000000-0000-0000-0000-000000000000",
      );
      expect(missing.ok ? undefined : missing.error.kind).toBe("not_found");
    } finally {
      await s.close();
    }
  });
});
