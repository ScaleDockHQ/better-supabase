import { describe, expect, it } from "vitest";

import { dbError } from "../../src/core/errors.ts";
import { err, ok } from "../../src/core/result.ts";
import {
  createReactRouter,
  type ReactRouterArgs,
} from "../../src/react-router/index.ts";
import {
  betterSupabase,
  env,
  requestAs,
  signer,
  USER,
} from "../fixtures/test-server.ts";

/** A minimal `RouterContextProvider`: a map keyed by context objects. */
function contextProvider(): ReactRouterArgs["context"] {
  const values = new Map<unknown, unknown>();
  return {
    get: (key) => {
      if (!values.has(key)) throw new Error("no value");
      return values.get(key);
    },
    set: (key, value) => {
      values.set(key, value);
    },
  };
}

const bs = createReactRouter(betterSupabase, {
  env,
  auth: { jwks: signer.jwks as never },
  prefetchJwks: false,
  createContext: () => ({}),
  signIn: "/sign-in",
});

/** Runs the middleware, then `fn` inside it. */
async function serve(
  request: Request,
  fn: (args: ReactRouterArgs) => Promise<unknown>,
) {
  const args = { request, context: contextProvider() };
  let out: unknown;
  let thrown: unknown;
  await bs.middleware(args, async () => {
    try {
      out = await fn(args);
    } catch (error) {
      thrown = error;
    }
    return new Response(null);
  });
  // oxlint-disable-next-line typescript/only-throw-error -- rethrows the thrown Response the adapter answers with.
  if (thrown !== undefined) throw thrown;
  return out;
}

describe("createReactRouter", () => {
  it("guards loaders and unwraps their Results", async () => {
    const loader = bs.loader({}, (_args, ctx) =>
      ok({ id: ctx.session.kind === "user" ? ctx.session.user.id : null }),
    );
    expect(await serve(await requestAs({ role: "member" }), loader)).toEqual({
      id: USER,
    });
  });

  it("throws a redirect or Problem Details response for refusals and errors", async () => {
    const loader = bs.loader({}, () => 1);
    const redirect = await serve(
      await requestAs(undefined, { url: "https://app.test/notes" }),
      loader,
    ).catch((error: unknown) => error);
    expect(redirect).toBeInstanceOf(Response);
    expect((redirect as Response).status).toBe(303);

    const failing = bs.loader({}, () => err(dbError("not_found", "Gone")));
    const problem = await serve(
      await requestAs({ role: "member" }),
      failing,
    ).catch((error: unknown) => error);
    expect((problem as Response).status).toBe(404);
  });

  it("runs actions into ActionResults", async () => {
    const action = bs.action({}, (input) => ok(input));
    const request = await requestAs(
      { role: "member" },
      {
        method: "POST",
        body: JSON.stringify({ title: "Hello" }),
        headers: { "content-type": "application/json" },
      },
    );
    expect(await serve(request, action)).toEqual({
      ok: true,
      data: { title: "Hello" },
      error: null,
    });
  });

  it("locals fails without the middleware", () => {
    expect(() =>
      bs.locals({
        request: new Request("https://app.test/"),
        context: contextProvider(),
      }),
    ).toThrow(/middleware/);
  });
});
