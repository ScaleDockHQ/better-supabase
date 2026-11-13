import { beforeEach, describe, expect, it, vi } from "vitest";

import { createSupabase } from "../../src/core/define.ts";
import { createNext } from "../../src/next/index.ts";
import { taintAvailable } from "../../src/next/taint.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { writeSession } from "../fixtures/session-cookies.ts";

const mocks = vi.hoisted(() => ({
  headers: new Headers(),
  taintValue:
    vi.fn<(message: string, lifetime: object, ...v: string[]) => void>(),
  taintObject: vi.fn<(message: string, object: object) => void>(),
}));

vi.mock(import("react"), async (original) => {
  const actual = await original();

  return {
    ...actual,
    // SAFETY: React's stable types omit the experimental taint functions.
    ...({
      experimental_taintUniqueValue: mocks.taintValue,
      experimental_taintObjectReference: mocks.taintObject,
    } as object),
  };
});

vi.mock(import("next/headers.js"), () => ({
  cookies: () =>
    Promise.resolve(
      // SAFETY: the code under test reads only getAll from the cookie jar.
      {
        getAll: () =>
          (mocks.headers.get("cookie") ?? "")
            .split("; ")
            .filter(Boolean)
            .map((pair) => ({
              name: pair.slice(0, pair.indexOf("=")),
              value: decodeURIComponent(pair.slice(pair.indexOf("=") + 1)),
            })),
      } as never,
    ),
  headers: () => Promise.resolve(mocks.headers as never),
}));

vi.mock(import("next/cache.js"), () => ({
  cacheLife: vi.fn(),
  cacheTag: vi.fn(),
  updateTag: vi.fn(),
  revalidateTag: vi.fn(),
  io: () => Promise.resolve(),
}));

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const NAME = "sb-abcdefghijklmnopqrst-auth-token";
const USER = "11111111-1111-4111-8111-111111111111";
const signer = await createTestSigner();

const bsb = createNext(createSupabase(schema), {
  env: {
    url: PROJECT_URL,
    publishableKey: "sb_publishable_test",
    jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
  },
  cacheTags: false,
  auth: { jwks: signer.jwks },
});

beforeEach(() => {
  mocks.taintValue.mockReset();
  mocks.taintObject.mockReset();
});

describe("taint", () => {
  it("sees the React taint API", () => {
    expect(taintAvailable()).toBe(true);
  });

  it("taints the access token, the refresh token and the auth state", async () => {
    const token = await signer.sign({ sub: USER });

    const cookie = writeSession([], NAME, {
      access_token: token,
      refresh_token: "refresh-secret",
      expires_at: Math.floor(Date.now() / 1000) + 3600,
    })
      .map((write) => `${write.name}=${encodeURIComponent(write.value)}`)
      .join("; ");

    mocks.headers = new Headers({ cookie });

    await bsb.context();

    const tainted = mocks.taintValue.mock.calls.map(([, , value]) => value);

    expect(tainted).toContain(token);
    expect(tainted).toContain("refresh-secret");
    expect(mocks.taintObject).toHaveBeenCalledTimes(2);
  });

  it("taints a bearer token without a refresh token", async () => {
    const token = await signer.sign({ sub: USER });
    mocks.headers = new Headers({ authorization: `Bearer ${token}` });

    await bsb.context();

    expect(mocks.taintValue).toHaveBeenCalledOnce();
    expect(mocks.taintValue.mock.calls[0]?.[2]).toBe(token);
  });

  it("taints nothing for a signed-out visitor but the objects", async () => {
    mocks.headers = new Headers();

    await bsb.context();

    expect(mocks.taintValue).not.toHaveBeenCalled();
    expect(mocks.taintObject).toHaveBeenCalledTimes(2);
  });
});
