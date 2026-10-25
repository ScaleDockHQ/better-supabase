import { describe, expect, it, vi } from "vitest";

import type { AuthState } from "../../src/auth/resolve.ts";
import type { SchemaMeta } from "../../src/schema/types.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { liveQuery } from "../../src/realtime/live.ts";
import {
  relayRealtimeClient,
  relayTopicPort,
} from "../../src/realtime/relay.ts";
import { defineSchema } from "../../src/schema/define.ts";
import {
  liveRelayTopic,
  realtimeRelay,
} from "../../src/server/realtime-relay.ts";
import { fakeUpstream, inProcessEventSource } from "../fixtures/fake-relay.ts";
import { schema } from "../fixtures/generated-camel.ts";

const meta: SchemaMeta = { ...schema.meta, realtime: { notes: {} } };

const betterSupabase = defineSupabase(defineSchema(meta));

const caller: AuthState = {
  kind: "user",
  token: "t",
  // SAFETY: the relay reads plain claims.
  claims: { sub: "u1", role: "authenticated" },
  // SAFETY: only `id` is read.
  user: { id: "u1" },
  source: "cookie",
  expiresAt: null,
};

function relayFor(
  upstream: ReturnType<typeof fakeUpstream>,
  options: { readonly maxDurationMs?: number } = {},
) {
  return realtimeRelay(
    {
      context: async () => ({
        auth: caller,
        resolution: { auth: caller },
        apply: (response) => response,
      }),
      admin: () => ({ $client: upstream.client }),
    },
    { topics: [liveRelayTopic], authorize: () => true, ...options },
  );
}

const tick = (ms = 5) =>
  new Promise((resolve) => {
    setTimeout(resolve, ms);
  });

