import { describe, expect, it } from "vitest";

import { testWebhookTransport } from "../../src/testing/index.ts";
import { parseRetryAfter } from "../../src/webhooks/http.ts";
import {
  fetchTransport,
  WebhookPolicyError,
} from "../../src/webhooks/index.ts";

type Route = (url: string, init: RequestInit) => Response;

function fakeFetch(route: Route) {
  const calls: { url: string; init: RequestInit }[] = [];
  const fetch = async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    calls.push({ url, init: init ?? {} });
    return route(url, init ?? {});
  };
  return { fetch, calls };
}

const request = {
  url: "https://hooks.example.com/in",
  headers: { "content-type": "application/json" },
  body: "{}",
};

const redirect = (location: string | null, status = 307) =>
  new Response(null, { status, headers: location ? { location } : {} });

describe("fetchTransport", () => {
  it("POSTs the body and returns the status and response text", async () => {
    const { fetch, calls } = fakeFetch(
      () => new Response("ok", { status: 202 }),
    );
    const transport = fetchTransport({ fetch });
    expect(await transport.send(request)).toEqual({ status: 202, body: "ok" });
    expect(calls[0]!.init).toMatchObject({
      method: "POST",
      body: "{}",
      redirect: "manual",
    });
  });

  it("returns Retry-After as seconds", async () => {
    const { fetch } = fakeFetch(
      () =>
        new Response("", { status: 429, headers: { "retry-after": "120" } }),
    );
    expect(await fetchTransport({ fetch }).send(request)).toEqual({
      status: 429,
      body: "",
      retryAfter: 120,
    });
    const now = Date.parse("2026-10-04T12:00:00Z");
    expect(parseRetryAfter("Sun, 04 Oct 2026 12:01:30 GMT", now)).toBe(90);
    expect(parseRetryAfter("Sun, 04 Oct 2026 11:00:00 GMT", now)).toBe(0);
    expect(parseRetryAfter("soon", now)).toBe(undefined);
    expect(parseRetryAfter(null, now)).toBe(undefined);
  });

  it("follows allowed redirects and checks each hop", async () => {
    const seen: string[] = [];
    const { fetch, calls } = fakeFetch((url) =>
      url.endsWith("/in") ? redirect("/moved") : new Response("done"),
    );
    const transport = fetchTransport({
      fetch,
      maxRedirects: 5,
      allowUrl: (url) => {
        seen.push(url.href);
        return true;
      },
    });
    expect(await transport.send(request)).toEqual({
      status: 200,
      body: "done",
    });
    expect(seen).toEqual([
      "https://hooks.example.com/in",
      "https://hooks.example.com/moved",
    ]);
    expect(calls.map((call) => call.url)).toEqual(seen);
  });

  it("refuses a redirect to a URL allowUrl rejects", async () => {
    const { fetch, calls } = fakeFetch(() =>
      redirect("http://169.254.169.254/latest"),
    );
    const transport = fetchTransport({
      fetch,
      maxRedirects: 5,
      allowUrl: (url) => url.hostname !== "169.254.169.254",
    });
    await expect(transport.send(request)).rejects.toThrow(WebhookPolicyError);
    expect(calls).toHaveLength(1);
  });

  it("follows no redirects by default", async () => {
    const { fetch, calls } = fakeFetch(() => redirect("/moved"));
    await expect(fetchTransport({ fetch }).send(request)).rejects.toThrow(
      "Redirect 307 not followed (maxRedirects is 0)",
    );
    expect(calls).toHaveLength(1);
  });

  it("reads at most maxResponseBytes of the body", async () => {
    let pulled = 0;
    const stream = new ReadableStream<Uint8Array>({
      pull(controller) {
        pulled += 1;
        controller.enqueue(new TextEncoder().encode("abcdefgh"));
        if (pulled > 100) controller.close();
      },
    });
    const { fetch } = fakeFetch(() => new Response(stream, { status: 500 }));
    expect(
      await fetchTransport({ fetch, maxResponseBytes: 12 }).send(request),
    ).toEqual({ status: 500, body: "abcdefghabcd" });
    expect(pulled).toBeLessThan(5);
    const empty = fakeFetch(() => new Response(null, { status: 204 }));
    expect(await fetchTransport({ fetch: empty.fetch }).send(request)).toEqual({
      status: 204,
      body: "",
    });
  });

  it("treats a throwing allowUrl as a rejection", async () => {
    const { fetch, calls } = fakeFetch(() => new Response("ok"));
    const transport = fetchTransport({
      fetch,
      allowUrl: () => {
        throw new Error("dns failed");
      },
    });
    await expect(transport.send(request)).rejects.toThrow("not allowed");
    expect(calls).toHaveLength(0);
  });

  it("stops at a redirect without a location or after too many hops", async () => {
    const missing = fakeFetch(() => redirect(null));
    await expect(
      fetchTransport({ fetch: missing.fetch }).send(request),
    ).rejects.toThrow("without a location");
    const loop = fakeFetch(() => redirect("/in", 302));
    await expect(
      fetchTransport({ fetch: loop.fetch, maxRedirects: 2 }).send(request),
    ).rejects.toThrow("More than 2 redirects");
    expect(loop.calls).toHaveLength(3);
  });

  it("combines the caller's abort signal with the timeout", async () => {
    const controller = new AbortController();
    const { fetch, calls } = fakeFetch(() => new Response("ok"));
    await fetchTransport({ fetch, timeoutMs: 50 }).send({
      ...request,
      signal: controller.signal,
    });
    const signal = calls[0]!.init.signal!;
    expect(signal.aborted).toBe(false);
    controller.abort();
    expect(signal.aborted).toBe(true);
  });

  it("passes the transport conformance kit", async () => {
    const bodies: string[] = [];
    const { fetch } = fakeFetch((_url, init) => {
      bodies.push(String(init.body));
      return new Response("ok");
    });
    const report = await testWebhookTransport(fetchTransport({ fetch }), {
      url: "https://hooks.example.com/in",
      received: async () => bodies,
    });
    expect(report.checks.every((check) => check.ok)).toBe(true);
  });

  it("fails the kit for a transport that returns no status", async () => {
    await expect(
      testWebhookTransport(
        {
          apiVersion: 1,
          name: "broken",
          send: async () => ({ status: 0, body: "" }),
        },
        { url: "https://hooks.example.com/in", received: async () => [] },
      ),
    ).rejects.toThrow("status must be an HTTP status");
  });
});
