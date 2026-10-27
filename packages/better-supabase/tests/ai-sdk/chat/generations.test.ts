import type { StandardSchemaV1 } from "@standard-schema/spec";

import { APICallError, streamText } from "ai";
import { describe, expect, it, vi } from "vitest";

import type {
  GenerationContext,
  GenerationRunArgs,
} from "../../../src/ai-sdk/chat/index.ts";

import {
  createCompletionRoute,
  createObjectRoute,
} from "../../../src/ai-sdk/chat/index.ts";
import { dbError } from "../../../src/core/errors.ts";
import { mockModel, post } from "./fakes.ts";

function context(): GenerationContext & {
  readonly pending: Promise<unknown>[];
} {
  const pending: Promise<unknown>[] = [];

  return {
    userId: "user",
    organizationId: "org",
    waitUntil: (promise) => {
      pending.push(promise);
    },
    pending,
  };
}

const run = vi.fn(<T>(args: GenerationRunArgs<T>) =>
  streamText({
    model: mockModel('{"title":"Hi"}'),
    prompt: JSON.stringify(args.input),
    abortSignal: args.abortSignal,
    providerOptions: args.providerOptions,
  }),
);

const titleSchema: StandardSchemaV1<unknown, { topic: string }> = {
  "~standard": {
    version: 1,
    vendor: "test",
    validate: (value) =>
      typeof value === "object" &&
      value !== null &&
      "topic" in value &&
      typeof value.topic === "string"
        ? { value: { topic: value.topic } }
        : { issues: [{ message: "Expected a topic", path: ["topic"] }] },
  },
};

describe("createCompletionRoute", () => {
  it("streams the text and reports the usage after the end", async () => {
    const onFinish = vi.fn();

    const route = createCompletionRoute({
      model: "openai/gpt-5",
      run,
      onFinish,
    });

    const ctx = context();

    const response = await route.respond(post({ prompt: "Say hi" }), ctx);

    expect(response.status).toBe(200);
    expect(await response.text()).toBe('{"title":"Hi"}');
    await Promise.all(ctx.pending);
    expect(run.mock.lastCall?.[0]).toMatchObject({
      input: "Say hi",
      model: "openai/gpt-5",
      providerOptions: {
        gateway: { user: "user", tags: ["org:org", "feature:completion"] },
      },
    });
    expect(onFinish).toHaveBeenCalledWith(
      expect.objectContaining({
        input: "Say hi",
        text: '{"title":"Hi"}',
        usage: expect.objectContaining({
          totalTokens: 10,
          generationId: "gen_1",
        }),
      }),
    );
  });

  it("rejects a missing prompt and a used-up quota", async () => {
    const route = createCompletionRoute({
      model: "m",
      run,
      quota: async (organizationId) =>
        organizationId === "org"
          ? dbError("rate_limited", "Out of tokens", { retryAfter: 60 })
          : undefined,
    });

    expect((await route.respond(post({ prompt: " " }), context())).status).toBe(
      400,
    );
    expect((await route.respond(post([]), context())).status).toBe(400);
    const limited = await route.respond(post({ prompt: "x" }), context());
    expect(limited.status).toBe(429);
    expect(limited.headers.get("retry-after")).toBe("60");
  });

  it("maps a failed start to Problem Details", async () => {
    const route = createCompletionRoute({
      model: "m",
      run: () => {
        throw new APICallError({
          message: "nope",
          url: "https://p.test",
          requestBodyValues: {},
          statusCode: 503,
        });
      },
    });

    const response = await route.respond(post({ prompt: "x" }), context());

    expect(response.status).toBe(503);
    expect(await response.json()).toMatchObject({
      code: "AI_PROVIDER_UNAVAILABLE",
    });
  });

  it("aborts the run when the client goes away and skips onFinish without waitUntil", async () => {
    const controller = new AbortController();
    let signal: AbortSignal | undefined;

    const route = createCompletionRoute({
      model: "m",
      feature: "summary",
      onFinish: vi.fn(),
      run: (args) => {
        signal = args.abortSignal;

        return {
          textStream: new ReadableStream<string>({
            start(stream) {
              stream.enqueue("a");
              stream.close();
            },
          }),
        };
      },
    });

    const request = new Request("https://app.test/api/completion", {
      method: "POST",
      body: JSON.stringify({ prompt: "x" }),
      signal: controller.signal,
    });

    const response = await route.respond(request, {
      userId: "u",
      organizationId: "o",
    });

    controller.abort();
    expect(signal?.aborted).toBe(true);
    expect(await response.text()).toBe("a");
  });

  it("reports zero usage when the result's usage fails", async () => {
    const onFinish = vi.fn();

    const route = createCompletionRoute({
      model: "m",
      onFinish,
      run: () => ({
        textStream: new ReadableStream<string>({
          start(stream) {
            stream.close();
          },
        }),
        usage: Promise.reject(new Error("no usage")),
      }),
    });

    const ctx = context();

    await (await route.respond(post({ prompt: "x" }), ctx)).text();
    await Promise.all(ctx.pending);
    expect(onFinish).toHaveBeenCalledWith(
      expect.objectContaining({
        text: "",
        usage: expect.objectContaining({ totalTokens: 0 }),
      }),
    );
  });
});

describe("createObjectRoute", () => {
  it("checks the input against its schema", async () => {
    const route = createObjectRoute({ model: "m", run, input: titleSchema });

    const bad = await route.respond(post({ subject: 1 }), context());
    expect(bad.status).toBe(422);
    expect(await bad.json()).toMatchObject({
      issues: [{ message: "Expected a topic", path: ["topic"] }],
    });

    const good = await route.respond(post({ topic: "cats" }), context());
    expect(good.status).toBe(200);
    expect(await good.text()).toBe('{"title":"Hi"}');
    expect(run.mock.lastCall?.[0]).toMatchObject({
      input: { topic: "cats" },
      providerOptions: { gateway: { tags: ["org:org", "feature:object"] } },
    });
  });

  it("passes the body through without a schema", async () => {
    const route = createObjectRoute({ model: "m", run });
    const response = await route.respond(post({ any: true }), context());

    await response.text();
    expect(run.mock.lastCall?.[0].input).toEqual({ any: true });
  });
});
