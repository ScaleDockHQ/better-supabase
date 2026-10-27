import { describe, expect, it, vi } from "vitest";

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

    resumeHook.mockRejectedValueOnce(new Error("not found"));
    const headers = await signWebhook(secret, { id: "msg_2", body });

    const missing = await resumeHookFromWebhook({ headers, body }, "tok", {
      provider: "standard-webhooks",
      secrets: secret,
    });

    expect(missing.status).toBe(404);
  });
});
