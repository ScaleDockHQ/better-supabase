import { describe, expect, it } from "vitest";

import type {
  HarnessRouteAgent,
  HarnessRouteSession,
  SteeringMailbox,
} from "../../../src/ai-sdk/agents/harness.ts";
import type { AiHarnessSessions } from "../../../src/blocks/ai-chat/durable.ts";

import {
  harnessRoute,
  harnessStateCipher,
  steerRoute,
} from "../../../src/ai-sdk/agents/harness.ts";
import { AsyncResult } from "../../../src/core/result.ts";

const KEY = btoa(String.fromCodePoint(...new Uint8Array(32).fill(7)));
const OTHER = btoa(String.fromCodePoint(...new Uint8Array(32).fill(9)));
const binding = { chatId: "c1", harnessId: "claude" };

describe("harnessStateCipher", () => {
  it("round-trips and never stores the plain state", async () => {
    const cipher = harnessStateCipher([{ id: "k1", key: KEY }]);
    const sealed = await cipher.seal({ token: "sk-secret" }, binding);

    expect(JSON.stringify(sealed)).not.toContain("sk-secret");

    const opened = await cipher.open(sealed, binding);

    expect(opened.ok && opened.data).toEqual({ token: "sk-secret" });
  });

  it("refuses a value moved to another chat", async () => {
    const cipher = harnessStateCipher([{ id: "k1", key: KEY }]);
    const sealed = await cipher.seal({ a: 1 }, binding);

    expect((await cipher.open(sealed, { ...binding, chatId: "c2" })).ok).toBe(
      false,
    );
  });

  it("opens with an old key after a rotation, and rejects plain state", async () => {
    const old = harnessStateCipher([{ id: "k1", key: KEY }]);
    const sealed = await old.seal({ a: 1 }, binding);

    const rotated = harnessStateCipher([
      { id: "k2", key: OTHER },
      { id: "k1", key: KEY },
    ]);

    expect((await rotated.open(sealed, binding)).ok).toBe(true);
    expect((await rotated.open({ plain: true }, binding)).ok).toBe(false);

    const dropped = harnessStateCipher([{ id: "k2", key: OTHER }]);

    expect((await dropped.open(sealed, binding)).ok).toBe(false);
  });
});

function fakes(lockResult = true) {
  const calls: string[] = [];
  let stored: unknown;
  const steered: string[] = [];

  const sessions = {
    load: () =>
      AsyncResult.ok(
        stored === undefined ? undefined : { resumeState: stored },
      ),
    lock: () => AsyncResult.ok(lockResult),
    unlock: () => {
      calls.push("unlock");

      return AsyncResult.ok(true);
    },
    upsert: ({ patch }: { patch: { resumeState?: unknown } }) => {
      stored = patch.resumeState;
      calls.push("upsert");

      return AsyncResult.ok({});
    },
  } as unknown as AiHarnessSessions;

  const session: HarnessRouteSession = {
    sessionId: "s",
    detach: async () => ({ type: "resume-session", secret: "sk-1" }),
    experimental_steerTurn: async (text) => {
      steered.push(text);
    },
  };

  const agent: HarnessRouteAgent = {
    harnessId: "claude",
    createSession: async () => session,
    stream: async () => ({
      toUIMessageStreamResponse: () => new Response("ok"),
      finishReason: new Promise((resolve) => {
        setTimeout(resolve, 30);
      }),
    }),
  };

  return { sessions, agent, calls, steered, stored: () => stored };
}

const request = (body: unknown) =>
  new Request("https://x.test/turn", {
    method: "POST",
    body: JSON.stringify(body),
  });

describe("harnessRoute", () => {
  it("stores the detached state encrypted and unlocks", async () => {
    const f = fakes();
    const pending: Promise<unknown>[] = [];

    const route = harnessRoute({
      agent: f.agent,
      sessions: f.sessions,
      cipher: harnessStateCipher([{ id: "k1", key: KEY }]),
      authorize: async () => undefined,
    });

    const response = await route.respond(
      request({ chatId: "c1", prompt: "hi" }),
      { userId: "u", waitUntil: (p) => pending.push(p) },
    );

    expect(response.status).toBe(200);
    await Promise.all(pending);

    expect(f.calls).toEqual(["upsert", "unlock"]);
    expect(JSON.stringify(f.stored())).not.toContain("sk-1");
  });

  it("answers 409 for a chat with a turn in progress", async () => {
    const f = fakes(false);

    const route = harnessRoute({
      agent: f.agent,
      sessions: f.sessions,
      cipher: harnessStateCipher([{ id: "k1", key: KEY }]),
      authorize: async () => undefined,
    });

    const response = await route.respond(
      request({ chatId: "c1", prompt: "hi" }),
      { userId: "u" },
    );

    expect(response.status).toBe(409);
  });

  it("does not start for a caller the access check refuses", async () => {
    const f = fakes();

    const route = harnessRoute({
      agent: f.agent,
      sessions: f.sessions,
      cipher: harnessStateCipher([{ id: "k1", key: KEY }]),
      authorize: async () => ({
        kind: "forbidden",
        message: "no",
        status: 403,
      }),
    });

    const response = await route.respond(
      request({ chatId: "c1", prompt: "hi" }),
      { userId: "u" },
    );

    expect(response.status).toBe(403);
    expect(f.calls).toEqual([]);
  });

  it("feeds messages sent during the turn to the running session", async () => {
    const f = fakes();
    const pending: Promise<unknown>[] = [];

    const steering: SteeringMailbox = {
      push: async () => ({ ok: true, data: undefined }) as never,
      pending: async () =>
        ({ ok: true, data: [{ id: "m2", text: "use tests" }] }) as never,
    };

    const route = harnessRoute({
      agent: f.agent,
      sessions: f.sessions,
      cipher: harnessStateCipher([{ id: "k1", key: KEY }]),
      authorize: async () => undefined,
      steering,
      steerPollMs: 5,
    });

    await route.respond(
      request({ chatId: "c1", prompt: "hi", messageId: "m1" }),
      { userId: "u", waitUntil: (p) => pending.push(p) },
    );
    await Promise.all(pending);

    expect(f.steered).toEqual(["use tests"]);
  });
});

describe("steerRoute", () => {
  it("pushes the message and answers 202", async () => {
    const pushed: unknown[] = [];

    const route = steerRoute({
      authorize: async () => undefined,
      steering: {
        push: async (input) => {
          pushed.push(input);

          return { ok: true, data: undefined } as never;
        },
        pending: async () => ({ ok: true, data: [] }) as never,
      },
    });

    const response = await route.respond(
      request({ chatId: "c1", messageId: "m2", text: "stop" }),
      { userId: "u" },
    );

    expect(response.status).toBe(202);
    expect(pushed).toEqual([{ chatId: "c1", messageId: "m2", text: "stop" }]);
  });
});
