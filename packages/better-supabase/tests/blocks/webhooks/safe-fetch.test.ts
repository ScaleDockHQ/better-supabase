import { describe, expect, it } from "vitest";

import {
  createSafeFetch,
  UnsafeUrlError,
} from "../../../src/blocks/webhooks/index.ts";

type Hop = { url: string; method: string; headers: Headers; body: string };

function fakeFetch(answer: (url: URL) => Response) {
  const hops: Hop[] = [];
  const fetch: typeof globalThis.fetch = async (input, init) => {
    const url = input instanceof URL ? input : new URL(String(input));
    hops.push({
      url: url.href,
      method: init?.method ?? "GET",
      headers: new Headers(init?.headers),
      body: init?.body
        ? new TextDecoder().decode(init.body as ArrayBuffer)
        : "",
    });
    return answer(url);
  };
  return { fetch, hops };
}

const resolve = (host: string) =>
  Promise.resolve(
    host === "internal.example.com" ? ["10.0.0.5"] : ["93.184.216.34"],
  );

describe("createSafeFetch", () => {
  it("fetches public HTTPS URLs and refuses private, plain-HTTP and credentialed ones", async () => {
    const { fetch, hops } = fakeFetch(() => new Response("ok"));
    const safe = createSafeFetch({ fetch, resolve });
    expect(await (await safe("https://example.com/a")).text()).toBe("ok");
    for (const url of [
      "http://example.com/",
      "https://127.0.0.1/",
      "https://internal.example.com/",
      "https://user:pass@example.com/",
      "https://localhost/",
    ]) {
      await expect(safe(url)).rejects.toBeInstanceOf(UnsafeUrlError);
    }
    expect(hops).toHaveLength(1);
  });

  it("checks every redirect and drops credentials across origins", async () => {
    const { fetch, hops } = fakeFetch((url) => {
      if (url.pathname === "/start")
        return new Response(null, {
          status: 302,
          headers: { location: "https://other.example.com/next" },
        });
      if (url.pathname === "/next")
        return new Response(null, {
          status: 307,
          headers: { location: "https://internal.example.com/secret" },
        });
      return new Response("done");
    });
    const safe = createSafeFetch({ fetch, resolve });
    await expect(
      safe("https://example.com/start", {
        method: "POST",
        body: "x",
        headers: { authorization: "Bearer t" },
      }),
    ).rejects.toThrow(/internal\.example\.com/);
    expect(hops.map((hop) => [hop.url, hop.method, hop.body])).toEqual([
      ["https://example.com/start", "POST", "x"],
      ["https://other.example.com/next", "GET", ""],
    ]);
    expect(hops[1]!.headers.get("authorization")).toBeNull();
  });

  it("keeps the body on 307, limits redirects and needs a location", async () => {
    let count = 0;
    const { fetch, hops } = fakeFetch(() => {
      count += 1;
      return count === 1
        ? new Response(null, { status: 307, headers: { location: "/again" } })
        : new Response("ok");
    });
    await createSafeFetch({ fetch, resolve })("https://example.com/", {
      method: "PUT",
      body: "data",
    });
    expect(hops[1]).toMatchObject({ method: "PUT", body: "data" });
    const loop = fakeFetch(
      () => new Response(null, { status: 301, headers: { location: "/" } }),
    );
    await expect(
      createSafeFetch({ fetch: loop.fetch, resolve, maxRedirects: 1 })(
        "https://example.com/",
      ),
    ).rejects.toThrow(/More than 1 redirects/);
    const bare = fakeFetch(() => new Response(null, { status: 302 }));
    await expect(
      createSafeFetch({ fetch: bare.fetch, resolve })("https://example.com/"),
    ).rejects.toThrow(/without a location/);
    const rejecting = createSafeFetch({
      fetch,
      allowUrl: () => Promise.reject(new Error("dns down")),
    });
    await expect(rejecting("https://example.com/")).rejects.toBeInstanceOf(
      UnsafeUrlError,
    );
  });
});
