import type { SupabaseClient } from "@supabase/supabase-js";

import { describe, expect, it, vi } from "vitest";

import type { SubscriptionStatus } from "../../src/realtime/index.ts";

import { watchTopic } from "../../src/blocks/react-topic.ts";
import { defineTopic } from "../../src/realtime/index.ts";

type Listener = (message: { event: string; payload: unknown }) => void;

interface FakeChannel {
  readonly topic: string;
  readonly listeners: Set<Listener>;
  status?: (state: string) => void;
  joined: boolean;
}

/**
 * A realtime-js stand-in that keeps its rules: `channel()` returns the open
 * channel for a topic, a channel subscribes once, and a removed channel
 * leaves the list only after the server acknowledges the leave.
 */
function fakeRealtime() {
  const open: FakeChannel[] = [];
  const subscribe = vi.fn();
  const client = {
    channel: vi.fn((name: string, _options?: unknown) => {
      const topic = `realtime:${name}`;
      const entry: FakeChannel = open.find((each) => each.topic === topic) ?? {
        topic,
        listeners: new Set(),
        joined: false,
      };
      if (!open.includes(entry)) open.push(entry);
      const channel = {
        topic,
        on: (_type: string, _filter: unknown, listener: Listener) => {
          entry.listeners.add(listener);
          return channel;
        },
        subscribe: (callback: (state: string) => void) => {
          if (entry.joined)
            throw new Error("tried to subscribe multiple times");
          entry.joined = true;
          entry.status = callback;
          subscribe(name);
          queueMicrotask(() => {
            callback("SUBSCRIBED");
          });
          return channel;
        },
        entry,
      };
      return channel;
    }),
    getChannels: () => open,
    removeChannel: vi.fn(async (channel: { entry: FakeChannel }) => {
      await new Promise((resolve) => {
        setTimeout(resolve, 5);
      });
      open.splice(open.indexOf(channel.entry), 1);
      return "ok" as const;
    }),
    realtime: { setAuth: vi.fn(async () => undefined) },
  };
  const emit = (name: string, event: string, payload: unknown = {}) => {
    const entry = open.find((each) => each.topic === `realtime:${name}`);
    for (const listener of entry?.listeners ?? []) listener({ event, payload });
  };
  const status = (name: string, state: string) => {
    open.find((each) => each.topic === `realtime:${name}`)?.status?.(state);
  };
  // SAFETY: the fake implements the members watchTopic and joinTopic call.
  const supabase = client as unknown as SupabaseClient;
  return { client, supabase, subscribe, emit, status };
}

function watcher() {
  const statuses: SubscriptionStatus[] = [];
  const watch = {
    onMessage: vi.fn(),
    onRejoin: vi.fn(),
    onStatus: (next: SubscriptionStatus) => {
      statuses.push(next);
    },
  };
  return { watch, statuses, last: () => statuses.at(-1) };
}

const flush = () =>
  new Promise((resolve) => {
    setTimeout(resolve, 0);
  });
const settle = () =>
  new Promise((resolve) => {
    setTimeout(resolve, 20);
  });

