import { describe, expect, it } from "vitest";

import { badRequest, readJson, sse } from "../../src/ai-sdk/http.ts";

describe("ai-sdk http helpers", () => {
  it("answers a bad request as a problem response", async () => {
    const response = badRequest("Expected the chat id.");
    expect(response.status).toBe(400);
    expect(await response.text()).toContain("AI_CHAT_BAD_REQUEST");
  });

  it("reads JSON and returns undefined for anything else", async () => {
    const good = new Request("https://x.test", {
      method: "POST",
      body: '{"a":1}',
    });
    const bad = new Request("https://x.test", { method: "POST", body: "nope" });
    expect(await readJson(good)).toEqual({ a: 1 });
    expect(await readJson(bad)).toBeUndefined();
  });

  it("streams with the UI message headers plus extra headers", async () => {
    const stream = new ReadableStream<string>({
      start(controller) {
        controller.enqueue("data: 1\n\n");
        controller.close();
      },
    });
    const response = sse(stream, { "x-workflow-run-id": "run1" });
    expect(response.headers.get("x-workflow-run-id")).toBe("run1");
    expect(response.headers.get("content-type")).toContain("text/event-stream");
    expect(await response.text()).toBe("data: 1\n\n");
  });
});
