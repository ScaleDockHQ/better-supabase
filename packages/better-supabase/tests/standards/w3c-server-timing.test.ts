import { NextRequest } from "next/server.js";
import { describe, expect, it, vi } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import { createNext } from "../../src/next/index.ts";
import { serverTimingValue } from "../../src/next/proxy.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

vi.mock("next/headers.js", () => ({
  headers: () => Promise.resolve(new Headers()),
  cookies: () => Promise.resolve({ set: () => undefined }),
}));
vi.mock("next/cache.js", () => ({
  updateTag: () => undefined,
  revalidateTag: () => undefined,
  cacheTag: () => undefined,
  io: () => Promise.resolve(),
}));

// Server-Timing grammar (WD section 3): `#server-timing-metric`, each
// `metric-name *( OWS ";" OWS server-timing-param )` with `dur=` a number.
const TOKEN = "[!#$%&'*+.^_`|~0-9A-Za-z-]+";
const METRIC = `${TOKEN}(?:;${TOKEN}=(?:${TOKEN}|"[^"]*"))*`;
const HEADER = new RegExp(`^${METRIC}(?:, ${METRIC})*$`);

function metrics(header: string): Map<string, number> {
  return new Map(
    header.split(", ").map((entry) => {
      const [name, ...params] = entry.split(";");
      const dur = params.find((param) => param.startsWith("dur="));
      return [name!, Number(dur?.slice(4))];
    }),
  );
}

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const signer = await createTestSigner();
const bs = createNext(defineSupabase(schema), {
  env: {
    url: PROJECT_URL,
    publishableKey: "sb_publishable_test",
    jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
  },
  auth: { jwks: signer.jwks as never },
});
const page = () =>
  new NextRequest("https://app.test/dashboard", {
    headers: { "sec-fetch-dest": "document" },
  });

describe(`W3C Server Timing (${SPEC_PINS.serverTiming})`, () => {
  it("formats metrics as name;dur=milliseconds", () => {
    const value = serverTimingValue({ "bs-proxy": 1.234, "bs-verify": 0.04 });
    expect(value).toBe("bs-proxy;dur=1.2, bs-verify;dur=0.0");
    expect(value).toMatch(HEADER);
  });

  it("next.proxy({ serverTiming: true }) emits bs-proxy and bs-verify with non-negative durations", async () => {
    const response = await bs.proxy(page(), { serverTiming: true });
    const header = response.headers.get("server-timing")!;
    expect(header).toMatch(HEADER);
    const values = metrics(header);
    expect([...values.keys()]).toEqual(["bs-proxy", "bs-verify"]);
    for (const dur of values.values()) expect(dur).toBeGreaterThanOrEqual(0);
    expect(values.get("bs-proxy")!).toBeGreaterThanOrEqual(
      values.get("bs-verify")!,
    );
  });

  it("appends to metrics the app already set, so both stay in one valid header", async () => {
    const response = await bs.proxy(page(), {
      serverTiming: true,
      after: (res) => {
        res.headers.set("server-timing", 'app;dur=3;desc="render"');
      },
    });
    const header = response.headers.get("server-timing")!;
    expect(header).toMatch(HEADER);
    expect([...metrics(header).keys()]).toEqual([
      "app",
      "bs-proxy",
      "bs-verify",
    ]);
  });

  it("adds no header unless asked", async () => {
    expect((await bs.proxy(page())).headers.has("server-timing")).toBe(false);
  });
});
