import { describe, expect, it, vi } from "vitest";
import { HookNotFoundError } from "workflow/errors";

import { signWebhook } from "../../src/core/signatures.ts";

const cancel = vi.fn(async (_options: unknown) => undefined);

const getReadable = vi.fn((_options: unknown) =>
  Object.assign(new ReadableStream<Uint8Array>(), {
    getTailIndex: async () => 7,
  }),
);

const getRun = vi.fn((runId: string) => ({ runId, cancel, getReadable }));
const resumeHook = vi.fn(async (_token: string, _payload: unknown) => ({}));

// SAFETY: the code under test calls only getRun and resumeHook, with the shapes mocked here.
vi.mock(import("workflow/api"), () => ({ getRun, resumeHook }) as never);

const { cancelRuns, resumeHookFromWebhook, resumeStreamResponse } =
  await import("../../src/workflow-sdk/index.ts");

describe("cancelRuns", () => {
  it("cancels each run with the reason and lists the failures", async () => {
    cancel
      .mockResolvedValueOnce(undefined)
      .mockRejectedValueOnce(new Error("gone"))
      .mockResolvedValueOnce(undefined);

    const result = await cancelRuns(["a", "b", "c"], {
      reason: "tenant deleted",
      concurrency: 2,
    });

    expect(result.cancelled).toEqual(["a", "c"]);
    expect(result.failed.map((entry) => entry.runId)).toEqual(["b"]);
    expect(cancel).toHaveBeenCalledWith({ cancelReason: "tenant deleted" });
  });
});

describe("resumeStreamResponse", () => {
  it("reads from the start index and sends the tail index", async () => {
    const response = await resumeStreamResponse("wrun_1", {
      startIndex: 3,
      namespace: "ui",
    });

    expect(getReadable).toHaveBeenCalledWith({
      startIndex: 3,
      namespace: "ui",
    });
    expect(response.headers.get("x-workflow-stream-tail-index")).toBe("7");
  });

  it("answers as server-sent events when asked", async () => {
    const response = await resumeStreamResponse("wrun_1", { sse: true });

    expect(response.headers.get("content-type")).toBe(
      "text/event-stream; charset=utf-8",
    );
    expect(response.headers.get("cache-control")).toBe(
      "no-cache, no-transform",
    );
    expect(response.headers.get("x-accel-buffering")).toBe("no");
  });

  it("pipes the chunks through a transform", async () => {
    getReadable.mockReturnValueOnce(
      Object.assign(
        new ReadableStream<Uint8Array>({
          start(controller) {
            controller.enqueue(new TextEncoder().encode("hi"));
            controller.close();
          },
        }),
        { getTailIndex: async () => 0 },
      ),
    );

    const response = await resumeStreamResponse("wrun_1", {
      transform: new TransformStream<Uint8Array, Uint8Array>({
        transform(chunk, controller) {
          controller.enqueue(
            new TextEncoder().encode(
              `data: ${new TextDecoder().decode(chunk)}\n\n`,
            ),
          );
        },
      }),
      sse: true,
    });

    expect(await response.text()).toBe("data: hi\n\n");
  });

  it("keeps the content type the caller set", async () => {
    const response = await resumeStreamResponse("wrun_1", {
      sse: true,
      headers: { "content-type": "text/plain" },
    });

    expect(response.headers.get("content-type")).toBe("text/plain");
  });
});

describe("resumeHookFromWebhook", () => {
  const secret = `whsec_${btoa("0123456789abcdef0123456789abcdef")}`;

  it("resumes the hook with a verified payload", async () => {
    const body = JSON.stringify({ paid: true });
    const headers = await signWebhook(secret, { id: "msg_1", body });

    const response = await resumeHookFromWebhook({ headers, body }, "tok", {
      provider: "standard-webhooks",
      secrets: secret,
    });

    expect(response.status).toBe(202);
    expect(resumeHook).toHaveBeenCalledWith("tok", { paid: true });
  });

  it("refuses a bad signature and an unknown hook", async () => {
    const body = "{}";

    const bad = await resumeHookFromWebhook(
      {
        headers: {
          "webhook-id": "m",
          "webhook-timestamp": "1",
          "webhook-signature": "v1,x",
        },
        body,
      },
      "tok",
      { provider: "standard-webhooks", secrets: secret },
    );

    expect(bad.status).toBe(401);

    resumeHook.mockRejectedValueOnce(new HookNotFoundError("tok"));
    const headers = await signWebhook(secret, { id: "msg_2", body });

    const missing = await resumeHookFromWebhook({ headers, body }, "tok", {
      provider: "standard-webhooks",
      secrets: secret,
    });

    expect(missing.status).toBe(404);
  });

  it("answers 503 when the World is unreachable and 500 otherwise", async () => {
    const body = "{}";
    const onError = vi.fn();

    const send = async (id: string): Promise<Response> =>
      resumeHookFromWebhook(
        { headers: await signWebhook(secret, { id, body }), body },
        "tok",
        { provider: "standard-webhooks", secrets: secret, onError },
      );

    resumeHook.mockRejectedValueOnce(
      Object.assign(new Error("down"), { code: "ECONNREFUSED" }),
    );

    const unavailable = await send("msg_3");

    expect(unavailable.status).toBe(503);
    expect(await unavailable.json()).toMatchObject({
      code: "WORKFLOW_UNAVAILABLE",
    });

    resumeHook.mockRejectedValueOnce(new Error("boom"));

    const failed = await send("msg_4");

    expect(failed.status).toBe(500);
    expect(await failed.json()).toMatchObject({
      code: "WORKFLOW_RESUME_FAILED",
    });
    expect(onError).toHaveBeenCalledTimes(2);
  });
});
