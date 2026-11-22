import { describe, expect, it, vi } from "vitest";

import type {
  HarnessRouteAgent,
  HarnessRouteSession,
  SteeringMailbox,
} from "../../../src/ai-sdk/agents/harness.ts";
import type { AiHarnessSessions } from "../../../src/blocks/ai-chat/durable.ts";

import {
  chatSteering,
  harnessRoute,
  harnessStateCipher,
  steerRoute,
} from "../../../src/ai-sdk/agents/harness.ts";
import { dbError } from "../../../src/core/errors.ts";
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

describe("harnessRoute input and failures", () => {
  const cipher = harnessStateCipher([{ id: "k1", key: KEY }]);

  it("answers 400 for a body that is not a chatId and a prompt", async () => {
    const f = fakes();

    const route = harnessRoute({
      agent: f.agent,
      sessions: f.sessions,
      cipher,
      authorize: async () => undefined,
    });

    expect((await route.respond(request([1]), { userId: "u" })).status).toBe(
      400,
    );
    expect(
      (await route.respond(request({ chatId: "c1" }), { userId: "u" })).status,
    ).toBe(400);
    expect(f.calls).toEqual([]);
  });

  it("resumes the next turn from the stored state", async () => {
    const f = fakes();
    const resumed: unknown[] = [];

    const agent: HarnessRouteAgent = {
      ...f.agent,
      createSession: async (input) => {
        resumed.push(input.resumeFrom);

        return f.agent.createSession(input);
      },
    };

    const route = harnessRoute({
      agent,
      sessions: f.sessions,
      cipher,
      authorize: async () => undefined,
      lockTtlSeconds: 60,
    });

    for (const prompt of ["one", "two"]) {
      const pending: Promise<unknown>[] = [];

      await route.respond(request({ chatId: "c1", prompt }), {
        userId: "u",
        waitUntil: (p) => pending.push(p),
      });
      await Promise.all(pending);
    }

    expect(resumed).toEqual([
      undefined,
      { type: "resume-session", secret: "sk-1" },
    ]);
  });

  it("unlocks and answers with the error when the state can't be opened", async () => {
    const f = fakes();
    const pending: Promise<unknown>[] = [];

    const first = harnessRoute({
      agent: f.agent,
      sessions: f.sessions,
      cipher,
      authorize: async () => undefined,
    });

    await first.respond(request({ chatId: "c1", prompt: "one" }), {
      userId: "u",
      waitUntil: (p) => pending.push(p),
    });
    await Promise.all(pending);

    const rotated = harnessRoute({
      agent: f.agent,
      sessions: f.sessions,
      cipher: harnessStateCipher([{ id: "k2", key: OTHER }]),
      authorize: async () => undefined,
    });

    const response = await rotated.respond(
      request({ chatId: "c1", prompt: "two" }),
      { userId: "u" },
    );

    expect(response.status).toBeGreaterThanOrEqual(400);
    expect(f.calls.at(-1)).toBe("unlock");
  });

  it("answers with the error when loading or locking fails", async () => {
    const f = fakes();

    const failing = (sessions: object) =>
      harnessRoute({
        agent: f.agent,
        sessions: { ...f.sessions, ...sessions },
        cipher,
        authorize: async () => undefined,
      }).respond(request({ chatId: "c1", prompt: "hi" }), { userId: "u" });

    const down = () => AsyncResult.err(dbError("network", "down"));

    expect((await failing({ lock: down })).status).toBeGreaterThanOrEqual(500);
    expect(f.calls).toEqual([]);
    expect((await failing({ load: down })).status).toBeGreaterThanOrEqual(500);
    expect(f.calls).toEqual(["unlock"]);
  });

  it("unlocks when the session can't start", async () => {
    const f = fakes();

    const route = harnessRoute({
      agent: {
        ...f.agent,
        createSession: async () => {
          throw new Error("no sandbox");
        },
      },
      sessions: f.sessions,
      cipher,
      authorize: async () => undefined,
    });

    const response = await route.respond(
      request({ chatId: "c1", prompt: "hi" }),
      { userId: "u" },
    );

    expect(response.status).toBeGreaterThanOrEqual(500);
    expect(f.calls).toEqual(["unlock"]);
  });

  it("reports a failed save, a failed poll and a failed steer", async () => {
    const f = fakes();
    const pending: Promise<unknown>[] = [];
    const reported: unknown[] = [];
    let polls = 0;

    const steering: SteeringMailbox = {
      push: async () => ({ ok: true, data: undefined }) as never,
      pending: async () => {
        polls += 1;

        return (
          polls === 1
            ? { ok: false, error: dbError("network", "poll") }
            : {
                ok: true,
                data: [
                  { id: "m2", text: "" },
                  { id: "m3", text: "go" },
                  { id: "m3", text: "go" },
                ],
              }
        ) as never;
      },
    };

    const route = harnessRoute({
      agent: {
        ...f.agent,
        createSession: async () => ({
          sessionId: "s",
          detach: async () => ({}),
          experimental_steerTurn: async () => {
            throw new Error("steer");
          },
        }),
      },
      sessions: {
        ...f.sessions,
        upsert: () => AsyncResult.err(dbError("network", "save")),
      },
      cipher,
      authorize: async () => undefined,
      steering,
      steerPollMs: 5,
      messageId: () => "m1",
      onError: (error) => reported.push(error),
    });

    await route.respond(request({ chatId: "c1", prompt: "hi" }), {
      userId: "u",
      waitUntil: (p) => pending.push(p),
    });
    await Promise.all(pending);

    const messages = reported.map((error) =>
      error instanceof Error
        ? error.message
        : (error as { message: string }).message,
    );

    expect(messages).toContain("poll");
    expect(messages).toContain("steer");
    expect(messages).toContain("save");
    expect(messages.filter((message) => message === "steer")).toHaveLength(1);
  });
});

