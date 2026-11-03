import { afterEach, describe, expect, it, vi } from "vitest";

import type { BlockTransport } from "../../../src/core/block-transport.ts";

import { createLeases } from "../../../src/blocks/queue/index.ts";
import { fakeSql } from "../../fixtures/fake-sql.ts";

const EXPIRES = "2030-01-01T00:00:00.000Z";

const claimed = (holder = "h1"): Record<string, unknown> => ({
  lease_state: "claimed",
  lease_holder: holder,
  lease_expires_at: EXPIRES,
  retry_after_ms: 0,
});

const busy = (retryAfterMs: number): Record<string, unknown> => ({
  lease_state: "busy",
  lease_holder: null,
  lease_expires_at: EXPIRES,
  retry_after_ms: retryAfterMs,
});

afterEach(() => {
  vi.useRealTimers();
});

describe("createLeases", () => {
  it("claims once without waiting by default", async () => {
    const fake = fakeSql([["claim_lease", [busy(5000)]]]);

    const result = await createLeases(fake.sql)
      .claim({ scope: "s", key: "k" })
      .orThrow();

    expect(result).toEqual({ status: "busy", retryAfterMs: 5000 });
    expect(fake.calls).toHaveLength(1);
    expect(fake.calls[0]!.values).toEqual(["s", "k", 60]);
  });

  it("answers completed without waiting", async () => {
    const fake = fakeSql([
      [
        "claim_lease",
        [{ ...busy(1000), lease_state: "completed", retry_after_ms: 1000 }],
      ],
    ]);

    const result = await createLeases(fake.sql)
      .claim({ key: "k", timeoutMs: 5000 })
      .orThrow();

    expect(result.status).toBe("completed");
    expect(fake.calls).toHaveLength(1);
  });

  it("waits with backoff inside the timeout, then answers busy", async () => {
    vi.useFakeTimers();

    const fake = fakeSql([["claim_lease", [busy(60_000)]]]);
    const pending = createLeases(fake.sql).claim({ key: "k", timeoutMs: 400 });

    await vi.advanceTimersByTimeAsync(1000);

    expect(await pending.orThrow()).toEqual({
      status: "busy",
      retryAfterMs: 60_000,
    });
    // 0, 50, 150, 350 and the last wait ends at the 400 ms bound.
    expect(fake.calls.length).toBeGreaterThanOrEqual(4);
    expect(fake.calls.length).toBeLessThanOrEqual(6);
  });

  it("claims once the holder lets go during the wait", async () => {
    vi.useFakeTimers();

    let calls = 0;

    const fake = fakeSql([
      [
        "claim_lease",
        () => {
          calls += 1;

          return calls < 3 ? [busy(10)] : [claimed("h2")];
        },
      ],
    ]);

    const pending = createLeases(fake.sql).claim({ key: "k", timeoutMs: 5000 });

    await vi.advanceTimersByTimeAsync(500);

    const result = await pending.orThrow();

    expect(result).toMatchObject({
      status: "claimed",
      lease: { holder: "h2" },
    });
    expect(
      result.status === "claimed" && result.lease.expiresAt.toString(),
    ).toBe("2030-01-01T00:00:00Z");
  });

  it("refuses an empty key", async () => {
    const fake = fakeSql([]);

    const result = await createLeases(fake.sql).claim({ key: "" });

    expect(result.ok).toBe(false);
    expect(fake.calls).toHaveLength(0);
  });

  it("releases the lease when the callback throws", async () => {
    const fake = fakeSql([
      ["claim_lease", [claimed()]],
      ["release_lease_claim", [{ done: true }]],
    ]);

    const result = await createLeases(fake.sql).withLease(
      { scope: "s", key: "k", heartbeat: false },
      () => {
        throw new Error("boom");
      },
    );

    expect(result.ok).toBe(false);
    expect(fake.calls.at(-1)!.text).toContain("release_lease_claim");
    expect(fake.calls.at(-1)!.values).toEqual(["s", "k", "h1"]);
  });

  it("releases after success, or completes when asked", async () => {
    const fake = fakeSql([
      ["claim_lease", [claimed()]],
      ["release_lease_claim", [{ done: true }]],
      ["complete_lease", [{ done: true }]],
    ]);

    const leases = createLeases(fake.sql);

    expect(
      await leases.withLease({ key: "k", heartbeat: false }, () => 7).orThrow(),
    ).toEqual({ status: "claimed", value: 7 });
    expect(fake.calls.at(-1)!.text).toContain("release_lease_claim");

    await leases
      .withLease({ key: "k", heartbeat: false, completeFor: 30 }, () => 1)
      .orThrow();
    expect(fake.calls.at(-1)!.text).toContain("complete_lease");
    expect(fake.calls.at(-1)!.values).toEqual(["", "k", "h1", 30]);
  });

  it("does not run the callback while the lease is busy or completed", async () => {
    const fake = fakeSql([["claim_lease", [busy(1000)]]]);
    const fn = vi.fn();

    const result = await createLeases(fake.sql)
      .withLease({ key: "k" }, fn)
      .orThrow();

    expect(result.status).toBe("busy");
    expect(fn).not.toHaveBeenCalled();
  });

  it("extends the lease while the callback runs", async () => {
    vi.useFakeTimers();

    const fake = fakeSql([
      ["claim_lease", [claimed()]],
      ["extend_lease_claim", [{ done: true }]],
      ["release_lease_claim", [{ done: true }]],
    ]);

    const pending = createLeases(fake.sql).withLease(
      { key: "k", leaseSeconds: 2 },
      () =>
        new Promise<string>((resolve) => {
          setTimeout(() => {
            resolve("done");
          }, 2500);
        }),
    );

    await vi.advanceTimersByTimeAsync(3000);

    expect(await pending.orThrow()).toEqual({
      status: "claimed",
      value: "done",
    });
    expect(
      fake.calls.filter((call) => call.text.includes("extend_lease_claim"))
        .length,
    ).toBeGreaterThanOrEqual(2);
  });

  it("calls the functions with named arguments over a transport", async () => {
    const seen: { fn: string; args: Readonly<Record<string, unknown>> }[] = [];

    const transport: BlockTransport = {
      call: (_schema, fn, args) => {
        seen.push({ fn, args });

        return Promise.resolve(fn === "claim_lease" ? [claimed("h9")] : true);
      },
    };

    const result = await createLeases(transport, { scope: "inbox" })
      .withLease({ key: "k", leaseSeconds: 30, heartbeat: false }, () => 1)
      .orThrow();

    expect(result.status).toBe("claimed");
    expect(seen).toEqual([
      {
        fn: "claim_lease",
        args: { scope: "inbox", key: "k", lease_seconds: 30 },
      },
      {
        fn: "release_lease_claim",
        args: { scope: "inbox", key: "k", holder: "h9" },
      },
    ]);
  });
});
