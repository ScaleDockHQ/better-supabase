import type * as Ssr from "@supabase/ssr";
import type { AuthChangeEvent, Session } from "@supabase/supabase-js";

import { describe, expect, it, vi } from "vitest";

import { createClient } from "../../src/client/index.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { EnvValidationError } from "../../src/env/index.ts";
import { capturingClient } from "../fixtures/client.ts";
import { schema } from "../fixtures/generated-camel.ts";

const browserClients = vi.hoisted((): unknown[][] => []);

vi.mock("@supabase/ssr", async (importOriginal) => {
  const actual = await importOriginal<typeof Ssr>();
  return {
    ...actual,
    createBrowserClient: (url: string, key: string, options: object) => {
      browserClients.push([url, key, options]);
      return actual.createBrowserClient(url, key, options as never);
    },
  };
});

const betterSupabase = defineSupabase(schema);
const URL_BASE = "https://abcdefghijklmnopqrst.supabase.co";
const ANON = {
  actor: { id: "anon", kind: "anon", role: "anon" },
  claims: { role: "anon" },
};

function base64url(text: string): string {
  return btoa(text)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/, "");
}

function token(payload: unknown): string {
  return `${base64url('{"alg":"none"}')}.${base64url(JSON.stringify(payload))}.sig`;
}

function session(
  accessToken: string,
  user: { id: string; email?: string; role?: string },
): Session {
  // SAFETY: snapshotOf reads only access_token and the user's id, email and role.
  return { access_token: accessToken, user } as unknown as Session;
}

type Listener = (event: AuthChangeEvent, session: Session | null) => void;

function setup() {
  const { client, requests } = capturingClient();
  let emit: Listener = () => undefined;
  vi.spyOn(client.auth, "onAuthStateChange").mockImplementation((callback) => {
    emit = (event, value) => void callback(event, value);
    // SAFETY: createClient ignores the subscription it gets back.
    return { data: { subscription: {} } } as never;
  });
  const browser = createClient(betterSupabase, { client });
  return {
    browser,
    client,
    requests,
    emit: (value: Session | null) => {
      emit("SIGNED_IN", value);
    },
  };
}

