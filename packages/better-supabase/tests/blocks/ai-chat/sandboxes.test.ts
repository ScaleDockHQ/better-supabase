import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../../src/core/block-transport.ts";

import { createAiChat } from "../../../src/blocks/ai-chat/index.ts";

const AT = "2026-01-01T00:00:00Z";
const job = undefined as never;
const signal = new AbortController().signal;

const sandboxRow = (overrides: Record<string, unknown> = {}) => ({
  id: "s1",
  organization_id: "o1",
  user_id: null,
  chat_id: "c1",
  harness_id: null,
  provider: "vercel",
  sandbox_id: "sbx_1",
  container_id: null,
  status: "running",
  metadata: {},
  idle_seconds: 600,
  error: null,
  last_used_at: AT,
  expires_at: null,
  stopped_at: null,
  created_at: AT,
  ...overrides,
});

type Handler = (args: Record<string, unknown>) => unknown;

function fakeTransport(handlers: Record<string, Handler>) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const transport: BlockTransport = {
    call: (_schema, fn, args) => {
      calls.push({ fn, args });
      const handler = handlers[fn];
      if (!handler) return Promise.reject(new Error(`unexpected ${fn}`));
      return Promise.resolve(handler(args));
    },
  };
  return { transport, calls };
}

describe("createAiChat sandboxes", () => {
  it("registers, touches, finds and lists sandboxes", async () => {
    const { transport, calls } = fakeTransport({
      register_ai_sandbox: () => sandboxRow(),
      touch_ai_sandbox: () => true,
      ai_sandbox_for: (args) =>
        args["chat_id"] === "c1" ? sandboxRow({ status: "bogus" }) : null,
      list_ai_sandboxes: () => [
        sandboxRow({ stopped_at: AT, status: "stopped" }),
      ],
    });
    const { sandboxes } = createAiChat({ transport });
    await sandboxes
      .register("o1", {
        provider: "vercel",
        sandboxId: "sbx_1",
        userId: "u1",
        chatId: "c1",
        harnessId: "claude-code",
        containerId: "ctr",
        metadata: { runtime: "node24" },
        idleSeconds: 299.6,
        expiresAt: Temporal.Instant.from(AT),
      })
      .orThrow();
    expect(calls[0]?.args).toEqual({
      tenant: "o1",
      provider: "vercel",
      sandbox_id: "sbx_1",
      fields: {
        user_id: "u1",
        chat_id: "c1",
        harness_id: "claude-code",
        container_id: "ctr",
        metadata: { runtime: "node24" },
        idle_seconds: 300,
        expires_at: AT,
      },
    });
    await sandboxes
      .register("o1", { provider: "vercel", sandboxId: "sbx_2" })
      .orThrow();
    expect(calls[1]?.args["fields"]).toEqual({});
    expect(await sandboxes.touch("s1").orThrow()).toBe(true);
    expect((await sandboxes.forChat("c1", "vercel").orThrow())?.status).toBe(
      "stopped",
    );
    expect(await sandboxes.forChat("c2", "vercel").orThrow()).toBeUndefined();
    const listed = await sandboxes.list("o1", { chatId: "c1" }).orThrow();
    expect(listed[0]?.stoppedAt?.toString()).toBe(AT);
    expect(listed[0]?.harnessId).toBeUndefined();
  });

  it("stops idle sandboxes and records failures", async () => {
    const finished: unknown[] = [];
    const { transport } = fakeTransport({
      idle_ai_sandboxes: () => [
        sandboxRow(),
        sandboxRow({ id: "s2", sandbox_id: "sbx_2" }),
      ],
      finish_ai_sandbox_stop: (args) => {
        finished.push(args);
        return true;
      },
    });
    const { sandboxes } = createAiChat({ transport });
    const stopped = await sandboxes.idleStopJob(async (sandbox) => {
      if (sandbox.id === "s2") throw new Error("busy");
    })(undefined, job, signal);
    expect(stopped).toBe(1);
    expect(finished).toEqual([
      { id: "s1", stopped: true, error: undefined },
      { id: "s2", stopped: false, error: "busy" },
    ]);
  });

  it("stops when recording a stop fails", async () => {
    const { transport } = fakeTransport({
      idle_ai_sandboxes: () => [sandboxRow()],
      finish_ai_sandbox_stop: () => Promise.reject(new Error("db down")),
    });
    const result = await createAiChat({ transport }).sandboxes.stopIdle(
      async () => {},
    );
    expect(result.ok).toBe(false);
  });
});
