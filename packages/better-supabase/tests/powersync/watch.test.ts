import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import type { PowerSyncDatabaseLike } from "../../src/powersync/executor.ts";

import { ok } from "../../src/core/result.ts";
import { watch } from "../../src/powersync/watch.ts";

function fakePowerSync(options: { listeners?: boolean } = {}) {
  const status = { connected: true };
  const listeners = new Set<(next: { connected: boolean }) => void>();

  const db: PowerSyncDatabaseLike = {
    execute: vi.fn(),
    getAll: vi.fn(),
    writeTransaction: vi.fn(),
    onChange: () => () => undefined,
    currentStatus: status,
    ...(options.listeners === false
      ? {}
      : {
          registerListener: (listener: {
            statusChanged?: (next: { connected: boolean }) => void;
          }) => {
            const notify = (next: { connected: boolean }) =>
              listener.statusChanged?.(next);

            listeners.add(notify);

            return () => void listeners.delete(notify);
          },
        }),
  };

  return {
    db,
    listeners,
    setConnected: (connected: boolean) => {
      status.connected = connected;

      for (const listener of listeners) {
        listener({ connected });
      }
    },
  };
}

/** A query whose answer changes on every run, so each run calls `onResult`. */
function counter() {
  let runs = 0;

  return vi.fn(async () => {
    runs += 1;

    return ok(runs);
  });
}

describe("watch refresh", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it("reruns every everyMs and skips the runs while offline", async () => {
    const { db, setConnected } = fakePowerSync();
    const query = counter();
    const onResult = vi.fn();

    const stop = watch(db, query, {
      tables: ["customers"],
      onResult,
      refresh: { everyMs: 1000 },
    });

    await vi.advanceTimersByTimeAsync(0);
    expect(query).toHaveBeenCalledOnce();
    await vi.advanceTimersByTimeAsync(2000);
    expect(query).toHaveBeenCalledTimes(3);
    expect(onResult).toHaveBeenLastCalledWith(ok(3));
    setConnected(false);
    await vi.advanceTimersByTimeAsync(3000);
    expect(query).toHaveBeenCalledTimes(3);
    stop();
  });

  it("reruns when PowerSync connects again", async () => {
    const { db, setConnected } = fakePowerSync();
    const query = counter();

    const stop = watch(db, query, {
      tables: ["customers"],
      onResult: vi.fn(),
      refresh: { onReconnect: true },
    });

    await vi.advanceTimersByTimeAsync(0);
    setConnected(true);
    await vi.advanceTimersByTimeAsync(0);
    expect(query).toHaveBeenCalledOnce();
    setConnected(false);
    setConnected(true);
    await vi.advanceTimersByTimeAsync(0);
    expect(query).toHaveBeenCalledTimes(2);
    stop();
  });

  it("calls no onResult when a refresh returns the same result", async () => {
    const { db } = fakePowerSync();
    const onResult = vi.fn();

    const stop = watch(db, async () => ok([{ id: "a" }]), {
      tables: ["customers"],
      onResult,
      refresh: { everyMs: 1000 },
    });

    await vi.advanceTimersByTimeAsync(3000);
    expect(onResult).toHaveBeenCalledOnce();
    stop();
  });

  it("stops the timer and the listener on stop and on abort", async () => {
    for (const end of ["stop", "abort"] as const) {
      const { db, listeners } = fakePowerSync();
      const query = counter();
      const controller = new AbortController();

      const stop = watch(db, query, {
        tables: ["customers"],
        onResult: vi.fn(),
        signal: controller.signal,
        refresh: { everyMs: 1000, onReconnect: true },
      });

      await vi.advanceTimersByTimeAsync(0);
      expect(listeners.size).toBe(1);

      if (end === "stop") {
        stop();
      } else {
        controller.abort();
      }

      await vi.advanceTimersByTimeAsync(5000);
      expect(query).toHaveBeenCalledOnce();
      expect(listeners.size).toBe(0);
    }
  });

  it("needs registerListener for onReconnect", () => {
    const { db } = fakePowerSync({ listeners: false });
    expect(() =>
      watch(db, async () => ok(1), {
        tables: ["customers"],
        onResult: vi.fn(),
        refresh: { onReconnect: true },
      }),
    ).toThrow(/registerListener/);
  });
});
