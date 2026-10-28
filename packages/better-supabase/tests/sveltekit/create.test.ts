import { describe, expect, it, vi } from "vitest";

import type { SvelteKitHelpers } from "../../src/sveltekit/index.ts";

import { DbException, dbError } from "../../src/core/errors.ts";
import { ok } from "../../src/core/result.ts";
import { createSvelteKit } from "../../src/sveltekit/index.ts";
import {
  countResolutions,
  expiredRequest,
} from "../fixtures/instant-sessions.ts";
import {
  betterSupabase,
  env,
  requestAs,
  signer,
  USER,
} from "../fixtures/test-server.ts";

class Redirect extends Error {
  readonly status: number;
  readonly location: string;
  constructor(status: number, location: string) {
    super(location);
    this.status = status;
    this.location = location;
  }
}

class HttpError extends Error {
  readonly status: number;
  readonly body: { readonly message: string };
  constructor(status: number, body: { readonly message: string }) {
    super(body.message);
    this.status = status;
    this.body = body;
  }
}

const kit: SvelteKitHelpers = {
  redirect: (status, location) => {
    throw new Redirect(status, location);
  },
  error: (status, message) => {
    throw new HttpError(status, { message });
  },
  fail: (status, data) => ({ status, data }),
};

const bsb = createSvelteKit(betterSupabase, {
  env,
  auth: { jwks: signer.jwks },
  prefetchJwks: false,
  kit,
  signIn: "/sign-in",
});

/** Runs the handle hook, then `fn` with the event it filled. */
async function withEvent<T>(
  request: Request,
  fn: (event: { request: Request; locals: object }) => Promise<T>,
): Promise<T> {
  const event = { request, locals: {}, url: new URL(request.url) };
  let out: T | undefined;
  await bsb.handle({
    event,
    resolve: async () => {
      out = await fn(event);

      return new Response(null);
    },
  });

  // SAFETY: resolve ran fn before handle returned.
  return out as T;
}

describe("createSvelteKit", () => {
  it("fills event.locals in handle, and require returns the caller", async () => {
    const request = await requestAs({ role: "member" });
    const caller = await withEvent(request, (event) => bsb.require(event));
    expect(caller.session).toMatchObject({ user: { id: USER } });
    expect(caller.db).toBeDefined();
  });

  it("redirects anonymous callers to signIn and errors on forbidden ones", async () => {
    await expect(
      withEvent(
        await requestAs(undefined, { url: "https://app.test/notes" }),
        (event) => bsb.require(event),
      ),
    ).rejects.toEqual(new Redirect(303, "/sign-in?next=%2Fnotes"));
    await expect(
      withEvent(await requestAs({ role: "member" }), (event) =>
        bsb.require(event, { requireTenant: true }),
      ),
    ).rejects.toBeInstanceOf(HttpError);
  });

  it("require without handle throws a setup error", async () => {
    await expect(
      bsb.require({ request: new Request("https://app.test/"), locals: {} }),
    ).rejects.toThrow(/hooks.server.ts/);
  });

  it("runs form actions into ActionResults and fail()", async () => {
    const save = bsb.action({}, (input) => ok({ input }));
    const form = new FormData();
    form.append("title", "Hello");

    const request = await requestAs(
      { role: "member" },
      { method: "POST", body: form, url: "https://app.test/notes" },
    );

    const result = await withEvent(request, (event) => save(event));
    expect(result).toEqual({
      ok: true,
      data: { input: { title: "Hello" } },
      error: null,
    });

    const refused = await withEvent(
      await requestAs(undefined, { method: "POST", body: new FormData() }),
      (event) => save(event),
    );

    expect(refused).toMatchObject({ status: 401, data: { ok: false } });
  });

  it("maps errors in handleError and registers load dependencies", () => {
    expect(
      bsb.handleError({ error: new DbException(dbError("not_found", "Gone")) }),
    ).toEqual({ message: "Gone", code: "not_found" });
    expect(bsb.handleError({ error: new Error("secret") }).message).toBeTypeOf(
      "string",
    );
    const depends = vi.fn();
    bsb.depends({ depends }, "notes", "projects");
    expect(depends.mock.calls).toEqual([["bsb:notes"], ["bsb:projects"]]);
  });

  it("verifies once for two loaders in one request", async () => {
    const resolutions = countResolutions(betterSupabase);
    const request = await requestAs({ role: "member" });

    const users = await withEvent(request, async (event) => {
      const loaders = [event, event].map(async (scope) => {
        const { snapshot } = await bsb.require(scope);
        const ctx = await bsb.contextFromSession(snapshot);

        return ctx.auth.kind === "user" ? ctx.auth.user.id : null;
      });

      return Promise.all(loaders);
    });

    expect(users).toEqual([USER, USER]);
    expect(resolutions.count()).toBe(1);
    resolutions.stop();
  });

  it("refreshes an expired cookie on a prefetch too", async () => {
    const refresh = vi.fn<typeof fetch>(
      async () => new Response(null, { status: 500 }),
    );

    const prefetching = createSvelteKit(betterSupabase, {
      env,
      auth: { jwks: signer.jwks, fetch: refresh },
      prefetchJwks: false,
      kit,
    });

    const load = async (prefetch: boolean) => {
      const request = await expiredRequest("https://app.test/notes", prefetch);
      const event = { request, locals: {}, url: new URL(request.url) };
      await prefetching.handle({
        event,
        resolve: async () => new Response(null),
      });
    };

    await load(true);
    expect(refresh).toHaveBeenCalledOnce();
  });
});
