import { afterEach, describe, expect, it, vi } from "vitest";

import type { SessionStatusBody } from "../../../src/server/session-status.ts";

import { watchSession } from "../../../src/next/client/session-watch.ts";

const body = (
  status: SessionStatusBody["status"],
  fingerprint: string | null = status === "active" ? "f1" : null,
): SessionStatusBody => ({
  status,
  userId: status === "active" ? "u1" : null,
  fingerprint,
  expiresAt: null,
  support: null,
});

function answers(...bodies: SessionStatusBody[]) {
  const queue = [...bodies];

  return vi.fn(async () => Response.json(queue.shift() ?? bodies.at(-1)));
}

const flush = () =>
  new Promise((resolve) => {
    setTimeout(resolve, 0);
  });

describe("watchSession", () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  it("reports nothing while the session holds, then an ended session", async () => {
    const fetch = answers(body("active"), body("active"), body("ended"));
    const onChange = vi.fn();
    const onStatus = vi.fn();

    const watcher = watchSession(onChange, {
      fetch,
      intervalMs: 0,
      channel: false,
      onStatus,
    });

    await flush();
    await watcher.check();
    expect(onChange).not.toHaveBeenCalled();
    await watcher.check();
    expect(onChange).toHaveBeenCalledWith({
      reason: "ended",
      status: body("ended"),
      source: "check",
    });
    expect(onStatus).toHaveBeenCalledTimes(3);
    expect(fetch).toHaveBeenCalledWith(
      "/api/session-status",
      expect.objectContaining({ cache: "no-store" }),
    );
    watcher.stop();
  });

  it("reports a claims change against the rendered fingerprint", async () => {
    const onChange = vi.fn();

    const watcher = watchSession(onChange, {
      fetch: answers(body("active", "f2")),
      fingerprint: "f1",
      intervalMs: 0,
      channel: false,
    });

    await watcher.check();
    expect(onChange).toHaveBeenCalledWith(
      expect.objectContaining({ reason: "claims_changed", source: "check" }),
    );
    watcher.stop();
  });

  it("ignores an expired token, failures and a signed-out start", async () => {
    const onChange = vi.fn();
    let call = 0;

    const fetch = vi.fn(async () => {
      call += 1;

      if (call === 2) {
        throw new Error("offline");
      }

      if (call === 3) {
        return new Response("nope", { status: 500 });
      }

      return Response.json(call === 1 ? body("signed_out") : body("expired"));
    });

    const watcher = watchSession(onChange, {
      fetch,
      intervalMs: 0,
      channel: false,
    });

    await flush();

    for (let i = 0; i < 3; i += 1) {
      await watcher.check();
    }

    expect(fetch).toHaveBeenCalledTimes(4);
    expect(onChange).not.toHaveBeenCalled();
    watcher.stop();
  });

  it("checks on an interval and tells the other tabs", async () => {
    vi.useFakeTimers();
    const name = `bsb-test-${crypto.randomUUID()}`;
    const other = new BroadcastChannel(name);
    const heard = vi.fn();
    other.addEventListener("message", (event) => heard(event.data));
    const onChange = vi.fn();

    const watcher = watchSession(onChange, {
      fetch: answers(body("active"), body("banned")),
      intervalMs: 1000,
      channel: name,
    });

    await vi.advanceTimersByTimeAsync(1000);
    expect(onChange).toHaveBeenCalledWith(
      expect.objectContaining({ reason: "banned" }),
    );
    vi.useRealTimers();
    await new Promise((resolve) => {
      setTimeout(resolve, 20);
    });
    expect(heard).toHaveBeenCalledWith({
      type: "better-supabase:session",
      reason: "banned",
      fingerprint: null,
    });

    const tab = vi.fn();

    const second = watchSession(tab, {
      fetch: answers(body("active")),
      intervalMs: 0,
      channel: name,
    });

    const signedOut = {
      type: "better-supabase:session",
      reason: "signed_out",
      fingerprint: null,
    };

    // oxlint-disable-next-line unicorn/require-post-message-target-origin -- BroadcastChannel.postMessage takes no target origin (2 findings).
    other.postMessage(signedOut);
    // oxlint-disable-next-line unicorn/require-post-message-target-origin -- BroadcastChannel.postMessage takes no target origin (2 findings).
    other.postMessage({ type: "other" });
    await new Promise((resolve) => {
      setTimeout(resolve, 20);
    });
    expect(tab).toHaveBeenCalledExactlyOnceWith({
      reason: "signed_out",
      status: null,
      source: "tab",
    });
    watcher.stop();
    second.stop();
    other.close();
  });
});

