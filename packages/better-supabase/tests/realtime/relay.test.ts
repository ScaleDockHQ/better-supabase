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
