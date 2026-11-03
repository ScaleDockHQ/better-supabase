import { describe, expect, it } from "vitest";

import { realtimeTokenRoute } from "../../src/ai-sdk/realtime.ts";
import { AsyncResult } from "../../src/core/result.ts";

const request = () =>
  new Request("https://x.test/rt", {
    method: "POST",
    body: JSON.stringify({ model: "m1" }),
  });

function route(allowed: boolean, caller = true) {
  const rows: unknown[] = [];
  let minted = 0;

  const handler = realtimeTokenRoute({
    identify: () => (caller ? { key: "u1" } : undefined),
    rateLimit: {
      check: () =>
        AsyncResult.ok({
          allowed,
          retryAfter: 2.2,
          remaining: 0,
          limit: 1,
        } as never),
    },
    mint: async () => {
      minted += 1;

      return { value: "tok" };
    },
    record: (entry) => {
      rows.push(entry);
    },
  });

  return { handler, rows, minted: () => minted };
}

describe("realtimeTokenRoute", () => {
  it("mints and records a token", async () => {
    const { handler, rows } = route(true);
    const response = await handler(request());

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ value: "tok" });
    expect(rows).toHaveLength(1);
  });

  it("answers 401 and 429 without minting", async () => {
    const anonymous = route(true, false);
    expect((await anonymous.handler(request())).status).toBe(401);

    const limited = route(false);
    const response = await limited.handler(request());
    expect(response.status).toBe(429);
    expect(response.headers.get("retry-after")).toBe("3");
    expect(limited.minted()).toBe(0);
  });
});
