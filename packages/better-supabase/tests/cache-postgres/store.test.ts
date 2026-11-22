import { describe, expect, it } from "vitest";

import {
  decodeBase64,
  encodeBase64,
  postgresCacheStore,
} from "../../src/cache-postgres/store.ts";

describe("base64", () => {
  it("round-trips bytes past the chunk size", () => {
    const bytes = new Uint8Array(100_000).map((_, index) => index % 256);

    expect(decodeBase64(encodeBase64(bytes))).toEqual(bytes);
  });
});

describe("postgresCacheStore", () => {
  it("returns an error result when the client throws", async () => {
    const client = {
      schema: () => {
        throw new Error("boom");
      },
    };

    // SAFETY: the stub has only the method the store calls first.
    const store = postgresCacheStore({ client: client as never });

    const result = await store.get("k");

    expect(result.ok).toBe(false);
    expect(result.error?.kind).toBe("unexpected");
  });

  it("reads tags in chunks of 128", async () => {
    const calls: string[][] = [];

    const client = {
      schema: () => ({
        from: () => ({
          select: () => ({
            in: (_column: string, tags: string[]) => {
              calls.push(tags);

              return {
                overrideTypes: () =>
                  Promise.resolve({
                    data: [{ tag: tags[0], stale_at: 1, expired_at: 2 }],
                    error: null,
                  }),
              };
            },
          }),
        }),
      }),
    };

    const store = postgresCacheStore({ client: client as never });
    const tags = Array.from({ length: 300 }, (_, index) => `t${String(index)}`);

    const result = await store.tagStates(tags);

    expect(calls.map((call) => call.length)).toEqual([128, 128, 44]);
    expect(result.ok && result.data.size).toBe(3);
  });
});
