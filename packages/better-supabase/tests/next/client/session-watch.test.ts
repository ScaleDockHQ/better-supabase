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
