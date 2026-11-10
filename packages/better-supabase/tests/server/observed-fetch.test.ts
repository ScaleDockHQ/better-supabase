import { describe, expect, it, vi } from "vitest";

import type { ObservedFetchCall } from "../../src/server/observed-fetch.ts";

import { observedFetch } from "../../src/server/observed-fetch.ts";

describe("observedFetch", () => {
  it("reports the method, the URL without its query, the status and the duration", async () => {
    const calls: ObservedFetchCall[] = [];
    let clock = 10;

    const fetch = observedFetch({
      fetch: () => {
        clock += 25;

        return Promise.resolve(new Response("{}", { status: 201 }));
      },
      now: () => clock,
      onCall: (call) => calls.push(call),
    });

    const response = await fetch(
      "https://x.supabase.co/rest/v1/notes?apikey=k",
      { method: "post" },
    );

    expect(response.status).toBe(201);
    expect(calls).toEqual([
      {
        method: "POST",
        url: "https://x.supabase.co/rest/v1/notes",
        status: 201,
        durationMs: 25,
      },
    ]);
  });

  it("reads a Request and reports a failure before rethrowing it", async () => {
    const calls: ObservedFetchCall[] = [];
    const failure = new TypeError("offline");

    const fetch = observedFetch({
      fetch: () => Promise.reject(failure),
      onCall: (call) => calls.push(call),
    });

    await expect(
      fetch(
        new Request("https://x.supabase.co/auth/v1/user", { method: "GET" }),
      ),
    ).rejects.toBe(failure);

    expect(calls[0]).toMatchObject({
      method: "GET",
      url: "https://x.supabase.co/auth/v1/user",
      status: undefined,
      error: "TypeError",
    });
  });

  it("never lets a throwing observer change the response", async () => {
    const onCall = vi.fn(() => {
      throw new Error("observer");
    });

    const fetch = observedFetch({
      fetch: () => Promise.resolve(new Response("ok")),
      onCall,
    });

    expect(await (await fetch("https://a.test/x")).text()).toBe("ok");
    expect(onCall).toHaveBeenCalledOnce();
  });
});
