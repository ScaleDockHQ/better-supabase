import { PostgrestClient } from "@supabase/postgrest-js";
import { createContextClient } from "@supabase/server/core";
import { clearAuthCookiesAtScopes } from "@supabase/ssr";
import { AuthSessionMissingError, createClient } from "@supabase/supabase-js";
import { describe, expect, it, vi } from "vitest";

/**
 * Upstream behaviours a better-supabase workaround depends on. Each title names
 * the filed issue and the workaround. When a case fails, the fix has shipped:
 * remove the workaround, then this case, instead of updating the assertion.
 */

const PROJECT_URL = "https://project.supabase.co";
const KEY = "sb_publishable_test";

interface Call {
  readonly url: string;
  readonly init: RequestInit | undefined;
}

function recordingFetch(response: () => Response): {
  readonly calls: Call[];
  readonly fetch: typeof fetch;
} {
  const calls: Call[] = [];

  return {
    calls,
    fetch: (input, init) => {
      calls.push({
        url: input instanceof Request ? input.url : String(input),
        init,
      });

      return Promise.resolve(response());
    },
  };
}

function json(body: unknown, status = 200): Response {
  return Response.json(body, { status });
}

function clientWith(fake: typeof fetch): ReturnType<typeof createClient> {
  return createClient(PROJECT_URL, KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
    global: { fetch: fake },
  });
}

describe("upstream behaviours behind our workarounds", () => {
  it("postgrest-js rpc GET sends an object argument as [object Object] (supabase-js#2895, queryArgs in core/postgrest-executor.ts)", async () => {
    const { calls, fetch } = recordingFetch(() => json([]));
    const postgrest = new PostgrestClient(`${PROJECT_URL}/rest/v1`, { fetch });

    await postgrest.rpc("search", { filter: { tag: "a" } }, { get: true });

    expect(new URL(calls[0]?.url ?? "").searchParams.get("filter")).toBe(
      "[object Object]",
    );
  });

  it("realtime-js channel() returns the existing channel and ignores new params (supabase-js#2896, the refcount in realtime/channels.ts)", () => {
    const client = clientWith(recordingFetch(() => json({})).fetch);

    const first = client.channel("room", {
      config: { presence: { key: "a" } },
    });

    const second = client.channel("room", {
      config: { presence: { key: "b" } },
    });

    expect(second).toBe(first);
    expect(second.params.config.presence?.key).toBe("a");
  });

  it("storage-js upload passes no signal to fetch (supabase-js#2898, abortable() in storage/connect.ts)", async () => {
    const { calls, fetch } = recordingFetch(() =>
      json({ Id: "1", Key: "bucket/a.txt" }),
    );

    const client = clientWith(fetch);
    await client.storage.from("bucket").upload("a.txt", new Blob(["a"]));

    const upload = calls.find((call) =>
      call.url.includes("/storage/v1/object/"),
    );

    expect(upload).toBeDefined();
    expect(upload?.init?.signal ?? undefined).toBeUndefined();
  });

  it("auth-js maps a 403 session_not_found to AuthSessionMissingError with status 400 (supabase-js#2892, auth/ended.ts)", async () => {
    const { fetch } = recordingFetch(() =>
      json(
        {
          code: "session_not_found",
          error_code: "session_not_found",
          msg: "gone",
        },
        403,
      ),
    );

    const client = clientWith(fetch);
    const { error } = await client.auth.getUser("token");

    expect(error).toBeInstanceOf(AuthSessionMissingError);
    expect(error?.status).toBe(400);
    expect(error?.code).toBeUndefined();
  });

  it("ssr clearAuthCookiesAtScopes calls setAll with no cache headers (ssr#316, NO_STORE in auth/ssr-client.ts)", async () => {
    const setAll = vi.fn();
    const storageKey = "sb-project-auth-token";

    await clearAuthCookiesAtScopes({
      getAll: () => [{ name: storageKey, value: "v" }],
      scopes: [{ domain: ".example.com" }],
      setAll,
      storageKey,
    });

    expect(setAll).toHaveBeenCalledWith(expect.any(Array), {});
  });

  it("@supabase/server createContextClient builds an auth client (server#202, informational: server/server.ts builds context clients on first use)", () => {
    const client = createContextClient({
      auth: { token: "token" },
      env: { publishableKeys: { default: KEY }, url: PROJECT_URL },
    });

    expect(typeof client.auth.getSession).toBe("function");
  });
});
