import { describe, expect, it } from "vitest";

import { DbException, dbError } from "../../src/core/errors.ts";
import { guard, problemOnError, toElysia } from "../../src/elysia/index.ts";
import { withBetterSupabase } from "../../src/server/composite.ts";
import { requestAs, server } from "../fixtures/test-server.ts";

describe("elysia guard and problemOnError", () => {
  const bridge = toElysia([
    withBetterSupabase(server, { allow: ["user", "anon"] }),
  ]);
  const admin = guard(bridge, { allow: ["user"], signIn: "/sign-in" });
  const onError = problemOnError();
  const fetch = bridge.wrap(async (request) => {
    try {
      const refused = await admin({ request });
      if (refused) return refused;
      if (request.url.endsWith("/thrown")) {
        throw new DbException(dbError("not_found", "Gone"));
      }
      return new Response("secret");
    } catch (error) {
      return onError({ error, request }) ?? new Response(null, { status: 500 });
    }
  });

  it("lets users through and redirects anonymous callers", async () => {
    const allowed = await fetch(await requestAs({ role: "admin" }));
    expect(await allowed.text()).toBe("secret");

    const refused = await fetch(
      await requestAs(undefined, { url: "https://app.test/admin" }),
    );
    expect(refused.status).toBe(303);
    expect(refused.headers.get("location")).toContain("/sign-in?next=%2Fadmin");
  });

  it("maps thrown DbExceptions to Problem Details", async () => {
    const thrown = await fetch(
      await requestAs({ role: "admin" }, { url: "https://app.test/thrown" }),
    );
    expect(thrown.status).toBe(404);
    expect(thrown.headers.get("content-type")).toBe("application/problem+json");
    expect(
      onError({
        error: new Error("boom"),
        request: new Request("https://app.test/"),
      }),
    ).toBeUndefined();
  });

  it("fails closed for a request that skipped the bridge", async () => {
    expect(() => admin({ request: new Request("https://app.test/") })).toThrow(
      /toElysia/,
    );
  });
});
