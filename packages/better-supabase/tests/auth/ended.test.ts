import { describe, expect, it, vi } from "vitest";

import { clearSessionCookies, sessionStatus } from "../../src/auth/ended.ts";
import { sessionCookieName, writeSession } from "../../src/auth/session.ts";

const PROJECT = "https://ref.supabase.co";
const NAME = sessionCookieName(PROJECT);

const token = (claims: Record<string, unknown>) =>
  `h.${Buffer.from(JSON.stringify(claims)).toString("base64url")}.s`;

const live = token({ sub: "u", exp: Math.floor(Date.now() / 1000) + 3600 });

const cookieHeader = (accessToken: string, padding = 0) =>
  writeSession([], NAME, {
    access_token: accessToken,
    refresh_token: "r",
    user: { id: "u", padding: "x".repeat(padding) },
  })
    .map((write) => `${write.name}=${encodeURIComponent(write.value)}`)
    .join("; ");

const answering = (status: number) =>
  vi.fn<typeof fetch>(async () => Response.json({}, { status }));

describe("sessionStatus", () => {
  it("asks Auth with the token and maps the answer", async () => {
    const fetch = answering(200);
    await expect(
      sessionStatus(live, { url: PROJECT, publishableKey: "pk", fetch }),
    ).resolves.toBe("active");
    const [url, init] = fetch.mock.calls[0]!;
    expect(String(url)).toBe(`${PROJECT}/auth/v1/user`);
    const headers = new Headers(init?.headers);
    expect(headers.get("authorization")).toBe(`Bearer ${live}`);
    expect(headers.get("apikey")).toBe("pk");

    for (const status of [401, 403]) {
      await expect(
        sessionStatus(live, {
          url: PROJECT,
          publishableKey: "pk",
          fetch: answering(status),
        }),
      ).resolves.toBe("ended");
    }
  });

  it("keeps the session on server errors, timeouts and network failures", async () => {
    const options = { url: PROJECT, publishableKey: "pk" };
    await expect(
      sessionStatus(live, { ...options, fetch: answering(500) }),
    ).resolves.toBe("unknown");
    await expect(
      sessionStatus(live, { ...options, fetch: answering(429) }),
    ).resolves.toBe("unknown");
    await expect(
      sessionStatus(live, {
        ...options,
        fetch: vi.fn<typeof fetch>(async () => {
          throw new TypeError("fetch failed");
        }),
      }),
    ).resolves.toBe("unknown");
    await expect(
      sessionStatus(live, {
        ...options,
        timeoutMs: 5,
        fetch: vi.fn<typeof fetch>(
          (_url, init) =>
            new Promise((_resolve, reject) => {
              init?.signal?.addEventListener("abort", () => {
                reject(init.signal?.reason);
              });
            }),
        ),
      }),
    ).resolves.toBe("unknown");
  });

  it("reads the token from the session cookie or the bearer header", async () => {
    const fetch = answering(403);
    const options = { url: PROJECT, publishableKey: "pk", fetch };
    const chunked = new Request("https://app.test/", {
      headers: { cookie: cookieHeader(live, 5000) },
    });
    await expect(sessionStatus(chunked, options)).resolves.toBe("ended");
    expect(
      new Headers(fetch.mock.calls[0]![1]?.headers).get("authorization"),
    ).toBe(`Bearer ${live}`);

    const bearer = new Request("https://app.test/", {
      headers: { authorization: `Bearer ${live}` },
    });
    await expect(sessionStatus(bearer, options)).resolves.toBe("ended");

    const renamed = new Request("https://app.test/", {
      headers: { cookie: cookieHeader(live).replaceAll(NAME, "custom") },
    });
    await expect(
      sessionStatus(renamed, { ...options, cookieName: "custom" }),
    ).resolves.toBe("ended");
    expect(fetch).toHaveBeenCalledTimes(3);
  });

  it("does not ask Auth without a token or with an expired one", async () => {
    const fetch = answering(403);
    const options = { url: PROJECT, publishableKey: "pk", fetch };
    await expect(
      sessionStatus(new Request("https://app.test/"), options),
    ).resolves.toBe("unknown");
    const expired = token({ sub: "u", exp: 1000 });
    await expect(sessionStatus(expired, options)).resolves.toBe("unknown");
    await expect(
      sessionStatus(live, { ...options, now: () => Date.now() + 7_200_000 }),
    ).resolves.toBe("unknown");
    expect(fetch).not.toHaveBeenCalled();
  });
});

describe("clearSessionCookies", () => {
  it("expires every chunk of the session cookie and adds no-store headers", () => {
    const request = new Request("https://app.test/", {
      headers: { cookie: `${cookieHeader(live, 5000)}; other=1` },
    });
    const response = new Response(null, { status: 200 });
    expect(clearSessionCookies(request, response, { url: PROJECT })).toBe(
      response,
    );
    const cleared = response.headers.getSetCookie();
    expect(cleared.length).toBeGreaterThan(1);
    expect(cleared.every((value) => value.startsWith(`${NAME}.`))).toBe(true);
    expect(cleared.every((value) => value.includes("Max-Age=0"))).toBe(true);
    expect(response.headers.get("cache-control")).toContain("no-store");
  });

  it("uses the cookie name and options it is given", () => {
    const request = new Request("https://app.test/", {
      headers: { cookie: cookieHeader(live).replaceAll(NAME, "custom") },
    });
    const response = clearSessionCookies(request, new Response(null), {
      url: PROJECT,
      cookieName: "custom",
      cookie: { domain: ".app.test" },
    });
    const [cleared] = response.headers.getSetCookie();
    expect(cleared).toMatch(/^custom=;/);
    expect(cleared).toContain("Domain=.app.test");
  });

  it("leaves a response without session cookies alone", () => {
    const response = clearSessionCookies(
      new Request("https://app.test/", { headers: { cookie: "other=1" } }),
      new Response(null),
      { url: PROJECT },
    );
    expect(response.headers.getSetCookie()).toEqual([]);
    expect(response.headers.get("cache-control")).toBeNull();
  });
});
