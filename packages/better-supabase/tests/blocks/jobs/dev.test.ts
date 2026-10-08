import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { devDrain, devDrainSecret } from "../../../src/blocks/jobs/index.ts";

describe("devDrainSecret", () => {
  it("keeps a set secret and generates one otherwise", () => {
    expect(devDrainSecret({ CRON_SECRET: "set" })).toBe("set");
    const env: Record<string, string | undefined> = {};
    const secret = devDrainSecret(env, "JOBS_SECRET");
    expect(secret).toMatch(/^[0-9a-f]{64}$/);
    expect(env["JOBS_SECRET"]).toBe(secret);
    expect(devDrainSecret(env, "JOBS_SECRET")).toBe(secret);
  });
});

describe("devDrain", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it("calls the drain route with its secret on every interval", async () => {
    const fetch = vi.fn<typeof globalThis.fetch>(() =>
      Promise.resolve(Response.json({ ok: true })),
    );
    const onError = vi.fn<(message: string) => void>();
    const drain = devDrain({
      url: "http://localhost:3000/api/jobs/drain",
      secret: "s3cret",
      every: 1000,
      fetch,
      onError,
    });
    expect(fetch).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(1000);
    expect(fetch).toHaveBeenCalledTimes(1);
    const [url, init] = fetch.mock.calls[0]!;
    expect(String(url)).toBe("http://localhost:3000/api/jobs/drain");
    expect(init?.method).toBeUndefined();
    expect(new Headers(init?.headers).get("authorization")).toBe(
      "Bearer s3cret",
    );
    await vi.advanceTimersByTimeAsync(2000);
    expect(fetch).toHaveBeenCalledTimes(3);
    drain.stop();
    await vi.advanceTimersByTimeAsync(5000);
    expect(fetch).toHaveBeenCalledTimes(3);
    expect(onError).not.toHaveBeenCalled();
  });

  it("reports failures, skips overlapping calls and stops on abort", async () => {
    let release: () => void = () => undefined;
    const fetch = vi.fn<typeof globalThis.fetch>(
      () =>
        new Promise((resolve) => {
          release = () => {
            resolve(new Response(null, { status: 401 }));
          };
        }),
    );
    const onError = vi.fn<(message: string) => void>();
    const controller = new AbortController();
    const drain = devDrain({
      url: new URL("http://localhost:3000/drain"),
      secret: "s",
      fetch,
      onError,
      signal: controller.signal,
    });
    const first = drain.tick();
    await drain.tick();
    expect(fetch).toHaveBeenCalledTimes(1);
    release();
    await first;
    expect(onError).toHaveBeenCalledWith("[jobs] dev drain answered 401");

    fetch.mockRejectedValueOnce(new TypeError("fetch failed"));
    await drain.tick();
    expect(onError).toHaveBeenLastCalledWith(
      "[jobs] dev drain failed: fetch failed",
    );

    controller.abort();
    await vi.advanceTimersByTimeAsync(120_000);
    await drain.tick();
    expect(fetch).toHaveBeenCalledTimes(2);
  });

  it("refuses a missing secret or interval", () => {
    expect(() =>
      devDrain({ url: "http://localhost/drain", secret: "" }),
    ).toThrow(/needs the drain route's secret/);
    expect(() =>
      devDrain({ url: "http://localhost/drain", secret: "s", every: 0 }),
    ).toThrow(/every must be a positive/);
  });
});
