import { describe, expect, it, vi } from "vitest";

import type { AssistantOptions } from "../../../src/ai-sdk/chat/index.ts";

import { AI_SDK_UI_FORMAT } from "../../../src/ai-sdk/index.ts";
import { dbError } from "../../../src/core/errors.ts";
import { fakeChats, post, record, setup, userMessage } from "./fakes.ts";

describe("createAssistant", () => {
  it("stores the turn, streams the answer and records its usage", async () => {
    const enqueueCostBackfill = vi.fn(async () => undefined);
    const onFinish = vi.fn();
    const { assistant, context, fake, pending, run } = setup({
      enqueueCostBackfill,
      onFinish,
    });
    const response = await assistant.respond(
      post({ id: "c1", message: userMessage() }),
      context,
    );
    expect(response.status).toBe(200);
    expect(response.headers.get("x-vercel-ai-ui-message-stream")).toBe("v1");
    const body = await response.text();
    expect(body).toContain('"delta":"Hello there"');
    expect(body).toContain("data: [DONE]");
    await Promise.all(pending);

    expect(run).toHaveBeenCalledOnce();
    const args = run.mock.calls[0]?.[0];
    expect(args?.model).toBe("openai/gpt-5");
    expect(args?.providerOptions).toEqual({
      gateway: {
        user: "user",
        tags: ["org:org", "chat:c1", "feature:chat"],
      },
    });
    expect(args?.messages).toEqual([
      { role: "user", content: [{ type: "text", text: "Hi" }] },
    ]);
    expect(fake.saved).toEqual([
      {
        chatId: "c1",
        message: {
          id: "id2",
          role: "assistant",
          parts: [
            { type: "step", boundary: "start" },
            { type: "text", text: "Hello there", state: "done" },
          ],
        },
        opts: expect.objectContaining({
          parentId: "u1",
          status: "complete",
          model: "openai/gpt-5",
          format: AI_SDK_UI_FORMAT,
          runId: "run1",
        }),
      },
    ]);
    expect(fake.released).toEqual([
      {
        chatId: "c1",
        streamId: "id1",
        opts: {
          status: "done",
          usage: {
            inputTokens: 7,
            outputTokens: 3,
            totalTokens: 10,
            cachedInputTokens: 0,
            reasoningTokens: 0,
          },
          generationId: "gen_1",
        },
      },
    ]);
    expect(enqueueCostBackfill).toHaveBeenCalledWith({
      generationId: "gen_1",
      organizationId: "org",
    });
    expect(onFinish).toHaveBeenCalledWith(
      expect.objectContaining({ status: "done", model: "openai/gpt-5" }),
    );
  });

  it("replays the stored stream and answers 204 when nothing runs", async () => {
    const { assistant, context, fake, pending } = setup();
    const first = await assistant.respond(
      post({ id: "c1", messages: [userMessage()] }),
      context,
    );
    const live = await first.text();
    await Promise.all(pending);
    const replay = await assistant.resume("c1", context);
    expect(replay.status).toBe(200);
    expect(await replay.text()).toBe(live);
    const chat = fake.raw.get("c1");
    if (chat) fake.raw.set("c1", { ...chat, activeStreamId: undefined });
    expect((await assistant.resume("c1", context)).status).toBe(204);
    expect((await assistant.resume("nope", context)).status).toBe(204);
    const done = await assistant.resume("c1", context, { fromIdx: 0 });
    expect(done.status).toBe(204);
  });

  it("resumes past the end with 204 and passes the signal", async () => {
    const { assistant, context, pending } = setup();
    const first = await assistant.respond(
      post({ id: "c1", message: userMessage() }),
      context,
    );
    await first.text();
    await Promise.all(pending);
    const after = await assistant.resume("c1", context, {
      fromIdx: 10_000,
      signal: new AbortController().signal,
    });
    expect(after.status).toBe(204);
  });

  it("sends the history it has, with the stored native answer", async () => {
    const { assistant, context, fake, pending, run } = setup();
    await (
      await assistant.respond(
        post({ id: "c1", message: userMessage() }),
        context,
      )
    ).text();
    await Promise.all(pending);
    await (
      await assistant.respond(
        post({ id: "c1", message: userMessage("u2", "Again") }),
        context,
      )
    ).text();
    await Promise.all(pending);
    expect(run.mock.calls[1]?.[0].uiMessages.map((m) => m.id)).toEqual([
      "u1",
      "id2",
      "u2",
    ]);
    expect(fake.tree.at(-1)?.native).toMatchObject({ id: "id4" });
  });

  it("regenerates from the user's message", async () => {
    const { assistant, context, fake, pending } = setup();
    await (
      await assistant.respond(
        post({ id: "c1", message: userMessage() }),
        context,
      )
    ).text();
    await Promise.all(pending);
    const response = await assistant.respond(
      post({
        id: "c1",
        message: userMessage(),
        trigger: "regenerate-message",
        messageId: "id2",
      }),
      context,
    );
    await response.text();
    await Promise.all(pending);
    expect(fake.saved).toHaveLength(2);
  });

  it("rejects bad requests", async () => {
    const { assistant, context } = setup();
    const status = async (body: unknown) =>
      (await assistant.respond(post(body), context)).status;
    expect(await status("{")).toBe(400);
    expect(await status([])).toBe(400);
    expect(await status({ id: "" })).toBe(400);
    expect(
      await status({
        id: "c",
        message: { id: "a", role: "assistant", parts: [] },
      }),
    ).toBe(400);
    expect(
      await status({ id: "c", message: userMessage(), trigger: "other" }),
    ).toBe(400);
  });

  it("checks the model against the catalog", async () => {
    const fake = fakeChats({ models: ["anthropic/claude", "openai/gpt-5"] });
    const { assistant, context, pending, run } = setup({}, fake);
    const refused = await assistant.respond(
      post({ id: "c1", message: userMessage(), model: "x/unknown" }),
      context,
    );
    expect(refused.status).toBe(403);
    await (
      await assistant.respond(
        post({ id: "c2", message: userMessage(), model: "anthropic/claude" }),
        context,
      )
    ).text();
    await Promise.all(pending);
    expect(run.mock.calls[0]?.[0].model).toBe("anthropic/claude");

    const other = fakeChats({ models: ["anthropic/claude"] });
    const second = setup({}, other);
    await (
      await second.assistant.respond(
        post({ id: "c3", message: userMessage() }),
        second.context,
      )
    ).text();
    expect(second.run.mock.calls[0]?.[0].model).toBe("anthropic/claude");
  });

  it("uses the chat's model when it is allowed", async () => {
    const fake = fakeChats({ models: ["a/one", "a/two"] });
    fake.raw.set("c1", record("c1", { model: "a/two" }));
    const { assistant, context, run } = setup({ defaultModel: "a/one" }, fake);
    await (
      await assistant.respond(
        post({ id: "c1", message: userMessage() }),
        context,
      )
    ).text();
    expect(run.mock.calls[0]?.[0].model).toBe("a/two");
    const empty = fakeChats({ models: [] });
    empty.raw.set("c9", record("c9", { model: "z/any" }));
    const free = setup({}, empty);
    await (
      await free.assistant.respond(
        post({ id: "c9", message: userMessage() }),
        free.context,
      )
    ).text();
    expect(free.run.mock.calls[0]?.[0].model).toBe("z/any");
  });

  it("falls back to the first allowed model", async () => {
    const fake = fakeChats({ models: ["a/only"] });
    const { assistant, context, run } = setup({ defaultModel: "b/gone" }, fake);
    await (
      await assistant.respond(
        post({ id: "c1", message: userMessage() }),
        context,
      )
    ).text();
    expect(run.mock.calls[0]?.[0].model).toBe("a/only");
  });

  it("blocks and records moderated messages", async () => {
    const moderate = vi
      .fn<NonNullable<AssistantOptions["moderate"]>>()
      .mockResolvedValueOnce({ action: "block", category: "pii", score: 0.9 })
      .mockResolvedValueOnce({ action: "flag", category: "tone" })
      .mockResolvedValueOnce({ action: "allow", category: "none" });
    const { assistant, context, fake } = setup({ moderate });
    const blocked = await assistant.respond(
      post({ id: "c1", message: userMessage() }),
      context,
    );
    expect(blocked.status).toBe(403);
    expect(await blocked.json()).toMatchObject({
      code: "AI_MODERATION_BLOCKED",
    });
    const flagged = await assistant.respond(
      post({ id: "c1", message: userMessage() }),
      context,
    );
    expect(flagged.status).toBe(200);
    await flagged.text();
    const allowed = await assistant.respond(
      post({ id: "c1", message: userMessage("u2") }),
      context,
    );
    await allowed.text();
    expect(fake.moderated).toEqual([
      expect.objectContaining({ action: "block", score: 0.9, stage: "input" }),
      expect.objectContaining({ action: "flag", category: "tone" }),
    ]);
  });

  it("answers 429 when the quota is used up", async () => {
    const { assistant, context, run } = setup({
      quota: async () =>
        dbError("quota_exceeded", "used up", { meter: "ai", retryAfter: 9 }),
    });
    const response = await assistant.respond(
      post({ id: "c1", message: userMessage() }),
      context,
    );
    expect(response.status).toBe(429);
    expect(response.headers.get("retry-after")).toBe("9");
    expect(run).not.toHaveBeenCalled();
    const open = setup({ quota: async () => undefined });
    expect(
      (
        await open.assistant.respond(
          post({ id: "c1", message: userMessage() }),
          open.context,
        )
      ).status,
    ).toBe(200);
  });

  it("answers 409 while another answer runs", async () => {
    const { assistant, context } = setup({}, fakeChats({ claimed: false }));
    const response = await assistant.respond(
      post({ id: "c1", message: userMessage() }),
      context,
    );
    expect(response.status).toBe(409);
  });

  it("releases the run when the model can't start", async () => {
    const { assistant, context, fake } = setup({
      run: () => {
        throw new Error("no key");
      },
    });
    const response = await assistant.respond(
      post({ id: "c1", message: userMessage() }),
      context,
    );
    expect(response.status).toBe(500);
    expect(fake.released).toEqual([
      {
        chatId: "c1",
        streamId: "id1",
        opts: { status: "error", error: "Error: no key" },
      },
    ]);
  });

  it("passes block errors through", async () => {
    const { assistant, context } = setup(
      {},
      fakeChats({ getError: dbError("forbidden", "no") }),
    );
    expect(
      (
        await assistant.respond(
          post({ id: "c1", message: userMessage() }),
          context,
        )
      ).status,
    ).toBe(403);
    expect((await assistant.resume("c1", context)).status).toBe(403);
  });

  it("stops the running answer", async () => {
    const { assistant, context, fake } = setup();
    expect((await assistant.stop("c1", context)).status).toBe(204);
    expect((await assistant.stop("missing", context)).status).toBe(403);
    expect(fake.stops).toEqual(["c1", "missing"]);
  });
});
