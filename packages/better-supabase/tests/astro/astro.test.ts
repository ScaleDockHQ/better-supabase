import { describe, expect, it } from "vitest";

import { createAstro, createImageService } from "../../src/astro/index.ts";
import { ok } from "../../src/core/result.ts";
import {
  betterSupabase,
  env,
  requestAs,
  signer,
  USER,
} from "../fixtures/test-server.ts";

const bs = createAstro(betterSupabase, {
  env,
  auth: { jwks: signer.jwks as never },
  prefetchJwks: false,
  signIn: "/sign-in",
});

/** Runs the middleware, then `page` with the context it filled. */
async function render(
  request: Request,
  page: (context: { request: Request; locals: object }) => Promise<Response>,
  locals: object = {},
): Promise<Response> {
  const context = { request, locals };
  return bs.onRequest(context, () => page(context));
}

describe("createAstro", () => {
  it("fills locals and guards pages", async () => {
    const response = await render(
      await requestAs({ role: "member" }),
      async (context) => {
        expect(bs.locals(context).session).toMatchObject({
          user: { id: USER },
        });
        const refused = await bs.guard(context, { roles: ["admin"] });
        return refused ?? new Response("page");
      },
    );
    expect(response.status).toBe(403);

    const anonymous = await render(
      await requestAs(undefined, { url: "https://app.test/notes" }),
      async (context) => (await bs.guard(context)) ?? new Response("page"),
    );
    expect(anonymous.status).toBe(303);
    expect(anonymous.headers.get("location")).toBe(
      "https://app.test/sign-in?next=%2Fnotes",
    );

    const allowed = await render(
      await requestAs({ role: "admin" }),
      async (context) =>
        (await bs.guard(context, { roles: ["admin"] })) ?? new Response("page"),
    );
    expect(await allowed.text()).toBe("page");
  });

  it("require returns the caller or throws the refusal", async () => {
    await render(await requestAs({ role: "member" }), async (context) => {
      const caller = await bs.require(context);
      expect(caller.db).toBeDefined();
      await expect(
        bs.require(context, { requireTenant: true }),
      ).rejects.toBeInstanceOf(Response);
      return new Response(null);
    });
  });

  it("runs Actions into ActionResults", async () => {
    const save = bs.action({}, (input) => ok({ input }));
    await render(await requestAs({ role: "member" }), async (context) => {
      expect(await save({ title: "Hi" }, context)).toEqual({
        ok: true,
        data: { input: { title: "Hi" } },
        error: null,
      });
      return new Response(null);
    });
    await render(await requestAs(), async (context) => {
      expect(await save({}, context)).toMatchObject({
        ok: false,
        error: { kind: "unauthorized" },
      });
      return new Response(null);
    });
  });

  it("reads the env from locals.runtime and needs the middleware", async () => {
    await render(await requestAs(), () => Promise.resolve(new Response(null)), {
      runtime: { env: {} },
    });
    expect(() =>
      bs.locals({ request: new Request("https://app.test/"), locals: {} }),
    ).toThrow(/middleware.ts/);
  });
});

describe("createImageService", () => {
  const service = createImageService({
    url: "https://abcdefghijklmnopqrst.supabase.co",
  });
  const avatar =
    "https://abcdefghijklmnopqrst.supabase.co/storage/v1/object/public/avatars/me.png";

  it("renders Storage images at the requested size and quality", () => {
    expect(service.getURL({ src: avatar, width: 64, quality: "high" })).toBe(
      "https://abcdefghijklmnopqrst.supabase.co/storage/v1/render/image/public/avatars/me.png?width=64&quality=80",
    );
    expect(
      service.getURL({ src: { src: avatar }, width: 64, quality: 50 }),
    ).toContain("quality=50");
  });

  it("passes other sources and unsized images through", () => {
    expect(service.getURL({ src: "/local.png", width: 64 })).toBe("/local.png");
    expect(service.getURL({ src: avatar })).toBe(avatar);
  });
});
