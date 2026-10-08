import { describe, expect, it } from "vitest";

import {
  isPrefetch,
  refreshFor,
  shouldCheckSession,
  shouldRefresh,
} from "../../src/server/refresh.ts";

const at = (init: RequestInit = {}, path = "/") =>
  new Request(`https://app.test${path}`, init);

describe("isPrefetch", () => {
  it("reads the router and browser prefetch headers", () => {
    expect(isPrefetch(at({ headers: { "next-router-prefetch": "1" } }))).toBe(
      true,
    );
    expect(isPrefetch(at({ headers: { purpose: "prefetch" } }))).toBe(true);
    expect(
      isPrefetch(at({ headers: { "sec-purpose": "prefetch;prerender" } })),
    ).toBe(true);
    expect(isPrefetch(at())).toBe(false);
  });
});

describe("shouldRefresh", () => {
  it("refreshes page loads and client navigations", () => {
    expect(
      shouldRefresh(at({ headers: { "sec-fetch-dest": "document" } })),
    ).toBe(true);
    expect(shouldRefresh(at({ headers: { rsc: "1" } }))).toBe(true);
    expect(shouldRefresh(at({ headers: { accept: "text/html" } }))).toBe(true);
  });

  it("refreshes form posts and Server Actions, never script fetches", () => {
    expect(
      shouldRefresh(at({ method: "POST", headers: { "next-action": "abc" } })),
    ).toBe(true);
    expect(
      shouldRefresh(
        at({ method: "POST", headers: { "x-sveltekit-action": "true" } }),
      ),
    ).toBe(true);
    expect(
      shouldRefresh(
        at({ method: "POST", headers: { "sec-fetch-dest": "document" } }),
      ),
    ).toBe(true);
    expect(
      shouldRefresh(
        at({
          method: "POST",
          headers: { "content-type": "multipart/form-data; boundary=x" },
        }),
      ),
    ).toBe(true);
    expect(
      shouldRefresh(
        at({ method: "POST", headers: { "content-type": "application/json" } }),
      ),
    ).toBe(false);
    expect(shouldRefresh(at({ headers: { "sec-fetch-dest": "empty" } }))).toBe(
      false,
    );
    expect(shouldRefresh(at())).toBe(false);
  });

  it("skips prefetches", () => {
    expect(
      shouldRefresh(at({ headers: { rsc: "1", "next-router-prefetch": "1" } })),
    ).toBe(false);
  });
});

describe("shouldCheckSession", () => {
  it("checks full page loads and the listed paths", () => {
    expect(
      shouldCheckSession(at({ headers: { "sec-fetch-dest": "document" } })),
    ).toBe(true);
    expect(shouldCheckSession(at({}, "/settings"), ["/settings"])).toBe(true);
    expect(shouldCheckSession(at({}, "/other"), ["/settings"])).toBe(false);
    expect(shouldCheckSession(at({}, "/other"))).toBe(false);
  });

  it("never checks prefetches or mutations", () => {
    expect(
      shouldCheckSession(
        at({ headers: { "sec-fetch-dest": "document", purpose: "prefetch" } }),
      ),
    ).toBe(false);
    expect(
      shouldCheckSession(
        at({ method: "POST", headers: { "sec-fetch-dest": "document" } }),
      ),
    ).toBe(false);
  });
});

describe("refreshFor", () => {
  it("resolves each policy for a request", () => {
    const page = at({ headers: { "sec-fetch-dest": "document" } });
    expect(refreshFor(undefined, page)).toBeUndefined();
    expect(refreshFor(false, page)).toBe(false);
    expect(refreshFor("navigation", page)).toBe(true);
    expect(refreshFor("navigation", at())).toBe(false);
    expect(refreshFor((request) => request.url.endsWith("/"), page)).toBe(true);
  });
});
