import { describe, expect, it, vi } from "vitest";

import type {
  AiMessage,
  BlockTransport,
} from "../../../src/blocks/ai-chat/index.ts";

import {
  aiChatListTopic,
  aiChatTopic,
  createAiChat,
} from "../../../src/blocks/ai-chat/index.ts";

const AT = "2026-01-01T00:00:00Z";

const chatRow = {
  id: "c1",
  organization_id: "o1",
  owner_id: "u1",
  project_id: null,
  agent_id: "agent",
  title: "Hello",
  model: "openai/gpt-5",
  visibility: "organization",
  pinned: true,
  archived_at: null,
  is_temporary: false,
  expires_at: null,
  current_leaf_id: "m2",
  active_stream_id: null,
  active_run_id: null,
  last_message_at: AT,
  created_at: AT,
  updated_at: AT,
};

const projectRow = {
  id: "p1",
  organization_id: "o1",
  owner_id: "u1",
  name: "Research",
  instructions: null,
  default_model: "openai/gpt-5",
  pinned: false,
  archived_at: AT,
  created_at: AT,
  updated_at: AT,
};

const messageRow = {
  id: "m1",
  parent_id: null,
  role: "user",
  parts: [{ type: "text", text: "hi" }, "junk"],
  metadata: {},
  format: "canonical",
  native: null,
  model: null,
  status: "complete",
  created_at: AT,
  sibling_count: 2,
  sibling_index: 1,
};

const approvalRow = {
  approval_id: "ap1",
  chat_id: "c1",
  run_id: null,
  message_id: "m2",
  tool: "search",
  tool_call_id: "t1",
  input: { q: "x" },
  decision: "approved",
  reason: null,
  signature: "sig",
  decided_by: "u1",
  decided_at: AT,
  created_at: AT,
};

const inputRow = {
  id: "i1",
  chat_id: "c1",
  run_id: null,
  tool_call_id: "t1",
  question: "Which?",
  schema: { type: "string" },
  answer: { value: "this" },
  answered_at: AT,
  created_at: AT,
};

const modelRow = {
  model_id: "openai/gpt-5",
  provider: "openai",
  name: "GPT-5",
  pricing: { input: 1 },
  capabilities: null,
  plans: ["pro"],
  enabled: true,
  refreshed_at: AT,
};

const moderationRow = {
  id: "md1",
  organization_id: "o1",
  chat_id: "c1",
  message_id: null,
  user_id: "u1",
  stage: "output",
  category: "pii",
  score: 0.9,
  action: "redact",
  created_at: AT,
};

const ANSWERS: Record<string, unknown> = {
  create_ai_chat: chatRow,
  get_ai_chat: chatRow,
  update_ai_chat: { ...chatRow, visibility: "weird" },
  list_ai_chats: { items: [chatRow], next: `${AT}|c1` },
  delete_ai_chat: true,
  purge_ai_chats: "3",
  save_ai_project: projectRow,
  list_ai_projects: [projectRow],
  delete_ai_project: true,
  append_ai_user_message: { message_id: "m1", parent_id: null, created: true },
  save_ai_assistant_message: {
    message_id: "m2",
    parent_id: "m1",
    created: false,
  },
  ai_message_path: [
    messageRow,
    {
      ...messageRow,
      id: "m2",
      parent_id: "m1",
      role: "assistant",
      parts: "none",
      metadata: { tokens: 3 },
      format: "ai-sdk-ui",
      native: { value: { id: "m2" } },
      status: "aborted",
      sibling_count: null,
      sibling_index: undefined,
    },
  ],
  ai_message_siblings: [{ id: "m1", role: "bogus", created_at: AT }],
  switch_ai_branch: { leaf_id: "m9" },
  claim_ai_chat_stream: { claimed: true, stream_id: "s1", run_id: "r1" },
  release_ai_chat_stream: true,
  request_ai_chat_stop: { stream_id: "s1", run_id: "r1" },
  set_ai_run_cost: false,
  record_ai_tool_approval: { ...approvalRow, decision: "pending" },
  decide_ai_tool_approval: approvalRow,
  get_ai_tool_approvals: [approvalRow],
  set_ai_tool_policy: { tool: "search", policy: "ask" },
  ai_tool_policies_for: { search: "deny", other: "bogus" },
  open_ai_pending_input: { ...inputRow, answer: null, answered_at: null },
  answer_ai_pending_input: inputRow,
  rate_ai_message: {
    chat_id: "c1",
    message_id: "m2",
    rating: -1,
    reason: "wrong",
    comment: null,
  },
  share_ai_chat: { id: "sh1", token: "tok", leaf_id: "m2", created_at: AT },
  revoke_ai_chat_share: true,
  list_ai_chat_shares: [
    {
      id: "sh1",
      leaf_id: "m2",
      created_by: "u1",
      created_at: AT,
      revoked_at: null,
    },
  ],
  get_shared_ai_chat: {
    chat: { id: "c1", title: null, model: null, created_at: AT },
    leaf_id: "m2",
    messages: [messageRow],
  },
  allowed_ai_models: [modelRow],
  upsert_ai_models: 2,
  record_ai_moderation_event: moderationRow,
  list_ai_moderation_events: [{ ...moderationRow, score: null }],
};

