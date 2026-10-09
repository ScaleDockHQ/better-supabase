import { call, ORPCError } from "@orpc/server";
import { describe, expect, it } from "vitest";

import { createOrpc } from "../../src/orpc/index.ts";
import {
  betterSupabase,
  env,
  requestAs,
  signer,
  USER,
} from "../fixtures/test-server.ts";

const bs = createOrpc(betterSupabase, {
  env,
  auth: { jwks: signer.jwks as never },
  prefetchJwks: false,
});

const me = bs
  .authed()
  .handler(({ context }) =>
    context.auth.kind === "user" ? context.auth.user.id : null,
  );
const admin = bs
  .authed({
    authorize: (session) =>
      session.kind === "user" &&
      session.claims.app_metadata?.["role"] === "admin",
  })
  .handler(() => "ok");
const scoped = bs.authed({ requireTenant: true }).handler(() => "ok");

const failureOf = (promise: Promise<unknown>) =>
  promise.catch((cause: unknown) => cause);

describe("bs.authed()", () => {
  it("adds the caller's context", async () => {
    const request = await requestAs({ role: "member" });
    expect(await call(me, undefined, { context: { request } })).toBe(USER);
  });

  it("refuses anonymous callers and failed authorize checks", async () => {
    const anonymous = await failureOf(
      call(me, undefined, { context: { request: await requestAs() } }),
    );
    expect(anonymous).toBeInstanceOf(ORPCError);
    expect(anonymous).toMatchObject({ code: "UNAUTHORIZED" });

    expect(
      await call(admin, undefined, {
        context: { request: await requestAs({ role: "admin" }) },
      }),
    ).toBe("ok");
    const member = await failureOf(
      call(admin, undefined, {
        context: { request: await requestAs({ role: "member" }) },
      }),
    );
    expect(member).toMatchObject({
      code: "FORBIDDEN",
      data: { code: "NOT_AUTHORIZED" },
    });
  });

  it("requireTenant refuses callers without a tenant", async () => {
    const failure = await failureOf(
      call(scoped, undefined, {
        context: { request: await requestAs({ role: "member" }) },
      }),
    );
    expect(failure).toMatchObject({
      code: "FORBIDDEN",
      data: { code: "NO_TENANT" },
    });
  });
});
