import * as v from "valibot";
import { describe, expect, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { dbError } from "../../src/core/errors.ts";
import { err, ok } from "../../src/core/result.ts";
import { createEdge, defineFunction } from "../../src/edge/index.ts";
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

const bs = createEdge(defineSupabase(schema), {
  env,
  auth: { jwks: signer.jwks as never },
});

const token = await signer.sign({ sub: USER });

const Invite = v.object({ email: v.pipe(v.string(), v.email()) });

const call = (
  serve: (request: Request) => Promise<Response>,
  init: { body?: string; method?: string; auth?: boolean } = {},
) =>
  serve(
    new Request(`${PROJECT_URL}/functions/v1/send-invite`, {
      method: init.method ?? "POST",
      headers: {
        ...(init.auth === false ? {} : { authorization: `Bearer ${token}` }),
        "content-type": "application/json",
      },
      ...(init.body === undefined ? {} : { body: init.body }),
    }),
  );

describe("defineFunction", () => {
  const sendInvite = defineFunction(bs, {
    input: Invite,
    output: v.object({ email: v.string(), by: v.string() }),
    handler: (input, ctx) =>
      ok({
        email: input.email,
        by: ctx.auth.kind === "user" ? ctx.auth.user.id : "nobody",
      }),
  });

  it("runs the handler as the caller with the parsed input", async () => {
    const response = await call(sendInvite, {
      body: JSON.stringify({ email: "ada@acme.test" }),
    });

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ email: "ada@acme.test", by: USER });
  });

  it("answers 422 with the issues for input the schema rejects", async () => {
    const response = await call(sendInvite, {
      body: JSON.stringify({ email: "nope" }),
    });

    expect(response.status).toBe(422);

    const problem = (await response.json()) as {
      kind: string;
      issues: { path?: string[] }[];
    };

    expect(problem.kind).toBe("validation");
    expect(problem.issues[0]?.path).toEqual(["email"]);
  });

  it("answers 400 for a body that is not JSON", async () => {
    const response = await call(sendInvite, { body: "{" });
    expect(response.status).toBe(400);
    expect(await response.json()).toMatchObject({ kind: "invalid_input" });
  });

  it("checks the input of a request without a body", async () => {
    const response = await call(sendInvite, { method: "GET" });
    expect(response.status).toBe(422);
  });

  it("keeps the guard: an anonymous caller gets 401", async () => {
    const response = await call(sendInvite, {
      body: JSON.stringify({ email: "ada@acme.test" }),
      auth: false,
    });

    expect(response.status).toBe(401);
  });

  it("answers 500 when the handler returns data its output rejects", async () => {
    const broken = defineFunction(bs, {
      input: v.optional(v.object({})),
      output: v.object({ id: v.string() }),
      // @ts-expect-error -- the handler returns what the output rejects
      handler: () => ({ id: 1 }),
    });

    const response = await call(broken, { method: "GET" });
    expect(response.status).toBe(500);
    expect(await response.json()).toMatchObject({ kind: "unexpected" });
  });

  it("sends a handler's error, Response or empty result as is", async () => {
    const failing = defineFunction(bs, {
      input: v.optional(v.object({})),
      handler: () => err(dbError("conflict", "Already invited")),
    });

    expect((await call(failing, { body: "" })).status).toBe(409);

    const raw = defineFunction(bs, {
      input: v.optional(v.object({})),
      output: v.object({ id: v.string() }),
      handler: () => new Response("teapot", { status: 418 }),
    });

    expect((await call(raw, { method: "GET" })).status).toBe(418);

    const empty = defineFunction(bs, {
      input: v.optional(v.object({})),
      handler: () => undefined,
    });

    expect((await call(empty, { method: "GET" })).status).toBe(204);
  });

  it("passes the middleware options on", async () => {
    const open = defineFunction(bs, {
      allow: ["anon"],
      input: v.optional(v.object({})),
      handler: (_input, ctx) => ({ kind: ctx.auth.kind, url: ctx.request.url }),
    });

    const response = await call(open, { method: "GET", auth: false });
    expect(await response.json()).toEqual({
      kind: "anon",
      url: `${PROJECT_URL}/functions/v1/send-invite`,
    });
  });
});