function fake(answers: Record<string, unknown> = ANSWERS) {
  const user = vi.fn(
    async (_schema: string, fn: string, _args: Record<string, unknown>) =>
      answers[fn],
  );
  const server = vi.fn(
    async (_schema: string, fn: string, _args: Record<string, unknown>) =>
      answers[fn],
  );
  const transport: BlockTransport = { call: user };
  const service: BlockTransport = { call: server };
  return { user, server, chat: createAiChat({ transport, service }) };
}

const lastArgs = (mock: ReturnType<typeof vi.fn>): unknown =>
  mock.mock.calls.at(-1)?.[2];

const message: AiMessage = {
  id: "m1",
  role: "user",
  parts: [{ type: "text", text: "hi" }],
};

describe("createAiChat", () => {
  it("names the topics", () => {
    expect(aiChatTopic("c1")).toBe("ai-chat:c1");
    expect(aiChatTopic("c1", "chat")).toBe("chat:c1");
    expect(aiChatListTopic("u1")).toBe("ai-chats:u1");
    expect(aiChatListTopic("u1", "lists")).toBe("lists:u1");
  });

  it("creates, reads, lists, updates and removes chats", async () => {
    const { user, server, chat } = fake();
    const created = await chat.chats.create("o1").orThrow();
    expect(created).toMatchObject({
      id: "c1",
      projectId: undefined,
      agentId: "agent",
      visibility: "organization",
      pinned: true,
      temporary: false,
      leafId: "m2",
    });
    expect(created.lastMessageAt.toString()).toBe(AT);
    expect(lastArgs(user)).toEqual({ tenant: "o1", fields: {} });

    await chat.chats
      .create("o1", {
        id: "c1",
        title: "T",
        model: null,
        projectId: "p1",
        agentId: "a",
        visibility: "private",
        pinned: false,
        temporary: true,
        ownerId: "u2",
      })
      .orThrow();
    expect(lastArgs(server)).toEqual({
      tenant: "o1",
      fields: {
        id: "c1",
        title: "T",
        model: null,
        project_id: "p1",
        agent_id: "a",
        visibility: "private",
        pinned: false,
        is_temporary: true,
        owner_id: "u2",
      },
    });

    expect((await chat.chats.get("c1").orThrow()).id).toBe("c1");
    const page = await chat.chats.list().orThrow();
    expect(page.items).toHaveLength(1);
    expect(page.next).toBe(`${AT}|c1`);
    expect(lastArgs(user)).toMatchObject({ tenant: null });
    await chat.chats
      .list({
        organizationId: "o1",
        search: "x",
        projectId: "p1",
        pinned: true,
        archived: true,
        cursor: "a",
        limit: 5,
      })
      .orThrow();
    expect(lastArgs(user)).toEqual({
      tenant: "o1",
      search: "x",
      project: "p1",
      pinned: true,
      archived: true,
      after: "a",
      size: 5,
    });

    const updated = await chat.chats
      .update("c1", {
        title: "New",
        model: "m",
        projectId: null,
        visibility: "private",
        pinned: false,
        archived: true,
      })
      .orThrow();
    expect(updated.visibility).toBe("private");
    expect(lastArgs(user)).toEqual({
      chat: "c1",
      fields: {
        title: "New",
        model: "m",
        project_id: null,
        visibility: "private",
        pinned: false,
        archived: true,
      },
    });
    await chat.chats.update("c1", {}).orThrow();
    expect(await chat.chats.remove("c1").orThrow()).toBe(true);
    expect(await chat.chats.purge(10).orThrow()).toBe(3);
    expect(lastArgs(server)).toEqual({ batch: 10 });
  });

  it("saves and lists projects", async () => {
    const { user, chat } = fake();
    const project = await chat.projects
      .create("o1", {
        name: "Research",
        instructions: "Be brief",
        defaultModel: null,
        pinned: true,
        archived: false,
      })
      .orThrow();
    expect(project).toMatchObject({
      name: "Research",
      instructions: "",
      defaultModel: "openai/gpt-5",
    });
    expect(project.archivedAt?.toString()).toBe(AT);
    expect(lastArgs(user)).toEqual({
      id: null,
      tenant: "o1",
      fields: {
        name: "Research",
        instructions: "Be brief",
        default_model: null,
        pinned: true,
        archived: false,
      },
    });
    await chat.projects.update("p1", {}).orThrow();
    expect(lastArgs(user)).toEqual({ id: "p1", tenant: null, fields: {} });
    expect(await chat.projects.list("o1").orThrow()).toHaveLength(1);
    expect(await chat.projects.remove("p1").orThrow()).toBe(true);
  });

  it("appends, saves and reads the message tree", async () => {
    const { user, server, chat } = fake();
    expect(await chat.messages.appendUser("c1", message).orThrow()).toEqual({
      messageId: "m1",
      parentId: undefined,
      created: true,
    });
    await chat.messages
      .appendUser(
        "c1",
        { ...message, metadata: { a: 1 } },
        { trigger: "regenerate-message", messageId: "m1" },
      )
      .orThrow();
    expect(lastArgs(user)).toEqual({
      chat: "c1",
      message: { ...message, metadata: { a: 1 } },
      trigger: "regenerate-message",
      message_id: "m1",
    });

    const saved = await chat.messages
      .saveAssistant(
        "c1",
        { id: "m2", role: "assistant", parts: [] },
        {
          parentId: "m1",
          status: "aborted",
          model: "m",
          format: "ai-sdk-ui",
          native: { id: "m2" },
          runId: "r1",
        },
      )
      .orThrow();
    expect(saved).toEqual({ messageId: "m2", parentId: "m1", created: false });
    expect(lastArgs(server)).toEqual({
      chat: "c1",
      message: { id: "m2", role: "assistant", parts: [] },
      parent_id: "m1",
      status: "aborted",
      model: "m",
      format: "ai-sdk-ui",
      native: { value: { id: "m2" } },
      run: "r1",
    });
    await chat.messages
      .saveAssistant(
        "c1",
        { id: "m2", role: "assistant", parts: [] },
        { parentId: "m1" },
      )
      .orThrow();
    expect(lastArgs(server)).toMatchObject({ native: undefined });

    const [first, second] = await chat.messages
      .path("c1", { leafId: "m2", native: true })
      .orThrow();
    expect(lastArgs(user)).toEqual({
      chat: "c1",
      leaf: "m2",
      include_native: true,
    });
    expect(first).toMatchObject({
      id: "m1",
      parentId: undefined,
      parts: [{ type: "text", text: "hi" }],
      siblingCount: 2,
      siblingIndex: 1,
      native: undefined,
    });
    expect(first).not.toHaveProperty("metadata");
    expect(second).toMatchObject({
      role: "assistant",
      parts: [],
      metadata: { tokens: 3 },
      format: "ai-sdk-ui",
      native: { id: "m2" },
      status: "aborted",
      siblingCount: 1,
      siblingIndex: 0,
    });
    await chat.messages.path("c1").orThrow();

    const [sibling] = await chat.messages.siblings("c1", "m1").orThrow();
    expect(sibling?.role).toBe("user");
    expect(await chat.messages.switchBranch("c1", "m1").orThrow()).toBe("m9");
  });

  it("claims, releases and stops runs", async () => {
    const { user, server, chat } = fake();
    expect(
      await chat.runs
        .claim("c1", "s1", { model: "m", messageId: "m2" })
        .orThrow(),
    ).toEqual({ claimed: true, streamId: "s1", runId: "r1" });
    expect(lastArgs(server)).toEqual({
      chat: "c1",
      stream: "s1",
      model: "m",
      message_id: "m2",
      engine: undefined,
      external_run_id: undefined,
    });
    await chat.runs
      .claim("c1", "s1", { engine: "workflow", externalRunId: "wrun_1" })
      .orThrow();
    expect(lastArgs(server)).toMatchObject({
      engine: "workflow",
      external_run_id: "wrun_1",
    });
    await chat.runs.claim("c1", "s1").orThrow();
    expect(
      await chat.runs
        .release("c1", "s1", {
          status: "error",
          usage: { tokens: 1 },
          generationId: "g",
          error: "boom",
          costMicroUsd: 5,
        })
        .orThrow(),
    ).toBe(true);
    expect(lastArgs(server)).toEqual({
      chat: "c1",
      stream: "s1",
      status: "failed",
      usage: { tokens: 1 },
      generation_id: "g",
      error: "boom",
      cost_micro_usd: 5,
    });
    await chat.runs.release("c1", "s1", { status: "stopped" }).orThrow();
    expect(lastArgs(server)).toMatchObject({ status: "cancelled" });
    await chat.runs.release("c1", "s1").orThrow();
    expect(await chat.runs.stop("c1").orThrow()).toEqual({
      streamId: "s1",
      runId: "r1",
    });
    expect(lastArgs(user)).toEqual({ chat: "c1" });
    expect(await chat.runs.setCost("g", 7, { tokens: 2 }).orThrow()).toBe(
      false,
    );

    const idle = fake({ request_ai_chat_stop: null });
    expect(await idle.chat.runs.stop("c1").orThrow()).toBeUndefined();
  });

  it("records and decides approvals and policies", async () => {
    const { user, server, chat } = fake();
    const pending = await chat.approvals
      .request("c1", { approvalId: "ap1", tool: "search", toolCallId: "t1" })
      .orThrow();
    expect(pending.decision).toBe("pending");
    expect(lastArgs(server)).toEqual({
      chat: "c1",
      approval: {
        approval_id: "ap1",
        tool: "search",
        tool_call_id: "t1",
        input: null,
        run_id: null,
        message_id: null,
        signature: null,
      },
    });
    await chat.approvals
      .request("c1", {
        approvalId: "ap1",
        tool: "search",
        toolCallId: "t1",
        input: { q: 1 },
        runId: "r1",
        messageId: "m2",
        signature: "s",
      })
      .orThrow();
    const decided = await chat.approvals.decide("ap1", true, "ok").orThrow();
    expect(decided).toMatchObject({
      decision: "approved",
      decidedBy: "u1",
      runId: undefined,
      input: { q: "x" },
    });
    expect(decided.decidedAt?.toString()).toBe(AT);
    expect(lastArgs(user)).toEqual({
      approval_id: "ap1",
      approved: true,
      reason: "ok",
    });
    expect(await chat.approvals.list("c1", ["ap1"]).orThrow()).toHaveLength(1);
    expect(
      await chat.approvals.setPolicy("o1", "search", "ask").orThrow(),
    ).toBe("ask");
    expect(await chat.approvals.policies("o1").orThrow()).toEqual({
      search: "deny",
    });
  });

  it("opens and answers pending inputs", async () => {
    const { user, server, chat } = fake();
    const open = await chat.inputs.open("c1", { question: "Which?" }).orThrow();
    expect(open).toMatchObject({ answer: null, answeredAt: undefined });
    expect(lastArgs(server)).toEqual({
      chat: "c1",
      input: {
        question: "Which?",
        schema: null,
        run_id: null,
        tool_call_id: null,
      },
    });
    await chat.inputs
      .open("c1", {
        question: "Q",
        schema: { type: "string" },
        runId: "r1",
        toolCallId: "t1",
      })
      .orThrow();
    const answered = await chat.inputs.answer("i1", "this").orThrow();
    expect(answered.answer).toBe("this");
    expect(lastArgs(user)).toEqual({ id: "i1", answer: { value: "this" } });
  });

  it("rates messages", async () => {
    const { user, chat } = fake();
    expect(
      await chat.feedback
        .rate("c1", "m2", -1, { reason: "wrong", comment: "no" })
        .orThrow(),
    ).toEqual({
      chatId: "c1",
      messageId: "m2",
      rating: -1,
      reason: "wrong",
      comment: undefined,
    });
    await chat.feedback.rate("c1", "m2", 0).orThrow();
    expect(lastArgs(user)).toMatchObject({ rating: null });
    const cleared = fake({
      rate_ai_message: { chat_id: "c1", message_id: "m2", rating: null },
    });
    expect(
      (await cleared.chat.feedback.rate("c1", "m2", 0).orThrow()).rating,
    ).toBe(0);
    const removed = fake({ rate_ai_message: null });
    expect(await removed.chat.feedback.rate("c1", "m2", 0).orThrow()).toEqual({
      chatId: "c1",
      messageId: "m2",
      rating: 0,
      reason: undefined,
      comment: undefined,
    });
  });

  it("shares chats by token", async () => {
    const { chat } = fake();
    const link = await chat.shares.create("c1").orThrow();
    expect(link).toMatchObject({ id: "sh1", token: "tok", leafId: "m2" });
    expect(await chat.shares.revoke("sh1").orThrow()).toBe(true);
    const [share] = await chat.shares.list("c1").orThrow();
    expect(share).toMatchObject({ createdBy: "u1", revokedAt: undefined });
    const shared = await chat.shares.get("tok").orThrow();
    expect(shared.chat).toMatchObject({ title: "", model: undefined });
    expect(shared.messages).toHaveLength(1);
  });

  it("reads and refreshes the model catalog and moderation", async () => {
    const { server, chat } = fake();
    const [model] = await chat.models.allowed().orThrow();
    expect(model).toMatchObject({
      id: "openai/gpt-5",
      capabilities: {},
      plans: ["pro"],
      enabled: true,
    });
    await chat.models.allowed("o1").orThrow();
    expect(
      await chat.models
        .upsert([{ id: "openai/gpt-5" }], { prune: true })
        .orThrow(),
    ).toBe(2);
    expect(lastArgs(server)).toEqual({
      models: { models: [{ id: "openai/gpt-5" }] },
      prune: true,
    });
    await chat.models.upsert([]).orThrow();

    const event = await chat.moderation
      .record({
        organizationId: "o1",
        stage: "output",
        action: "redact",
        category: "pii",
      })
      .orThrow();
    expect(event).toMatchObject({ action: "redact", score: 0.9 });
    expect(lastArgs(server)).toMatchObject({
      event: { organization_id: "o1", chat_id: null, score: null },
    });
    await chat.moderation
      .record({
        organizationId: "o1",
        stage: "input",
        action: "block",
        chatId: "c1",
        messageId: "m1",
        userId: "u1",
        category: "abuse",
        score: 1,
      })
      .orThrow();
    const [listed] = await chat.moderation.list("o1", 5).orThrow();
    expect(listed?.score).toBeUndefined();
    const blank = fake({
      list_ai_moderation_events: [{ ...moderationRow, category: null }],
    });
    const [none] = await blank.chat.moderation.list("o1").orThrow();
    expect(none?.category).toBe("");
  });

  it("uses the user transport when no service transport is given", async () => {
    const call = vi.fn(async () => 1);
    const chat = createAiChat({ transport: { call }, schema: "api" });
    expect(await chat.models.upsert([]).orThrow()).toBe(1);
    expect(call).toHaveBeenCalledWith("api", "upsert_ai_models", {
      models: { models: [] },
      prune: undefined,
    });
  });

  it("returns database errors as results", async () => {
    const chat = createAiChat({
      transport: {
        call: () =>
          Promise.reject(
            Object.assign(new Error("No chat"), {
              code: "P0002",
              hint: "AI_CHAT_NOT_FOUND",
            }),
          ),
      },
    });
    expect(await chat.chats.get("c1")).toMatchObject({
      ok: false,
      error: { kind: "not_found" },
    });
  });
});
