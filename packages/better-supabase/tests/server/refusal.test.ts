import { describe, expect, it } from "vitest";

import { DbException, dbError } from "../../src/core/errors.ts";
import {
  errorResponse,
  guardedLocals,
  routeRefusal,
} from "../../src/server/refusal.ts";
import { authAs } from "../fixtures/test-server.ts";

const request = new Request("https://app.test/admin");

describe("routeRefusal", () => {
  it("lets allowed callers through", async () => {
    const auth = await authAs({ role: "admin" });
    expect(await routeRefusal({ bs: { auth } }, request, {})).toBeUndefined();
  });

  it("answers refused callers with Problem Details or a redirect", async () => {
    const anonymous = await authAs();
    const problem = await routeRefusal(
      { bs: { auth: anonymous } },
      request,
      {},
    );
    expect(problem?.status).toBe(401);
    expect(problem?.headers.get("content-type")).toBe(
      "application/problem+json",
    );

    const redirect = await routeRefusal({ bs: { auth: anonymous } }, request, {
      signIn: "/sign-in",
    });
    expect(redirect?.status).toBe(303);
    expect(redirect?.headers.get("location")).toBe(
      "https://app.test/sign-in?next=%2Fadmin",
    );

    const member = await authAs({ role: "member" });
    const forbidden = await routeRefusal({ bs: { auth: member } }, request, {
      requireTenant: true,
    });
    expect(forbidden?.status).toBe(403);
  });
});

describe("errorResponse", () => {
  it("maps DbExceptions and leaves other errors alone", async () => {
    const mapped = errorResponse(
      new DbException(dbError("not_found", "Gone")),
      request,
    );
    expect(mapped?.status).toBe(404);
    expect(await mapped?.json()).toMatchObject({ instance: "/admin" });
    expect(errorResponse(new Error("boom"), request)).toBeUndefined();
  });
});

describe("guardedLocals", () => {
  it("reads bs and tenant, and fails without withBetterSupabase", async () => {
    const auth = await authAs();
    expect(guardedLocals({ bs: { auth }, tenant: "acme" })).toEqual({
      bs: { auth },
      tenant: "acme",
    });
    expect(guardedLocals({ bs: { auth }, tenant: 1 }).tenant).toBeUndefined();
    expect(() => guardedLocals({})).toThrow(/withBetterSupabase/);
  });
});
