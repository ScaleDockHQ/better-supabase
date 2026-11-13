import { describe, expect, it, vi } from "vitest";

import type { PgListenClient } from "../../src/postgres/listen.ts";

import { silentLogger } from "../../src/core/logger.ts";
import { listenForWork } from "../../src/postgres/listen.ts";

type Listener = (value: never) => void;

class FakeClient implements PgListenClient {
  readonly queries: string[] = [];
  released: boolean | undefined;
  private readonly ready: Record<string, unknown[]>;
  private readonly listeners = new Map<string, Listener[]>();

  constructor(ready: Record<string, unknown[]> = {}) {
    this.ready = ready;
  }

  on(event: string, listener: Listener): this {
    this.listeners.set(event, [...(this.listeners.get(event) ?? []), listener]);

    return this;
  }

  removeAllListeners(): this {
    this.listeners.clear();

    return this;
  }

  emit(event: string, value?: unknown): void {
    for (const listener of this.listeners.get(event) ?? []) {
      // SAFETY: each test emits the value its event's listener takes.
      (listener as (value: unknown) => void)(value);
    }
  }

  async query(text: string): Promise<{ rows: unknown[] }> {
    this.queries.push(text);
    const match = Object.keys(this.ready).find((key) => text.includes(key));

    return { rows: match ? (this.ready[match] ?? []) : [] };
  }

  release(destroy?: boolean): void {
    this.released = destroy ?? false;
  }

  notify(payload: string, channel = "better_supabase_work"): void {
    this.emit("notification", { channel, payload });
  }
}

const poolOf = (...clients: FakeClient[]) => ({
  connect: vi.fn(async () => {
    const next = clients.shift();

    if (!next) {
      throw new Error("no connection");
    }

    return next;
  }),
  options: { connectionString: "postgres://u:p@db.example.com:5432/postgres" },
});

describe("listenForWork", () => {
  it("refuses the transaction pooler", async () => {
    await expect(
      listenForWork(
        {
          connect: async () => new FakeClient(),
          options: {
            connectionString:
              "postgres://u:p@aws-0.pooler.supabase.com:6543/postgres",
          },
        },
        {},
      ),
    ).rejects.toThrow(/transaction pooler \(port 6543\) drops LISTEN/);
  });

  it("gathers notifications into one pass per kind and queue", async () => {
    const client = new FakeClient();
    const inbox = vi.fn(async () => undefined);
    const emails = vi.fn(async () => undefined);

    const listener = await listenForWork(poolOf(client), {
      inbox,
      queues: { emails },
      debounceMs: 5,
      logger: silentLogger,
    });

    expect(client.queries).toContain("listen better_supabase_work");

    client.notify('{"kind":"inbox"}');
    client.notify('{"kind":"inbox"}');
    client.notify('{"kind":"queue","queue":"emails"}');
    client.notify('{"kind":"queue","queue":"other"}');
    client.notify('{"kind":"outbox"}');
    client.notify("not json");
    client.notify('{"kind":"inbox"}', "elsewhere");

    await vi.waitFor(() => {
      expect(emails).toHaveBeenCalledOnce();
    });
    expect(inbox).toHaveBeenCalledOnce();

    await listener.close();
    expect(client.released).toBe(true);
    expect(client.queries.at(-1)).toBe("unlisten better_supabase_work");
  });

  it("probes after it connects and again after a reconnect", async () => {
    const first = new FakeClient();

    const second = new FakeClient({
      webhook_inbox_has_work: [{ ready: true }],
      ready_job_queues: [{ queue: "emails" }],
    });

    const inbox = vi.fn(async () => undefined);
    const emails = vi.fn(async () => undefined);

    const listener = await listenForWork(poolOf(first, second), {
      inbox,
      queues: { emails },
      debounceMs: 1,
      reconnectMs: 1,
      logger: silentLogger,
    });

    expect(first.queries).toContain(
      "select better_supabase.webhook_inbox_has_work() as ready",
    );
    expect(inbox).not.toHaveBeenCalled();

    first.emit("error", new Error("terminated"));

    await vi.waitFor(() => {
      expect(emails).toHaveBeenCalledOnce();
    });
    expect(inbox).toHaveBeenCalledOnce();
    expect(first.released).toBe(true);

    await listener.close();
  });
});
