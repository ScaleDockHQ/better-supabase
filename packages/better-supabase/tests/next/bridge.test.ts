import type { Entry } from "@supabase/middleware";

import { defineMiddleware } from "@supabase/middleware";
import { NextRequest } from "next/server.js";
import { describe, expect, it, vi } from "vitest";

import { toNextAction } from "../../src/next/bridge.ts";

const jar = vi.hoisted(() => ({ set: vi.fn() }));

vi.mock(import("next/headers.js"), () => ({
  headers: async () =>
    new Headers({ host: "app.test", cookie: "sb-test-auth-token=old" }),
  cookies: async () =>
    Object.assign(new NextRequest("https://app.test/").cookies, {
      set: jar.set,
      delete: vi.fn(),
    }),
}));

const cookieOf = defineMiddleware({
  key: "cookie",
  run: () => async (request) => ({
    cookie: request.headers.get("cookie") ?? "",
  }),
});

const rotates: Entry<Record<never, never>> = (next) => async (request, ctx) => {
  const response = await next(request, ctx);
  const headers = new Headers(response.headers);
  headers.append("set-cookie", "sb-test-auth-token=new; Path=/; HttpOnly");

  return new Response(response.body, { status: response.status, headers });
};

describe("toNextAction", () => {
  it("reads headers() and writes through cookies().set", async () => {
    const action = toNextAction(
      [rotates, cookieOf()],
      async (ctx) => ctx.cookie,
    );

    expect(await action()).toBe("sb-test-auth-token=old");
    expect(jar.set).toHaveBeenCalledWith("sb-test-auth-token", "new", {
      path: "/",
      httpOnly: true,
    });
  });
});
