import { describe, expect, it } from "vitest";

import type { A2AChatClient } from "../../../src/blocks/agents/index.ts";

import {
  A2A_CARD_PATH,
  agentCard,
  agentCardResponse,
  createA2AHandler,
  taskStateOf,
} from "../../../src/blocks/agents/index.ts";
import { dbError } from "../../../src/core/errors.ts";
import { AsyncResult } from "../../../src/core/result.ts";

const agent = (
  slug: string,
  visibility: "public" | "private" | "organization",
) => ({
  slug,
  name: slug.toUpperCase(),
  description: "",
  tools: ["search"],
  starters: ["Hello"],
  visibility,
});

const OPTIONS = {
  name: "Acme agents",
  description: "Agents of Acme",
  version: "1.2.0",
  url: "https://acme.test/a2a",
};

describe("agentCard", () => {
  it("lists only public agents as skills", () => {
    const card = agentCard(
      [agent("a", "public"), agent("b", "private"), agent("c", "organization")],
      OPTIONS,
    );

    expect(card.skills.map((skill) => skill.id)).toEqual(["a"]);
    expect(card.supportedInterfaces[0]).toEqual({
      url: "https://acme.test/a2a",
      protocolBinding: "JSONRPC",
      protocolVersion: "1.0",
    });
    expect(card.skills[0]?.description).toBe("A");
    expect(card.capabilities.streaming).toBe(true);
  });

  it("adds organization agents on request", () => {
    const card = agentCard([agent("c", "organization")], {
      ...OPTIONS,
      includeOrganization: true,
    });

    expect(card.skills).toHaveLength(1);
  });

  it("serves an ETag and answers If-None-Match with 304", async () => {
    const card = agentCard([agent("a", "public")], OPTIONS);
    const url = `https://acme.test${A2A_CARD_PATH}`;
    const first = await agentCardResponse(new Request(url), card);
    const etag = first.headers.get("etag") ?? "";

    expect(first.status).toBe(200);
    expect(etag).not.toBe("");

    const second = await agentCardResponse(
      new Request(url, { headers: { "if-none-match": etag } }),
      card,
    );

    expect(second.status).toBe(304);
  });
});

describe("taskStateOf", () => {
  it("maps run states", () => {
    expect(taskStateOf("queued")).toBe("TASK_STATE_SUBMITTED");
    expect(taskStateOf("cancel_requested")).toBe("TASK_STATE_WORKING");
    expect(taskStateOf("cancelled")).toBe("TASK_STATE_CANCELED");
  });
});

function fixture(status: string) {
  const stored: unknown[] = [];
  const stopped: string[] = [];

  const run = {
    id: "run1",
    chatId: "chat1",
    status,
    startedAt: Temporal.Instant.from("2026-01-01T00:00:00Z"),
    endedAt: undefined,
    error: undefined,
  };

  const chat = {
    chats: {
      create: () => AsyncResult.ok({ id: "chat1" }),
      get: () => AsyncResult.ok({ id: "chat1" }),
    },
    messages: {
      appendUser: ({ message }: { chatId: string; message: unknown }) => {
        stored.push(message);

        return AsyncResult.ok({});
      },
      path: () =>
        AsyncResult.ok([
          { role: "user", parts: [{ type: "text", text: "Hi" }] },
          { role: "assistant", parts: [{ type: "text", text: "Hello" }] },
        ]),
    },
    runs: {
      get: (id: string) =>
        id === "run1"
          ? AsyncResult.ok(run)
          : AsyncResult.err(dbError("not_found", "No such run")),
      stop: (chatId: string) => {
        stopped.push(chatId);

        return AsyncResult.ok(undefined);
      },
    },
  } as unknown as A2AChatClient;

  const handler = createA2AHandler({
    pollMs: 1,
    resolve: (request) =>
      Promise.resolve(
        request.headers.get("authorization") === "Bearer ok"
          ? {
              chat,
              organizationId: "org1",
              start: () => Promise.resolve({ runId: "run1" }),
            }
          : undefined,
      ),
  });

  return { handler, stored, stopped };
}

const call = (
  handler: (request: Request) => Promise<Response>,
  method: string,
  params: unknown,
  headers: Record<string, string> = {},
) =>
  handler(
    new Request("https://acme.test/a2a", {
      method: "POST",
      headers: { authorization: "Bearer ok", "a2a-version": "1.0", ...headers },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
    }),
  );

const message = { messageId: "m1", role: "ROLE_USER", parts: [{ text: "Hi" }] };

describe("createA2AHandler", () => {
  it("answers 401 without credentials", async () => {
    const { handler } = fixture("completed");

    const response = await handler(
      new Request("https://acme.test/a2a", { method: "POST", body: "{}" }),
    );

    expect(response.status).toBe(401);
    expect(response.headers.get("www-authenticate")).toBe("Bearer");
  });

  it("refuses a request without the version header", async () => {
    const { handler } = fixture("completed");

    const response = await call(
      handler,
      "GetTask",
      { id: "run1" },
      { "a2a-version": "" },
    );

    const body = await response.json();

    expect(body.error.code).toBe(-32_009);
  });

  it("stores the message and returns the completed task with its answer", async () => {
    const { handler, stored } = fixture("completed");
    const response = await call(handler, "SendMessage", { message });
    const body = await response.json();

    expect(stored).toEqual([
      { id: "m1", role: "user", parts: [{ type: "text", text: "Hi" }] },
    ]);
    expect(body.result.task).toMatchObject({
      id: "run1",
      contextId: "chat1",
      status: { state: "TASK_STATE_COMPLETED" },
      artifacts: [{ parts: [{ text: "Hello" }] }],
    });
  });

  it("returns right away when asked to", async () => {
    const { handler } = fixture("running");

    const response = await call(handler, "SendMessage", {
      message,
      configuration: { returnImmediately: true },
    });

    const body = await response.json();

    expect(body.result.task.status.state).toBe("TASK_STATE_WORKING");
  });

  it("rejects parts that are not text", async () => {
    const { handler } = fixture("completed");

    const response = await call(handler, "SendMessage", {
      message: { ...message, parts: [{ url: "https://x.test/f" }] },
    });

    const body = await response.json();

    expect(body.error.code).toBe(-32_005);
  });

  it("streams the task and closes on a terminal state", async () => {
    const { handler } = fixture("completed");
    const response = await call(handler, "SendStreamingMessage", { message });
    const text = await response.text();

    expect(response.headers.get("content-type")).toBe("text/event-stream");
    expect(text).toContain('"task"');
    expect(text.startsWith("data: ")).toBe(true);
  });

  it("gets a task and reports an unknown id", async () => {
    const { handler } = fixture("running");
    const found = await (await call(handler, "GetTask", { id: "run1" })).json();

    const missing = await (
      await call(handler, "GetTask", { id: "nope" })
    ).json();

    expect(found.result.id).toBe("run1");
    expect(missing.error.code).toBe(-32_001);
  });

  it("cancels a running task and refuses a finished one", async () => {
    const running = fixture("running");
    await call(running.handler, "CancelTask", { id: "run1" });

    expect(running.stopped).toEqual(["chat1"]);

    const done = fixture("completed");

    const body = await (
      await call(done.handler, "CancelTask", { id: "run1" })
    ).json();

    expect(body.error.code).toBe(-32_002);
  });

  it("answers an unknown method", async () => {
    const { handler } = fixture("running");
    const body = await (await call(handler, "ListTasks", {})).json();

    expect(body.error.code).toBe(-32_601);
  });
});
