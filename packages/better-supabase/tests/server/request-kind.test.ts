import { describe, expect, it } from "vitest";

import {
  isDocumentLoad,
  isPrefetch,
  refreshFor,
} from "../../src/server/request-kind.ts";

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

describe("isDocumentLoad", () => {
  it("reads sec-fetch-dest first, then accept", () => {
    expect(
      isDocumentLoad(at({ headers: { "sec-fetch-dest": "document" } })),
    ).toBe(true);
    expect(isDocumentLoad(at({ headers: { "sec-fetch-dest": "empty" } }))).toBe(
      false,
    );
    expect(isDocumentLoad(at({ headers: { accept: "text/html" } }))).toBe(true);
    expect(
      isDocumentLoad(at({ headers: { accept: "text/html", rsc: "1" } })),
    ).toBe(false);
    expect(isDocumentLoad(at())).toBe(false);
  });

  it("is never a prefetch or a mutation", () => {
    expect(
      isDocumentLoad(
        at({ headers: { "sec-fetch-dest": "document", purpose: "prefetch" } }),
      ),
    ).toBe(false);
    expect(
      isDocumentLoad(
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
    expect(refreshFor(true, page)).toBe(true);
    expect(refreshFor((request) => request.url.endsWith("/"), page)).toBe(true);
  });
});