describe("createClient", () => {
  it("uses the given client and starts loading as anon", () => {
    const { browser, client } = setup();
    expect(browser.supabase).toBe(client);
    expect(browser.betterSupabase).toBe(betterSupabase);
    expect(browser.auth.current()).toEqual({
      status: "loading",
      user: null,
      claims: null,
    });
    expect(browser.db.$context).toEqual(ANON);
    expect(browser.db.$client).toBe(client);
  });

  it("follows the session in the snapshot and the repositories' context", () => {
    const { browser, emit } = setup();
    const claims = {
      sub: "u1",
      role: "authenticated",
      exp: 100,
      app_metadata: { tenant_id: "t1" },
    };
    emit(session(token(claims), { id: "u1", email: "ada@example.test" }));
    expect(browser.auth.current()).toEqual({
      status: "signed-in",
      user: { id: "u1", email: "ada@example.test", role: "authenticated" },
      claims,
    });
    expect(browser.db.$context).toEqual({
      actor: {
        id: "u1",
        kind: "user",
        role: "authenticated",
        email: "ada@example.test",
      },
      claims,
    });

    emit(null);
    expect(browser.auth.current()).toEqual({
      status: "signed-out",
      user: null,
      claims: null,
    });
    expect(browser.db.$context).toEqual(ANON);
  });

  it("falls back to the user's role when the token has none or is unreadable", () => {
    const { browser, emit } = setup();
    for (const accessToken of [
      "opaque",
      "a.%%%.c",
      `a.${base64url("[1]")}.c`,
      `a.${base64url("null")}.c`,
      token({ role: 7 }),
    ]) {
      emit(null);
      emit(session(accessToken, { id: "u1", role: "member" }));
      const current = browser.auth.current();
      expect(current.status).toBe("signed-in");
      expect(current.user).toEqual({ id: "u1", role: "member" });
      expect(browser.db.$context.actor).toEqual({
        id: "u1",
        kind: "user",
        role: "member",
      });
    }
    emit(null);
    emit(session("opaque", { id: "u1" }));
    expect(browser.auth.current()).toEqual({
      status: "signed-in",
      user: { id: "u1" },
      claims: {},
    });
    expect(browser.db.$context).toEqual({
      actor: { id: "u1", kind: "user" },
      claims: {},
    });
  });

  it("reads the user from the claims when tokens-only cookies left no user object", () => {
    const { browser, emit } = setup();
    // auth-js puts a placeholder there that throws on every other property read.
    const missing = new Proxy(
      {},
      {
        get: (_target, property) => {
          if (property === "__isUserNotAvailableProxy") return true;
          throw new Error(`read ${String(property)}`);
        },
      },
    );
    const claims = {
      sub: "u1",
      email: "ada@example.test",
      role: "authenticated",
    };
    emit(session(token(claims), missing as never));
    expect(browser.auth.current()).toEqual({
      status: "signed-in",
      user: { id: "u1", email: "ada@example.test", role: "authenticated" },
      claims,
    });
    emit(session("opaque", missing as never));
    expect(browser.auth.current().status).toBe("signed-out");
  });

  it("carries the impersonator from the act claim", () => {
    const { browser, emit } = setup();
    emit(
      session(token({ act: { kind: "impersonation", sub: "admin-1" } }), {
        id: "u1",
      }),
    );
    expect(browser.db.$context.actor).toEqual({
      id: "u1",
      kind: "user",
      impersonator: "admin-1",
    });
  });

  it("notifies subscribers when the user or a claim changes, not on a refresh", () => {
    const { browser, emit } = setup();
    const listener = vi.fn();
    const unsubscribe = browser.auth.subscribe(listener);
    const user = { id: "u1" };

    emit(session(token({ exp: 1, tenant_id: "t1" }), user));
    const db = browser.db;
    const snapshot = browser.auth.current();
    expect(listener).toHaveBeenCalledTimes(1);

    emit(session(token({ exp: 2, iat: 1, jti: "j", tenant_id: "t1" }), user));
    expect(listener).toHaveBeenCalledTimes(1);
    expect(browser.db).toBe(db);
    expect(browser.auth.current()).toBe(snapshot);

    emit(session(token({ exp: 3, tenant_id: "t2" }), user));
    expect(listener).toHaveBeenCalledTimes(2);
    expect(browser.db).not.toBe(db);
    expect(browser.auth.current().claims).toEqual({ exp: 3, tenant_id: "t2" });

    emit(session(token({ exp: 3, tenant_id: "t2" }), { id: "u2" }));
    expect(listener).toHaveBeenCalledTimes(3);
    expect(browser.auth.current().user?.id).toBe("u2");

    emit(null);
    emit(null);
    expect(listener).toHaveBeenCalledTimes(4);

    unsubscribe();
    emit(session(token({ exp: 3 }), user));
    expect(listener).toHaveBeenCalledTimes(4);
    expect(browser.auth.current().status).toBe("signed-in");
  });

  it("builds query options that run on the current repositories", async () => {
    const { browser, requests } = setup();
    const options = browser.queries.customers.findMany({ select: ["id"] });
    expect(options.queryKey.slice(0, 3)).toEqual([
      "bs",
      "customers",
      "findMany",
    ]);
    const queryFn = options.queryFn as (context: {
      signal: AbortSignal;
    }) => Promise<unknown>;
    await expect(
      queryFn({ signal: new AbortController().signal }),
    ).resolves.toEqual([]);
    expect(requests.map((request) => request.path)).toEqual([
      "/rest/v1/customers",
    ]);
  });

  it("creates a client from env, with cookies or localStorage", () => {
    const env = { url: URL_BASE, publishableKey: "sb_publishable_test" };
    const local = createClient(betterSupabase, { env, storage: "local" });
    expect(local.supabase.storage).toBeDefined();
    expect(local.auth.current().status).toBe("loading");
    const cookies = createClient(betterSupabase, { env });
    expect(cookies.supabase).not.toBe(local.supabase);
    expect(cookies.db.$context).toEqual(ANON);
  });

  it("passes cookies.encode and auth.userStorage to @supabase/ssr", () => {
    const env = { url: URL_BASE, publishableKey: "sb_publishable_test" };
    const userStorage = {
      getItem: () => null,
      setItem: () => undefined,
      removeItem: () => undefined,
    };
    browserClients.length = 0;
    createClient(betterSupabase, { env });
    createClient(betterSupabase, {
      env,
      cookies: { encode: "tokens-only" },
      auth: { userStorage },
    });
    expect(browserClients).toEqual([
      [URL_BASE, "sb_publishable_test", {}],
      [
        URL_BASE,
        "sb_publishable_test",
        { auth: { userStorage }, cookies: { encode: "tokens-only" } },
      ],
    ]);
    const local = createClient(betterSupabase, {
      env,
      storage: "local",
      auth: { userStorage },
    });
    expect(local.auth.current().status).toBe("loading");
  });

  it("needs env or a client, and a valid env", () => {
    expect(() => createClient(betterSupabase)).toThrow(
      "createClient needs `env` ({ url, publishableKey }) or `client`",
    );
    expect(() =>
      createClient(betterSupabase, {
        env: { url: "not a url", publishableKey: "" },
      }),
    ).toThrow(EnvValidationError);
  });
});