describe("watchSession in a browser", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("checks on focus and when the page becomes visible, never while hidden", async () => {
    const win = new EventTarget();
    const doc = Object.assign(new EventTarget(), { visibilityState: "hidden" });
    vi.stubGlobal("window", win);
    vi.stubGlobal("document", doc);

    const fetch = answers(body("active"), body("active"), body("signed_out"));
    const onChange = vi.fn();

    const watcher = watchSession(onChange, {
      fetch,
      intervalMs: 0,
      channel: false,
    });

    await flush();
    expect(fetch).toHaveBeenCalledOnce();

    win.dispatchEvent(new Event("focus"));
    await flush();
    expect(fetch).toHaveBeenCalledOnce();

    doc.visibilityState = "visible";
    doc.dispatchEvent(new Event("visibilitychange"));
    await flush();
    expect(fetch).toHaveBeenCalledTimes(2);

    win.dispatchEvent(new Event("focus"));
    await flush();
    expect(onChange).toHaveBeenCalledWith(
      expect.objectContaining({ reason: "signed_out", source: "check" }),
    );

    watcher.stop();
    watcher.stop();
    win.dispatchEvent(new Event("focus"));
    await flush();
    expect(fetch).toHaveBeenCalledTimes(3);
  });

  it("reuses a running check and drops answers after stop or of the wrong shape", async () => {
    let release: (response: Response) => void = () => undefined;

    const fetch = vi.fn(
      () =>
        new Promise<Response>((resolve) => {
          release = resolve;
        }),
    );

    const onStatus = vi.fn();

    const watcher = watchSession(vi.fn(), {
      fetch,
      intervalMs: 0,
      channel: false,
      onStatus,
    });

    const first = watcher.check();
    expect(watcher.check()).toBe(first);
    watcher.stop();
    release(Response.json(body("active")));
    expect(await first).toBeUndefined();

    const malformed = [
      null,
      { status: 1 },
      { status: "active", fingerprint: 2 },
    ];

    const odd = watchSession(vi.fn(), {
      fetch: async () => Response.json(malformed.shift() ?? null),
      intervalMs: 0,
      channel: false,
      onStatus,
    });

    await flush();
    expect(await odd.check()).toBeUndefined();
    expect(await odd.check()).toBeUndefined();
    expect(onStatus).not.toHaveBeenCalled();
    odd.stop();
  });

  it("uses the default route, fetch and channel and ignores other tab messages", async () => {
    const fetch = vi.fn(async () => Response.json(body("active")));
    vi.stubGlobal("fetch", fetch);

    const other = new BroadcastChannel("better-supabase:session");
    const onChange = vi.fn();
    const watcher = watchSession(onChange);

    await flush();
    expect(fetch).toHaveBeenCalledWith(
      "/api/session-status",
      expect.objectContaining({ method: "GET" }),
    );

    const ignored = [
      null,
      { type: "better-supabase:session", reason: "nope", fingerprint: null },
      {
        type: "better-supabase:session",
        reason: "claims_changed",
        fingerprint: 3,
      },
    ];

    for (const message of ignored) {
      // oxlint-disable-next-line unicorn/require-post-message-target-origin -- BroadcastChannel.postMessage takes no target origin (1 finding).
      other.postMessage(message);
    }

    await new Promise((resolve) => {
      setTimeout(resolve, 20);
    });
    expect(onChange).not.toHaveBeenCalled();

    watcher.stop();
    other.close();
  });
});
