import { describe, expect, test } from "vitest";

import {
  DEFAULT_SEAL_INFO,
  isFlow,
  isOAuthSession,
  needsRefresh,
  OAuthError,
  pkcePair,
  randomToken,
  seal,
  unseal,
} from "../../../src/create/oauth/index.ts";
import * as supabase from "../../../src/create/supabase/index.ts";

const SECRET = "a-cookie-secret-of-at-least-32-characters";

const session = { accessToken: "a", refreshToken: "r", expiresAt: 1000 };

describe("seal and unseal", () => {
  test("round-trip with a custom info", async () => {
    const sealed = await seal(session, SECRET, "app vercel session");

    await expect(
      unseal(sealed, SECRET, isOAuthSession, "app vercel session"),
    ).resolves.toStrictEqual(session);
  });

  test("a value sealed with one info doesn't open with another", async () => {
    const sealed = await seal(session, SECRET, "app vercel session");

    await expect(
      unseal(sealed, SECRET, isOAuthSession, "app github session"),
    ).resolves.toBeUndefined();

    await expect(
      unseal(sealed, SECRET, isOAuthSession),
    ).resolves.toBeUndefined();
  });

  test("the default info opens cookies the Supabase helpers sealed", async () => {
    const sealed = await supabase.seal(session, SECRET);

    await expect(
      unseal(sealed, SECRET, isOAuthSession, DEFAULT_SEAL_INFO),
    ).resolves.toStrictEqual(session);
  });
});

describe("isOAuthSession", () => {
  test("accepts a session without a refresh token", () => {
    expect(isOAuthSession({ accessToken: "a", expiresAt: 1 })).toBe(true);
  });

  test("rejects a wrong shape", () => {
    expect(isOAuthSession({ accessToken: "a" })).toBe(false);
    expect(
      isOAuthSession({ accessToken: "a", expiresAt: 1, refreshToken: 2 }),
    ).toBe(false);
  });
});

describe("the Supabase aliases", () => {
  test("re-export the same functions", () => {
    expect(supabase.isSession).toBe(isOAuthSession);
    expect(supabase.isFlow).toBe(isFlow);
    expect(supabase.needsRefresh).toBe(needsRefresh);
    expect(supabase.OAuthError).toBe(OAuthError);
    expect(supabase.pkcePair).toBe(pkcePair);
    expect(supabase.randomToken).toBe(randomToken);
    expect(supabase.seal).toBe(seal);
    expect(supabase.unseal).toBe(unseal);
  });
});
