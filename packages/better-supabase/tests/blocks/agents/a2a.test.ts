import { describe, expect, it } from "vitest";

import type { A2AChatClient } from "../../../src/blocks/agents/index.ts";

import {
  A2A_CARD_PATH,
  agentCard,
  agentCardResponse,
  createA2AHandler,
  isTerminalTask,
  taskOf,
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
      appendUser: (_chatId: string, message: unknown) => {
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

const runOf = (status: string, extra: Record<string, unknown> = {}) => ({
  id: "run1",
  chatId: "chat1",
  status,
  startedAt: Temporal.Instant.from("2026-01-01T00:00:00Z"),
  endedAt: undefined,
  error: undefined,
  ...extra,
});

interface Overrides {
  run?: () => unknown;
  runs?: unknown[];
  chats?: Record<string, unknown>;
  messages?: Record<string, unknown>;
  start?: () => Promise<{ runId: string }>;
  path?: () => unknown;
}

function custom(overrides: Overrides, handlerOptions = {}) {
  let index = 0;

  const chat = {
    chats: {
      create: () => AsyncResult.ok({ id: "chat1" }),
      get: () => AsyncResult.ok({ id: "chat9" }),
      ...overrides.chats,
    },
    messages: {
      appendUser: () => AsyncResult.ok({}),
      path:
        overrides.path ??
        (() =>
          AsyncResult.ok([
            { role: "assistant", parts: [{ type: "text", text: "A" }] },
            { role: "assistant", parts: [{ type: "text", text: "B" }] },
          ])),
      ...overrides.messages,
    },
    runs: {
      get: () => {
        if (overrides.runs !== undefined) {
          const value =
            overrides.runs[Math.min(index, overrides.runs.length - 1)];

          index += 1;

          return value;
        }

        return overrides.run === undefined
          ? AsyncResult.ok(runOf("completed"))
          : overrides.run();
      },
      stop: () => AsyncResult.ok(undefined),
    },
  } as unknown as A2AChatClient;

  return createA2AHandler({
    pollMs: 1,
    ...handlerOptions,
    resolve: () =>
      Promise.resolve({
        chat,
        organizationId: null,
        start: overrides.start ?? (() => Promise.resolve({ runId: "run1" })),
      }),
  });
}

const send = async (
  handler: (request: Request) => Promise<Response>,
  method: string,
  params: unknown,
) => (await call(handler, method, params, {})).json();

describe("agent cards and tasks in full", () => {
  it("carries every optional card field", async () => {
    const bare = {
      ...agent("a", "public"),
      tools: [],
      starters: [],
      description: "Does things",
    };

    const card = agentCard([bare], {
      ...OPTIONS,
      streaming: false,
      provider: { organization: "Acme", url: "https://acme.test" },
      documentationUrl: "https://acme.test/docs",
      securitySchemes: { bearer: {} },
      securityRequirements: [{ bearer: [] }],
    });

    expect(card.skills[0]).toEqual({
      id: "a",
      name: "A",
      description: "Does things",
      tags: ["agent"],
    });
    expect(card).toMatchObject({
      provider: { organization: "Acme" },
      documentationUrl: "https://acme.test/docs",
      securitySchemes: { bearer: {} },
      securityRequirements: [{ bearer: [] }],
      capabilities: { streaming: false },
    });

    const response = await agentCardResponse(
      new Request("https://acme.test/card"),
      card,
      { maxAge: 60 },
    );

    expect(response.headers.get("cache-control")).toBe("public, max-age=60");
  });

  it("maps every run state and builds tasks", () => {
    expect(taskStateOf("running")).toBe("TASK_STATE_WORKING");
    expect(taskStateOf("completed")).toBe("TASK_STATE_COMPLETED");
    expect(taskStateOf("failed")).toBe("TASK_STATE_FAILED");
    expect(isTerminalTask("TASK_STATE_FAILED")).toBe(true);
    expect(isTerminalTask("TASK_STATE_WORKING")).toBe(false);

    // SAFETY: the run carries the fields taskOf reads.
    const failed = taskOf(
      runOf("failed", {
        error: "bad",
        endedAt: Temporal.Instant.from("2026-01-02T00:00:00Z"),
      }) as never,
    );

    expect(failed.status.message?.parts).toEqual([{ text: "bad" }]);
    expect(failed.status.timestamp).toBe("2026-01-02T00:00:00Z");
    // SAFETY: as above.
    expect(taskOf(runOf("failed") as never).status.message).toBeUndefined();
    // SAFETY: as above.
    expect(taskOf(runOf("completed") as never, "yes").artifacts).toHaveLength(
      1,
    );
    // SAFETY: as above.
    expect(taskOf(runOf("completed") as never).artifacts).toBeUndefined();
  });
});

describe("createA2AHandler requests", () => {
  it("refuses other methods and uses a custom challenge", async () => {
    const handler = createA2AHandler({
      challenge: "Basic",
      resolve: () => Promise.resolve(undefined),
    });

    const denied = await handler(
      new Request("https://acme.test/a2a", { method: "POST" }),
    );

    expect(denied.headers.get("www-authenticate")).toBe("Basic");

    const get = await handler(new Request("https://acme.test/a2a"));

    expect(get.status).toBe(405);
  });

  it("rejects bad envelopes", async () => {
    const handler = custom({});

    const raw = (body: string) =>
      handler(
        new Request("https://acme.test/a2a", {
          method: "POST",
          headers: { "a2a-version": "1.0" },
          body,
        }),
      );

    expect((await (await raw("{nope")).json()).error.code).toBe(-32_700);
    expect((await (await raw("[]")).json()).error.code).toBe(-32_600);
    expect(
      (await (await raw('{"jsonrpc":"2.0","method":1}')).json()).error.code,
    ).toBe(-32_600);
  });

  it("accepts the version as a query parameter", async () => {
    const handler = custom({});

    const response = await handler(
      new Request("https://acme.test/a2a?A2A-Version=1.0", {
        method: "POST",
        body: JSON.stringify({
          jsonrpc: "2.0",
          id: 1,
          method: "GetTask",
          params: { id: "run1" },
        }),
      }),
    );

    expect((await response.json()).result.id).toBe("run1");
  });

  it("validates the message", async () => {
    const handler = custom({});

    expect(
      (
        await send(handler, "SendMessage", {
          message: { parts: [{ text: "x" }] },
        })
      ).error.code,
    ).toBe(-32_602);
    expect((await send(handler, "SendMessage", {})).error.code).toBe(-32_602);

    for (const parts of [[], [{ text: 1 }], "x", [null]]) {
      expect(
        (
          await send(handler, "SendMessage", {
            message: { messageId: "m", parts },
          })
        ).error.code,
      ).toBe(-32_005);
    }
  });

  it("continues a task, a context or starts a chat", async () => {
    const starts: unknown[] = [];

    const handler = custom({
      runs: [
        AsyncResult.ok(runOf("running")),
        AsyncResult.ok(runOf("running")),
        AsyncResult.ok(runOf("completed")),
      ],
      start: (...args: unknown[]) => {
        starts.push(args);

        return Promise.resolve({ runId: "run1" });
      },
    });

    const body = await send(handler, "SendMessage", {
      message: { ...message, taskId: "run1" },
      metadata: { agent: "helper" },
    });

    expect(body.result.task.status.state).toBe("TASK_STATE_COMPLETED");
    expect(body.result.task.artifacts[0].parts[0].text).toBe("B");

    const context = await send(
      custom({ run: () => AsyncResult.ok(runOf("completed")) }),
      "SendMessage",
      { message: { ...message, contextId: "chat9" }, metadata: { agent: 5 } },
    );

    expect(context.result.task.contextId).toBe("chat1");
  });

  it("answers errors of continuing", async () => {
    const notFound = AsyncResult.err(dbError("not_found", "x"));

    expect(
      (
        await send(custom({ run: () => notFound }), "SendMessage", {
          message: { ...message, taskId: "gone" },
        })
      ).error.code,
    ).toBe(-32_001);
    expect(
      (
        await send(custom({}), "SendMessage", {
          message: { ...message, taskId: "run1" },
        })
      ).error.code,
    ).toBe(-32_004);
    expect(
      (
        await send(
          custom({
            chats: { get: () => AsyncResult.err(dbError("not_found", "x")) },
          }),
          "SendMessage",
          { message: { ...message, contextId: "nope" } },
        )
      ).error.code,
    ).toBe(-32_602);
    expect(
      (
        await send(
          custom({
            chats: {
              create: () => AsyncResult.err(dbError("unexpected", "x")),
            },
          }),
          "SendMessage",
          { message },
        )
      ).error.code,
    ).toBe(-32_603);
    expect(
      (
        await send(
          custom({
            messages: {
              appendUser: () => AsyncResult.err(dbError("unexpected", "x")),
            },
          }),
          "SendMessage",
          { message },
        )
      ).error.code,
    ).toBe(-32_603);
    expect(
      (
        await send(
          custom({ start: () => Promise.reject(new Error("no")) }),
          "SendMessage",
          { message },
        )
      ).error.code,
    ).toBe(-32_603);
  });

  it("reports an unreadable run and a missing answer", async () => {
    const unreadable = custom({
      run: () => AsyncResult.err(dbError("not_found", "x")),
    });

    expect(
      (await send(unreadable, "SendMessage", { message })).error.code,
    ).toBe(-32_603);
    expect(
      (
        await send(unreadable, "SendMessage", {
          message,
          configuration: { returnImmediately: true },
        })
      ).error.code,
    ).toBe(-32_603);

    const noAnswer = custom({
      path: () => AsyncResult.ok([{ role: "user", parts: [] }]),
    });

    expect(
      (await send(noAnswer, "SendMessage", { message })).result.task.artifacts,
    ).toBeUndefined();

    const nonText = custom({
      path: () =>
        AsyncResult.ok([{ role: "assistant", parts: [{ type: "tool" }] }]),
    });

    expect(
      (await send(nonText, "SendMessage", { message })).result.task.artifacts,
    ).toBeUndefined();

    const noPath = custom({
      messages: { path: () => AsyncResult.err(dbError("unexpected", "x")) },
    });

    expect(
      (await send(noPath, "SendMessage", { message })).result.task.artifacts,
    ).toBeUndefined();
  });

  it("times out waiting for a run that does not end", async () => {
    const handler = custom(
      { run: () => AsyncResult.ok(runOf("running")) },
      { streamTimeoutMs: 5 },
    );

    const body = await send(handler, "SendMessage", { message });

    expect(body.result.task.status.state).toBe("TASK_STATE_WORKING");
  });

  it("streams status and artifact updates until the end", async () => {
    const handler = custom({
      runs: [
        AsyncResult.ok(runOf("running")),
        AsyncResult.ok(runOf("running")),
        AsyncResult.ok(runOf("completed")),
      ],
    });

    const response = await call(handler, "SendStreamingMessage", { message });
    const text = await response.text();

    expect(text).toContain('"statusUpdate"');
    expect(text).toContain('"artifactUpdate"');

    const failed = custom({
      runs: [AsyncResult.ok(runOf("running")), AsyncResult.ok(runOf("failed"))],
    });

    const failedText = await (
      await call(failed, "SendStreamingMessage", { message })
    ).text();

    expect(failedText).toContain("TASK_STATE_FAILED");
    expect(failedText).not.toContain("artifactUpdate");

    const gone = custom({
      runs: [
        AsyncResult.ok(runOf("running")),
        AsyncResult.err(dbError("not_found", "x")),
      ],
    });

    expect(
      await (await call(gone, "SendStreamingMessage", { message })).text(),
    ).toContain('"task"');

    const slow = custom(
      { run: () => AsyncResult.ok(runOf("running")) },
      { streamTimeoutMs: 5 },
    );

    expect(
      await (await call(slow, "SendStreamingMessage", { message })).text(),
    ).toContain("TASK_STATE_WORKING");
  });

  it("handles GetTask and CancelTask edge cases", async () => {
    const handler = custom({});

    expect((await send(handler, "GetTask", {})).error.code).toBe(-32_001);
    expect((await send(handler, "CancelTask", {})).error.code).toBe(-32_001);

    const missing = custom({
      run: () => AsyncResult.err(dbError("not_found", "x")),
    });

    expect((await send(missing, "CancelTask", { id: "x" })).error.code).toBe(
      -32_001,
    );

    const vanishing = custom({
      runs: [
        AsyncResult.ok(runOf("running")),
        AsyncResult.err(dbError("not_found", "x")),
      ],
    });

    expect(
      (await send(vanishing, "CancelTask", { id: "run1" })).error.code,
    ).toBe(-32_001);

    const cancelled = custom({
      runs: [
        AsyncResult.ok(runOf("running")),
        AsyncResult.ok(runOf("cancelled")),
      ],
    });

    expect(
      (await send(cancelled, "CancelTask", { id: "run1" })).result.status.state,
    ).toBe("TASK_STATE_CANCELED");
  });
});
