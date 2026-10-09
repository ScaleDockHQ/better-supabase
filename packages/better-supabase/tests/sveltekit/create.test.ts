import { describe, expect, it, vi } from "vitest";

import { DbException, dbError } from "../../src/core/errors.ts";
import { ok } from "../../src/core/result.ts";
import {
  createSvelteKit,
  type SvelteKitHelpers,
} from "../../src/sveltekit/index.ts";
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
  error: (status, body) => {
    throw new HttpError(status, body);
  },
  fail: (status, data) => ({ status, data }),
};

const bs = createSvelteKit(betterSupabase, {
  env,
  auth: { jwks: signer.jwks as never },
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
  await bs.handle({
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
    const caller = await withEvent(request, (event) => bs.require(event));
    expect(caller.session).toMatchObject({ user: { id: USER } });
    expect(caller.db).toBeDefined();
  });

  it("redirects anonymous callers to signIn and errors on forbidden ones", async () => {
    await expect(
      withEvent(
        await requestAs(undefined, { url: "https://app.test/notes" }),
        (event) => bs.require(event),
      ),
    ).rejects.toEqual(new Redirect(303, "/sign-in?next=%2Fnotes"));
    await expect(
      withEvent(await requestAs({ role: "member" }), (event) =>
        bs.require(event, { requireTenant: true }),
      ),
    ).rejects.toBeInstanceOf(HttpError);
  });

  it("require without handle throws a setup error", async () => {
    await expect(
      bs.require({ request: new Request("https://app.test/"), locals: {} }),
    ).rejects.toThrow(/hooks.server.ts/);
  });

  it("runs form actions into ActionResults and fail()", async () => {
    const save = bs.action({}, (input) => ok({ input }));
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
      bs.handleError({ error: new DbException(dbError("not_found", "Gone")) }),
    ).toEqual({
      message: "Gone",
      code: "not_found",
    });
    expect(bs.handleError({ error: new Error("secret") }).message).toBeTypeOf(
      "string",
    );
    const depends = vi.fn();
    bs.depends({ depends }, "notes", "projects");
    expect(depends.mock.calls).toEqual([["bs:notes"], ["bs:projects"]]);
  });
});
