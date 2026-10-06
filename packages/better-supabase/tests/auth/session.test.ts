import {
  clearAuthCookiesAtScopes,
  createServerClient,
  stringFromBase64URL,
} from "@supabase/ssr";
import { describe, expect, it } from "vitest";

import {
  applyCookieWrites,
  type CookieWrite,
  clearSessionAtScopes,
  DEFAULT_SESSION_ENCODING,
  readSession,
  sessionEncoding,
  type StoredSession,
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
    expect(DEFAULT_SESSION_ENCODING).toBe("user-and-tokens");
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
      {
        encode: "tokens-only",
      },
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
    expect(sessionEncoding(tokensOnly)).toBe("tokens-only");

    const full = readSession(
      applyCookieWrites([], writeSession([], NAME, session())),
      NAME,
    )!;
    expect(full.user).toEqual(USER);
    expect(sessionEncoding(full)).toBe("user-and-tokens");
    expect(sessionEncoding(session({ user: null }))).toBe("tokens-only");
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
      {
        encode: "tokens-only",
      },
    );
    expect(writes.filter((write) => write.options.maxAge === 0)).not.toEqual(
      [],
    );
    const after = applyCookieWrites(before, writes);
    expect(after.map((cookie) => cookie.name)).toEqual([NAME]);
    expect(readSession(after, NAME)?.user).toBeUndefined();
  });

  it("is read by @supabase/ssr with encode: tokens-only", async () => {
    const writes = writeSession(
      [],
      NAME,
      session(),
      {},
      {
        encode: "tokens-only",
      },
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

describe("clearSessionAtScopes", () => {
  const existing = [
    { name: `${NAME}.0`, value: "a" },
    { name: `${NAME}.1`, value: "b" },
    { name: `${NAME}-code-verifier`, value: "c" },
    { name: "other", value: "d" },
  ];
  const scopes = [{ domain: ".old.example.com" }, { path: "/app" }];

  it("writes what clearAuthCookiesAtScopes writes", async () => {
    let theirs: CookieWrite[] = [];
    await clearAuthCookiesAtScopes({
      getAll: () => existing,
      setAll: (cookies) => {
        theirs = cookies;
      },
      storageKey: NAME,
      scopes,
    });
    const ours = clearSessionAtScopes(existing, NAME, scopes);
    expect(ours).toEqual(theirs);
    expect(ours.map((write) => [write.name, write.options])).toEqual([
      [
        `${NAME}.0`,
        expect.objectContaining({ domain: ".old.example.com", maxAge: 0 }),
      ],
      [
        `${NAME}.1`,
        expect.objectContaining({ domain: ".old.example.com", maxAge: 0 }),
      ],
      [`${NAME}.0`, expect.objectContaining({ path: "/app", maxAge: 0 })],
      [`${NAME}.1`, expect.objectContaining({ path: "/app", maxAge: 0 })],
    ]);
  });

  it("writes nothing without scopes or session cookies", () => {
    expect(clearSessionAtScopes(existing, NAME, [])).toEqual([]);
    expect(
      clearSessionAtScopes([{ name: "other", value: "d" }], NAME, scopes),
    ).toEqual([]);
    expect(
      clearSessionAtScopes([{ name: NAME, value: "x" }], NAME, [{}]),
    ).toEqual([
      {
        name: NAME,
        value: "",
        options: expect.objectContaining({ path: "/", maxAge: 0 }),
      },
    ]);
  });
});
