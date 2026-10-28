import { createServerClient, stringFromBase64URL } from "@supabase/ssr";
import { describe, expect, it } from "vitest";

import type { CookieWrite, StoredSession } from "../../src/auth/session.ts";

import {
  applyCookieWrites,
  readSession,
  writeSession,
} from "../../src/auth/session.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const NAME = "sb-abcdefghijklmnopqrst-auth-token";
const USER = { id: "11111111-1111-4111-8111-111111111111", email: "a@b.test" };

const session = (extra: Partial<StoredSession> = {}): StoredSession => ({
  access_token: "access",
  refresh_token: "refresh",
  expires_at: Math.floor(Date.now() / 1000) + 3600,
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

  it("drops the user object with tokens-only and reads both shapes", () => {
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

    const tokensOnly = readSession(applyCookieWrites([], writes), NAME)!;
    expect(tokensOnly.user).toBeUndefined();
    expect(tokensOnly.access_token).toBe("access");

    const full = readSession(
      applyCookieWrites([], writeSession([], NAME, session())),
      NAME,
    )!;

    expect(full.user).toEqual(USER);
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
    expect(readSession(after, NAME)?.user).toBeUndefined();
  });

  it("reads the longest chunk prefix that parses", () => {
    const big = session({
      user: { ...USER, user_metadata: { bio: "x".repeat(6000) } },
    });

    const chunks = applyCookieWrites([], writeSession([], NAME, big));
    const count = chunks.length;
    expect(count).toBeGreaterThan(1);

    const leftover = [
      ...chunks,
      { name: `${NAME}.${count}`, value: "stale" },
      { name: `${NAME}.${count + 1}`, value: "stale" },
    ];

    expect(readSession(leftover, NAME)?.user).toEqual(big.user);
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