describe("watchTopic", () => {
  it("shares one channel between two watchers of a topic", async () => {
    const realtime = fakeRealtime();
    const first = watcher();
    const second = watcher();
    const leaveFirst = watchTopic(realtime.supabase, "chat:c1", first.watch);
    const leaveSecond = watchTopic(realtime.supabase, "chat:c1", second.watch);
    await flush();
    expect(realtime.client.channel).toHaveBeenCalledTimes(1);
    expect(realtime.client.channel).toHaveBeenCalledWith("chat:c1", {
      config: { private: true, broadcast: { self: false } },
    });
    expect(realtime.client.realtime.setAuth).toHaveBeenCalledTimes(1);
    expect(realtime.subscribe).toHaveBeenCalledTimes(1);
    expect(first.last()).toBe("subscribed");
    expect(second.last()).toBe("subscribed");

    realtime.emit("chat:c1", "message.saved", { id: "m1" });
    expect(first.watch.onMessage).toHaveBeenCalledWith("message.saved", {
      id: "m1",
    });
    expect(second.watch.onMessage).toHaveBeenCalledWith("message.saved", {
      id: "m1",
    });
    leaveFirst();
    leaveSecond();
  });

  it("keeps the channel for the other watcher when one leaves", async () => {
    const realtime = fakeRealtime();
    const first = watcher();
    const second = watcher();
    const leaveFirst = watchTopic(realtime.supabase, "chat:c1", first.watch);
    const leaveSecond = watchTopic(realtime.supabase, "chat:c1", second.watch);
    await flush();

    leaveFirst();
    leaveFirst();
    expect(first.last()).toBe("closed");
    await settle();
    expect(realtime.client.removeChannel).not.toHaveBeenCalled();
    expect(second.last()).toBe("subscribed");
    realtime.emit("chat:c1", "leaf.changed");
    expect(first.watch.onMessage).not.toHaveBeenCalled();
    expect(second.watch.onMessage).toHaveBeenCalledTimes(1);

    leaveSecond();
    await flush();
    expect(realtime.client.removeChannel).toHaveBeenCalledTimes(1);
    expect(second.last()).toBe("closed");
  });

  it("survives a StrictMode remount in the same commit", async () => {
    const realtime = fakeRealtime();
    const mounted = watcher();
    // StrictMode runs the effect, its cleanup and the effect again.
    watchTopic(realtime.supabase, "chat:c1", mounted.watch)();
    const leave = watchTopic(realtime.supabase, "chat:c1", mounted.watch);
    await settle();
    expect(realtime.client.removeChannel).not.toHaveBeenCalled();
    expect(realtime.subscribe).toHaveBeenCalledTimes(1);
    expect(mounted.last()).toBe("subscribed");
    realtime.emit("chat:c1", "message.saved");
    expect(mounted.watch.onMessage).toHaveBeenCalledTimes(1);
    leave();
    await flush();
    expect(realtime.client.removeChannel).toHaveBeenCalledTimes(1);
  });

  it("joins again after the last watcher left", async () => {
    const realtime = fakeRealtime();
    watchTopic(realtime.supabase, "chat:c1", watcher().watch)();
    await settle();
    expect(realtime.client.removeChannel).toHaveBeenCalledTimes(1);
    const next = watcher();
    const leave = watchTopic(realtime.supabase, "chat:c1", next.watch);
    await flush();
    expect(next.last()).toBe("subscribed");
    leave();
  });

  it("reports rejoins to each watcher, but not the first join", async () => {
    const realtime = fakeRealtime();
    const first = watcher();
    const leaveFirst = watchTopic(realtime.supabase, "chat:c1", first.watch);
    await flush();
    const late = watcher();
    const leaveLate = watchTopic(realtime.supabase, "chat:c1", late.watch);
    expect(late.statuses).toEqual(["joining", "subscribed"]);
    expect(first.watch.onRejoin).not.toHaveBeenCalled();

    realtime.status("chat:c1", "CHANNEL_ERROR");
    expect(first.last()).toBe("error");
    expect(late.last()).toBe("error");
    realtime.status("chat:c1", "SUBSCRIBED");
    expect(first.watch.onRejoin).toHaveBeenCalledTimes(1);
    expect(late.watch.onRejoin).toHaveBeenCalledTimes(1);
    leaveFirst();
    leaveLate();
  });

  it("reports an error when the topic is joined with other settings", async () => {
    const realtime = fakeRealtime();
    const room = defineTopic("chat:{id}");
    const subscription = room.subscribe(
      realtime.supabase,
      { id: "c1" },
      {},
      { self: true },
    );
    const conflicting = watcher();
    const leave = watchTopic(realtime.supabase, "chat:c1", conflicting.watch);
    expect(conflicting.statuses).toEqual(["error"]);
    leave();
    await subscription.unsubscribe();
  });
});