describe("chatSteering", () => {
  const messages = {
    appendUser: vi.fn(() => AsyncResult.ok({})),
    path: vi.fn(() =>
      AsyncResult.ok([
        { id: "m0", role: "user", parts: [{ type: "text", text: "old" }] },
        { id: "m1", role: "user", parts: [{ type: "text", text: "start" }] },
        { id: "a1", role: "assistant", parts: [{ type: "text", text: "ok" }] },
        {
          id: "m2",
          role: "user",
          parts: [
            { type: "text", text: "use" },
            { type: "file", url: "x" },
            { type: "text", text: "tests" },
          ],
        },
      ]),
    ),
  };

  // SAFETY: the mailbox calls only `appendUser` and `path`.
  const mailbox = chatSteering({ messages } as never);

  it("stores a steering message as a user message on the chat", async () => {
    const pushed = await mailbox.push({
      chatId: "c1",
      messageId: "m2",
      text: "stop",
    });

    expect(pushed.ok).toBe(true);
    expect(messages.appendUser).toHaveBeenCalledWith({
      chatId: "c1",
      message: {
        id: "m2",
        role: "user",
        parts: [{ type: "text", text: "stop" }],
        metadata: { steering: true },
      },
    });

    messages.appendUser.mockReturnValueOnce(
      AsyncResult.err(dbError("forbidden", "no")),
    );

    expect(
      (await mailbox.push({ chatId: "c1", messageId: "m3", text: "x" })).ok,
    ).toBe(false);
  });

  it("reads the user messages after the turn's message", async () => {
    const pending = await mailbox.pending({
      chatId: "c1",
      afterMessageId: "m1",
    });

    expect(pending.ok && pending.data).toEqual([
      { id: "m2", text: "use\ntests" },
    ]);

    const unknown = await mailbox.pending({
      chatId: "c1",
      afterMessageId: "zz",
    });

    expect(unknown.ok && unknown.data).toEqual([]);

    messages.path.mockReturnValueOnce(
      AsyncResult.err(dbError("network", "down")),
    );

    expect(
      (await mailbox.pending({ chatId: "c1", afterMessageId: "m1" })).ok,
    ).toBe(false);
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

  it("answers 400, the refusal or the push error", async () => {
    const steering: SteeringMailbox = {
      push: async () =>
        ({ ok: false, error: dbError("network", "down") }) as never,
      pending: async () => ({ ok: true, data: [] }) as never,
    };

    const open = steerRoute({ authorize: async () => undefined, steering });

    expect((await open.respond(request("x"), { userId: "u" })).status).toBe(
      400,
    );
    expect(
      (
        await open.respond(request({ chatId: "c1", text: "x" }), {
          userId: "u",
        })
      ).status,
    ).toBe(400);

    const body = { chatId: "c1", messageId: "m2", text: "stop" };

    expect(
      (await open.respond(request(body), { userId: "u" })).status,
    ).toBeGreaterThanOrEqual(500);

    const closed = steerRoute({
      authorize: async () => ({
        kind: "forbidden",
        message: "no",
        status: 403,
      }),
      steering,
    });

    expect((await closed.respond(request(body), { userId: "u" })).status).toBe(
      403,
    );
  });
});