describe("relayRealtimeClient", () => {
  it("runs live queries through the relay and refetches after a reconnect", async () => {
    const upstream = fakeUpstream();
    const relay = relayFor(upstream, { maxDurationMs: 60 });
    const { EventSource, sources } = inProcessEventSource(relay.GET);
    const client = relayRealtimeClient("/api/realtime?app=1", { EventSource });
    const onChange = vi.fn();
    const statuses: string[] = [];

    const live = liveQuery(betterSupabase, client, ["notes"], {
      onChange,
      onStatus: (status) => statuses.push(status),
      debounceMs: 0,
    });

    await live.ready;
    expect(sources).toHaveLength(1);
    expect((sources[0] as unknown as { url: string }).url).toBe(
      "/api/realtime?app=1&topic=bsb%3At%3Apublic.notes",
    );

    upstream.emit("bsb:t:public.notes", "change");
    await tick(20);
    expect(onChange).toHaveBeenCalledWith(["notes"]);

    onChange.mockClear();
    await tick(120);
    expect(onChange).toHaveBeenCalledWith(["notes"]);
    expect(statuses).not.toContain("error");

    await live.unsubscribe();
    await tick(10);
    expect(client.getChannels()).toEqual([]);
  });

  it("joins once a refused upstream recovers", async () => {
    vi.useFakeTimers();

    try {
      const upstream = fakeUpstream();
      upstream.refuse(true);
      const relay = relayFor(upstream);
      const { EventSource, sources } = inProcessEventSource(relay.GET);
      const client = relayRealtimeClient("/rt", { EventSource });
      const statuses: string[] = [];

      client
        .channel("bsb:t:public.notes")
        .subscribe((status) => statuses.push(status));

      await vi.advanceTimersByTimeAsync(10);
      expect(statuses).toEqual(["CHANNEL_ERROR"]);
      expect(sources).toHaveLength(1);

      upstream.refuse(false);
      await vi.advanceTimersByTimeAsync(1000);
      expect(sources).toHaveLength(2);
      expect(statuses).toEqual(["CHANNEL_ERROR", "SUBSCRIBED"]);

      await client.removeChannel(client.getChannels()[0]!);
    } finally {
      vi.useRealTimers();
    }
  });

  it("reports a rejoin to a topic port and broadcasts through POST", async () => {
    const posted: unknown[] = [];

    const sources: {
      listeners: Map<string, (event: { data?: unknown }) => void>;
    }[] = [];

    class ScriptedSource {
      readyState = 1;
      readonly listeners = new Map<
        string,
        (event: { data?: unknown }) => void
      >();

      constructor() {
        sources.push(this);
      }

      addEventListener(
        type: string,
        listener: (event: { data?: unknown }) => void,
      ) {
        this.listeners.set(type, listener);
      }

      close() {
        this.readyState = 2;
      }
    }

    const port = relayTopicPort("/rt", {
      EventSource: ScriptedSource,
      fetch: async (_url, init) => {
        posted.push(JSON.parse(String(init?.body)));

        return new Response(null, { status: 202 });
      },
    });

    const onMessage = vi.fn();
    const onRejoin = vi.fn();
    const statuses: string[] = [];

    const handle = port("doc:1", {
      onMessage,
      onRejoin,
      onStatus: (status) => statuses.push(status),
    });

    await tick();

    const fire = (type: string, data?: unknown) =>
      sources[0]?.listeners.get(type)?.(
        data === undefined ? {} : { data: JSON.stringify(data) },
      );

    fire("status", { status: "subscribed" });
    fire("broadcast", { event: "edit", payload: { n: 1 } });
    fire("broadcast", "not json");
    fire("end", { reason: "max_duration" });
    fire("error");
    fire("status", { status: "subscribed", rejoin: true });

    expect(onMessage).toHaveBeenCalledExactlyOnceWith("edit", { n: 1 });
    expect(onRejoin).toHaveBeenCalledOnce();
    expect(statuses).toEqual(["joining", "subscribed", "subscribed"]);

    handle.send("edit", { n: 2 });
    await tick();
    expect(posted).toEqual([
      { topic: "doc:1", event: "edit", payload: { n: 2 } },
    ]);

    handle.leave();
    await tick();
    expect(statuses.at(-1)).toBe("closed");
  });

  it("reconnects with backoff after the relay closes a joined stream", async () => {
    vi.useFakeTimers();

    const sources: ScriptedClosing[] = [];

    class ScriptedClosing {
      readyState = 1;
      readonly listeners = new Map<
        string,
        (event: { data?: unknown }) => void
      >();

      constructor() {
        sources.push(this);
      }

      addEventListener(
        type: string,
        listener: (event: { data?: unknown }) => void,
      ) {
        this.listeners.set(type, listener);
      }

      close() {
        this.readyState = 2;
      }
    }

    try {
      const client = relayRealtimeClient("/rt", {
        EventSource: ScriptedClosing,
      });

      const statuses: string[] = [];
      const channel = client.channel("doc:1");
      channel.subscribe((status) => statuses.push(status));

      sources[0]?.listeners.get("status")?.({
        data: JSON.stringify({ status: "subscribed" }),
      });
      sources[0]!.readyState = 2;
      sources[0]?.listeners.get("error")?.({});
      await vi.advanceTimersByTimeAsync(0);
      expect(statuses).toEqual(["SUBSCRIBED", "CHANNEL_ERROR"]);

      await vi.advanceTimersByTimeAsync(1000);
      expect(sources).toHaveLength(2);

      await client.removeChannel(channel);
      expect(sources[1]?.readyState).toBe(2);
    } finally {
      vi.useRealTimers();
    }
  });

  it("times out a join that never answers", async () => {
    vi.useFakeTimers();

    class Silent {
      readyState = 0;
      addEventListener() {}
      close() {
        this.readyState = 2;
      }
    }

    try {
      const client = relayRealtimeClient("/rt", {
        EventSource: Silent,
        timeoutMs: 100,
      });

      const statuses: string[] = [];
      client.channel("doc:1").subscribe((status) => statuses.push(status));
      await vi.advanceTimersByTimeAsync(100);
      expect(statuses).toEqual(["TIMED_OUT"]);
    } finally {
      vi.useRealTimers();
    }
  });
});

