import { createServerClient, stringFromBase64URL } from "@supabase/ssr";
import { afterEach, describe, expect, it, vi } from "vitest";

import type { CookieWrite, StoredSession } from "../../src/auth/session.ts";

import {
  applyCookieWrites,
  ssrSession,
  writeSession,
} from "../../src/auth/session.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const NAME = "sb-abcdefghijklmnopqrst-auth-token";
const USER = { id: "11111111-1111-4111-8111-111111111111", email: "a@b.test" };

const session = (extra: Partial<StoredSession> = {}): StoredSession => ({
  access_token: "access",
  refresh_token: "refresh",
  expires_at: 1_900_000_000,
  expires_in: 3600,
  token_type: "bearer",
  user: USER,
  ...extra,
});

const decoded = (writes: readonly CookieWrite[]): unknown =>
  JSON.parse(
    stringFromBase64URL(
      writes
        .map((write) => write.value)
        .join("")
        .slice("base64-".length),
    ),
  );

describe("session encoding", () => {
  it("keeps the user object by default", () => {
    const writes = writeSession([], NAME, session());
    expect(decoded(writes)).toMatchObject({ user: USER });
    expect(writeSession([], NAME, session(), {}, {})).toEqual(writes);
    expect(
      writeSession([], NAME, session(), {}, { encode: "user-and-tokens" }),
    ).toEqual(writes);
  });

  it("drops the user object with tokens-only", () => {
    const writes = writeSession(
      [],
      NAME,
      session(),
      {},
      { encode: "tokens-only" },
    );

    const stored = decoded(writes);
    expect(stored).not.toHaveProperty("user");
    expect(stored).toMatchObject({
      access_token: "access",
      refresh_token: "refresh",
      token_type: "bearer",
    });
  });

  it("expires the chunks a tokens-only rewrite of a large session no longer uses", () => {
    const big = session({
      user: { ...USER, user_metadata: { bio: "x".repeat(6000) } },
    });

    const before = applyCookieWrites([], writeSession([], NAME, big));
    expect(before.length).toBeGreaterThan(1);

    const writes = writeSession(
      before,
      NAME,
      big,
      {},
      { encode: "tokens-only" },
    );

    expect(writes.filter((write) => write.options.maxAge === 0)).not.toEqual(
      [],
    );
    const after = applyCookieWrites(before, writes);
    expect(after.map((cookie) => cookie.name)).toEqual([NAME]);
  });

  it("is read by @supabase/ssr with encode: tokens-only", async () => {
    const writes = writeSession(
      [],
      NAME,
      session(),
      {},
      { encode: "tokens-only" },
    );

    const client = createServerClient(PROJECT_URL, "sb_publishable_test", {
      cookies: {
        encode: "tokens-only",
        getAll: () => writes.map(({ name, value }) => ({ name, value })),
        setAll: () => undefined,
      },
    });

    const { data } = await client.auth.getSession();
    expect(data.session?.access_token).toBe("access");
    expect(data.session?.refresh_token).toBe("refresh");
  });
});

describe("ssrSession", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("reads both encodings, whole or chunked, once per cookie list", async () => {
    const full = applyCookieWrites([], writeSession([], NAME, session()));

    const tokensOnly = applyCookieWrites(
      [],
      writeSession([], NAME, session(), {}, { encode: "tokens-only" }),
    );

    const chunked = applyCookieWrites(
      [],
      writeSession(
        [],
        NAME,
        session({
          user: { ...USER, user_metadata: { bio: "x".repeat(6000) } },
        }),
      ),
    );

    expect(chunked.length).toBeGreaterThan(1);

    expect(await ssrSession(full, NAME)).toEqual(session());
    expect(await ssrSession(tokensOnly, NAME)).toMatchObject({
      access_token: "access",
    });
    expect(await ssrSession(chunked, NAME)).toMatchObject({
      refresh_token: "refresh",
    });
    expect(ssrSession(full, NAME)).toBe(ssrSession(full, NAME));
    expect(await ssrSession([], NAME)).toBeNull();
  });

  it("returns expiring and expired sessions as stored, without calling Auth", async () => {
    const fetch = vi.spyOn(globalThis, "fetch");
    const now = Math.floor(Date.now() / 1000);

    for (const expiresAt of [now + 30, now - 30]) {
      const cookies = applyCookieWrites(
        [],
        writeSession([], NAME, session({ expires_at: expiresAt })),
      );

      expect(await ssrSession(cookies, NAME)).toMatchObject({
        access_token: "access",
        expires_at: expiresAt,
      });
    }

    expect(fetch).not.toHaveBeenCalled();
  });
});
