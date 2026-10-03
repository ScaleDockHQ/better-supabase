import { call, ORPCError, os } from "@orpc/server";
import * as v from "valibot";
import { describe, expect, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { DbException, dbError } from "../../src/core/errors.ts";
import { err, ok } from "../../src/core/result.ts";
import {
  createOrpc,
  type OrpcRequestContext,
  orpcCode,
} from "../../src/orpc/index.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};
const USER = "11111111-1111-4111-8111-111111111111";
const signer = await createTestSigner();

describe("createOrpc", () => {
  const betterSupabase = defineSupabase(schema);
  const bs = createOrpc(betterSupabase, {
    env,
    auth: { jwks: signer.jwks as never },
  });
  const authed = os.$context<OrpcRequestContext>().use(bs.middleware());

  const me = authed.handler(({ context }) => ({
    id: context.auth.kind === "user" ? context.auth.user.id : null,
    hasDb: typeof context.db.customers.findMany === "function",
  }));
  const rename = authed
    .input(v.object({ id: v.string(), name: v.string() }))
    .handler(({ input }) =>
      input.id === "taken"
        ? bs.unwrap(err(dbError("conflict", "Taken")))
        : bs.unwrap<{ id: string }>(ok({ id: input.id })),
    );
  const thrown = authed.handler(() => {
    throw new DbException(dbError("not_found", "Gone"));
  });

  const request = async (token?: string) =>
    new Request("https://api.test/rpc", {
      headers: token ? { authorization: `Bearer ${token}` } : {},
    });

  it("adds the caller and repositories to context", async () => {
    const token = await signer.sign({ sub: USER });
    expect(
      await call(me, undefined, { context: { request: await request(token) } }),
    ).toEqual({ id: USER, hasDb: true });
  });

  it("rejects anonymous callers with UNAUTHORIZED", async () => {
    const failure = await call(me, undefined, {
      context: { request: await request() },
    }).catch((cause: unknown) => cause);
    expect(failure).toBeInstanceOf(ORPCError);
    expect(failure).toMatchObject({
      code: "UNAUTHORIZED",
      data: { kind: "unauthorized", code: "MISSING_CREDENTIALS" },
    });
  });

  it("maps Results and DbExceptions to ORPCErrors", async () => {
    const context = {
      request: await request(await signer.sign({ sub: USER })),
    };
    expect(await call(rename, { id: "c1", name: "A" }, { context })).toEqual({
      id: "c1",
    });
    await expect(
      call(rename, { id: "taken", name: "A" }, { context }),
    ).rejects.toMatchObject({ code: "CONFLICT" });
    await expect(call(thrown, undefined, { context })).rejects.toMatchObject({
      code: "NOT_FOUND",
      data: { kind: "not_found", detail: "Gone" },
    });
  });

  it("derives codes from the error status", () => {
    expect(orpcCode(dbError("validation", "x", { issues: [] }))).toBe(
      "UNPROCESSABLE_CONTENT",
    );
    expect(orpcCode(dbError("stale", "x"))).toBe("PRECONDITION_FAILED");
    expect(orpcCode(dbError("unexpected", "x"))).toBe("INTERNAL_SERVER_ERROR");
  });
});