describe("relayRealtimeClient channels", () => {
  class Scripted {
    static made: Scripted[] = [];
    readyState = 1;
    readonly url: string;
    readonly init: unknown;
    readonly listeners = new Map<string, (event: { data?: unknown }) => void>();

    constructor(url: string, init?: unknown) {
      this.url = url;
      this.init = init;
      Scripted.made.push(this);
    }

    addEventListener(
      type: string,
      listener: (event: { data?: unknown }) => void,
    ) {
      this.listeners.set(type, listener);
    }

    close() {
      this.readyState = 2;
    }

    fire(type: string, data?: unknown) {
      this.listeners.get(type)?.(
        data === undefined
          ? {}
          : { data: typeof data === "string" ? data : JSON.stringify(data) },
      );
    }
  }

  const fresh = () => {
    Scripted.made = [];

    return Scripted;
  };

  it("parses broadcasts, presence and statuses and skips malformed frames", () => {
    const client = relayRealtimeClient("/rt", { EventSource: fresh() });
    const channel = client.channel("room:1");
    const statuses: [string, string | undefined][] = [];
    const broadcasts = vi.fn();
    const named = vi.fn();
    const presence = vi.fn();

    channel.on("broadcast", { event: "*" }, broadcasts);
    channel.on("broadcast", { event: "edit" }, named);
    channel.on("presence", { event: "sync" }, presence);
    channel.subscribe((status, error) =>
      statuses.push([status, error?.message]),
    );

    const [source] = Scripted.made;
    expect(source?.url).toBe("/rt?topic=room%3A1");
    expect(source?.init).toEqual({ withCredentials: true });
    expect(client.channel("room:1")).toBe(channel);

    source?.listeners.get("status")?.({});
    source?.fire("status", "{broken");
    source?.fire("status", { status: "joining" });
    source?.fire("status", { status: "subscribed" });
    source?.fire("status", { status: "error" });
    source?.fire("broadcast", { event: 1 });
    source?.fire("broadcast", { event: "move", payload: 1 });
    source?.fire("broadcast", { event: "edit", payload: 2 });
    source?.fire("presence", [1]);
    source?.fire("presence", { k1: [{ name: "Ann" }], bad: "x" });

    expect(statuses).toEqual([
      ["SUBSCRIBED", undefined],
      ["CHANNEL_ERROR", "Realtime error on room:1"],
    ]);
    expect(broadcasts).toHaveBeenCalledTimes(2);
    expect(named).toHaveBeenCalledExactlyOnceWith({
      type: "broadcast",
      event: "edit",
      payload: 2,
    });
    expect(presence).toHaveBeenCalledOnce();
    expect(channel.presenceState()).toEqual({ k1: [{ name: "Ann" }] });
    expect(() => channel.subscribe()).toThrow(
      "tried to subscribe multiple times to room:1 on the relay",
    );
  });

  it("reports a dropped connection, a refusal and ignores stale sources", async () => {
    const client = relayRealtimeClient("/rt", { EventSource: fresh() });

    const statuses: string[] = [];
    const joined = client.channel("room:1");
    joined.subscribe((status, error) =>
      statuses.push(`${status}:${error?.message ?? ""}`),
    );

    const [first] = Scripted.made;
    first?.fire("status", { status: "subscribed" });
    first!.readyState = 0;
    first?.fire("error");
    first?.fire("end", { reason: "max_duration" });
    first?.fire("error");

    expect(statuses).toEqual([
      "SUBSCRIBED:",
      "CHANNEL_ERROR:The relay connection for room:1 dropped",
    ]);

    const refused: string[] = [];
    const other = client.channel("room:2");
    other.subscribe((status, error) =>
      refused.push(`${status}:${error?.message ?? ""}`),
    );
    const second = Scripted.made[1];
    second!.readyState = 0;
    second?.fire("error");
    second!.readyState = 2;
    second?.fire("error");
    second?.fire("error");
    second?.fire("status", { status: "subscribed" });

    expect(refused).toEqual([
      "CHANNEL_ERROR:The relay could not join room:2; retrying",
    ]);

    await client.removeChannel(joined);
    first?.fire("error");
    expect(statuses).toHaveLength(2);
    await client.removeChannel(joined);
    expect(() => joined.subscribe()).toThrow("tried to subscribe");
    expect(client.getChannels()).toEqual([other]);
    await client.removeChannel(other);
  });

  it("backs off up to the cap and stops reconnecting once removed", async () => {
    vi.useFakeTimers();

    try {
      const client = relayRealtimeClient("/rt", {
        EventSource: fresh(),
        maxBackoffMs: 1500,
      });

      const channel = client.channel("room:1");
      channel.subscribe();

      const drop = (index: number) => {
        const source = Scripted.made[index];
        source?.fire("status", { status: "subscribed" });
        source?.fire("end", { reason: "max_duration" });
        source!.readyState = 2;
        source?.fire("error");
      };

      drop(0);
      await vi.advanceTimersByTimeAsync(1000);
      expect(Scripted.made).toHaveLength(2);

      Scripted.made[1]!.readyState = 2;
      Scripted.made[1]?.fire("error");
      await vi.advanceTimersByTimeAsync(1499);
      expect(Scripted.made).toHaveLength(2);
      await vi.advanceTimersByTimeAsync(1);
      expect(Scripted.made).toHaveLength(3);

      Scripted.made[2]!.readyState = 2;
      Scripted.made[2]?.fire("error");
      await channel.unsubscribe();
      await vi.advanceTimersByTimeAsync(5000);
      expect(Scripted.made).toHaveLength(3);
    } finally {
      vi.useRealTimers();
    }
  });

  it("retries a first join with backoff and resets it after a join", async () => {
    vi.useFakeTimers();

    const probes = vi.fn();

    try {
      const client = relayRealtimeClient("/rt", {
        EventSource: fresh(),
        fetch: probes,
      });

      const statuses: string[] = [];
      const channel = client.channel("room:1");
      channel.subscribe((status, error) =>
        statuses.push(`${status}:${error?.message ?? ""}`),
      );

      Scripted.made[0]!.readyState = 2;
      Scripted.made[0]?.fire("error");
      expect(statuses).toEqual([
        "CHANNEL_ERROR:The relay could not join room:1; retrying",
      ]);

      await vi.advanceTimersByTimeAsync(1000);
      expect(Scripted.made).toHaveLength(2);
      Scripted.made[1]?.fire("end", { reason: "upstream_error" });
      expect(Scripted.made[1]?.readyState).toBe(2);
      Scripted.made[1]?.fire("error");
      expect(statuses.at(-1)).toBe(
        "CHANNEL_ERROR:The relay could not join room:1 (upstream_error); retrying",
      );

      await vi.advanceTimersByTimeAsync(1999);
      expect(Scripted.made).toHaveLength(2);
      await vi.advanceTimersByTimeAsync(1);
      expect(Scripted.made).toHaveLength(3);

      Scripted.made[2]?.fire("status", { status: "subscribed" });
      Scripted.made[2]?.fire("end", { reason: "max_duration" });
      Scripted.made[2]!.readyState = 2;
      Scripted.made[2]?.fire("error");
      await vi.advanceTimersByTimeAsync(1000);
      expect(Scripted.made).toHaveLength(4);

      Scripted.made[3]?.fire("end", ["no reason"]);
      await vi.advanceTimersByTimeAsync(60_000);
      expect(statuses).toEqual([
        "CHANNEL_ERROR:The relay could not join room:1; retrying",
        "CHANNEL_ERROR:The relay could not join room:1 (upstream_error); retrying",
        "SUBSCRIBED:",
        "CHANNEL_ERROR:The relay closed room:1; reconnecting",
        "CHANNEL_ERROR:The relay could not join room:1 (closed); retrying",
      ]);
      expect(Scripted.made).toHaveLength(5);
      expect(probes).not.toHaveBeenCalled();

      await channel.unsubscribe();
      await vi.advanceTimersByTimeAsync(60_000);
      expect(Scripted.made).toHaveLength(5);
    } finally {
      vi.useRealTimers();
    }
  });

  it("stops a first join at timeoutMs and reads the failure once", async () => {
    vi.useFakeTimers();

    const answers: (() => Response)[] = [
      () => Response.json({ detail: "Not allowed" }, { status: 403 }),
      () => new Response("ok"),
      () => {
        throw new TypeError("offline");
      },
    ];

    const probes: RequestInit[] = [];

    try {
      const client = relayRealtimeClient("/rt", {
        EventSource: fresh(),
        timeoutMs: 5000,
        fetch: async (_input, init) => {
          probes.push(init ?? {});

          return answers.shift()!();
        },
      });

      const statuses: string[] = [];

      const refuse = () => {
        const source = Scripted.made.at(-1)!;
        source.readyState = 2;
        source.fire("error");
      };

      for (const name of ["room:1", "room:2", "room:3"]) {
        const before = Scripted.made.length;
        client
          .channel(name)
          .subscribe((status, error) =>
            statuses.push(`${name}:${status}:${error?.message ?? ""}`),
          );
        refuse();
        await vi.advanceTimersByTimeAsync(1000);
        refuse();
        await vi.advanceTimersByTimeAsync(2000);
        refuse();
        await vi.advanceTimersByTimeAsync(2000);
        expect(Scripted.made).toHaveLength(before + 3);
      }

      await vi.advanceTimersByTimeAsync(60_000);
      expect(Scripted.made).toHaveLength(9);
      expect(statuses.filter((each) => each.includes("TIMED_OUT"))).toEqual([
        "room:1:TIMED_OUT:The relay could not join room:1: 403 Not allowed",
        "room:2:TIMED_OUT:The relay could not join room:2",
        "room:3:TIMED_OUT:The relay could not join room:3",
      ]);
      expect(statuses).toHaveLength(12);
      expect(probes).toHaveLength(3);
      expect(probes[0]).toMatchObject({
        credentials: "include",
        headers: { accept: "text/event-stream" },
      });
      expect(probes[0]?.signal?.aborted).toBe(true);
    } finally {
      vi.useRealTimers();
    }
  });

  it("drops a failure read that arrives after the channel was removed", async () => {
    vi.useFakeTimers();

    let answer: (response: Response) => void = () => undefined;

    try {
      const client = relayRealtimeClient("/rt", {
        EventSource: fresh(),
        timeoutMs: 500,
        fetch: () =>
          new Promise<Response>((resolve) => {
            answer = resolve;
          }),
      });

      const statuses: string[] = [];
      const channel = client.channel("room:1");
      channel.subscribe((status) => statuses.push(status));
      Scripted.made[0]!.readyState = 2;
      Scripted.made[0]?.fire("error");
      await vi.advanceTimersByTimeAsync(500);
      await client.removeChannel(channel);
      Scripted.made[0]?.fire("end", { reason: "closed" });
      answer(new Response(null, { status: 503 }));
      await vi.advanceTimersByTimeAsync(0);

      expect(statuses).toEqual(["CHANNEL_ERROR"]);
      expect(Scripted.made).toHaveLength(1);
    } finally {
      vi.useRealTimers();
    }
  });

  it("reports a missing EventSource and uses the global one when present", () => {
    vi.stubGlobal("EventSource", undefined);

    try {
      const statuses: string[] = [];

      relayRealtimeClient("/rt")
        .channel("room:1")
        .subscribe((status, error) =>
          statuses.push(`${status}:${error?.message ?? ""}`),
        );

      expect(statuses).toEqual([
        "CHANNEL_ERROR:relayRealtimeClient needs EventSource",
      ]);

      vi.stubGlobal("EventSource", fresh());
      relayRealtimeClient("/rt").channel("room:1").subscribe();
      expect(Scripted.made).toHaveLength(1);
    } finally {
      vi.unstubAllGlobals();
    }
  });

  it("maps failed broadcasts to their problem detail, title or status text", async () => {
    const answers: (() => Response | Promise<Response>)[] = [
      () => Response.json({ detail: "Read-only" }, { status: 403 }),
      () => Response.json({ title: "Not Found" }, { status: 404 }),
      () => new Response("oops", { status: 500, statusText: "Server Error" }),
      () => Response.json(["x"], { status: 400, statusText: "Bad" }),
      () => {
        throw new Error("offline");
      },
      () => Promise.reject("refused"),
      () => new Response(null, { status: 202 }),
    ];

    const client = relayRealtimeClient("/rt", {
      EventSource: fresh(),
      fetch: async () => answers.shift()!(),
    });

    const channel = client.channel("room:1");

    expect(await channel.httpSend("e", 1)).toEqual({
      success: false,
      status: 403,
      error: "Read-only",
    });
    expect(await channel.httpSend("e", 1)).toEqual({
      success: false,
      status: 404,
      error: "Not Found",
    });
    expect(await channel.httpSend("e", 1)).toEqual({
      success: false,
      status: 500,
      error: "Server Error",
    });
    expect(await channel.httpSend("e", 1)).toEqual({
      success: false,
      status: 400,
      error: "Bad",
    });
    expect(await channel.httpSend("e", 1)).toEqual({
      success: false,
      status: 0,
      error: "offline",
    });
    expect(
      await channel.send({ type: "broadcast", event: "e", payload: 1 }),
    ).toBe("error");
    expect(
      await channel.send({ type: "broadcast", event: "e", payload: 1 }),
    ).toBe("ok");
    expect(await channel.track({})).toBe("error");
    expect(await channel.untrack()).toBe("error");
  });

  it("broadcasts with the global fetch by default", async () => {
    const fetch = vi.fn(async () => new Response(null, { status: 202 }));
    vi.stubGlobal("fetch", fetch);

    try {
      const client = relayRealtimeClient("/rt", { EventSource: fresh() });
      expect(await client.channel("room:1").httpSend("e", 1)).toEqual({
        success: true,
      });
      expect(fetch).toHaveBeenCalledWith(
        "/rt",
        expect.objectContaining({ method: "POST" }),
      );
    } finally {
      vi.unstubAllGlobals();
    }
  });
});
