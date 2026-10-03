import addFormats from "ajv-formats";
import Ajv2020 from "ajv/dist/2020.js";
import { Hono } from "hono";
import { describe, expect, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import {
  type DbError,
  type DbErrorKind,
  dbError,
  statusOf,
} from "../../src/core/errors.ts";
import {
  fromProblem,
  isProblem,
  PROBLEM_CONTENT_TYPE,
  problemResponse,
  toProblem,
} from "../../src/core/problem.ts";
import { err } from "../../src/core/result.ts";
import { createEdge } from "../../src/edge/index.ts";
import { type HonoEnv, createHono } from "../../src/hono/index.ts";
import { PROBLEM_SCHEMA } from "../../src/openapi/index.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import {
  type Functions,
  type Models,
  schema,
} from "../fixtures/generated-camel.ts";

const KINDS: readonly DbErrorKind[] = [
  "not_found",
  "unauthorized",
  "forbidden",
  "conflict",
  "foreign_key",
  "check",
  "not_null",
  "exclusion",
  "invalid_input",
  "invalid_value",
  "raised",
  "timeout",
  "serialization",
  "network",
  "aborted",
  "invalid_request",
  "validation",
  "multiple_rows",
  "stale",
  "rate_limited",
  "unexpected",
];

const sample = (kind: DbErrorKind): DbError =>
  kind === "validation"
    ? dbError("validation", "Invalid", {
        issues: [{ message: "Required", path: ["name"] }],
      })
    : dbError(kind, `A ${kind} error`);

const ajv = new Ajv2020({ strict: false });
addFormats(ajv);
const validProblem = ajv.compile(PROBLEM_SCHEMA);

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};
const signer = await createTestSigner();
const betterSupabase = defineSupabase(schema);

describe("RFC 9457 Problem Details", () => {
  it.each(KINDS)(
    "%s maps to a problem with type, title and the HTTP status (section 3.1)",
    (kind) => {
      const problem = toProblem(sample(kind), { instance: "/api/x" });
      expect(validProblem(problem)).toBe(true);
      expect(problem.status).toBe(statusOf(kind));
      expect(problem.type).toMatch(
        /^https:\/\/bettersupabase\.com\/problems\/[a-z-]+$/,
      );
      expect(problem.title).toMatch(/\S/);
      expect(problem.instance).toBe("/api/x");
      expect(isProblem(problem)).toBe(true);
    },
  );

  it("uses one title per type, so the title stays the same for every occurrence (section 3.1.3)", () => {
    const titles = new Map<string, string>();
    for (const kind of KINDS) {
      const one = toProblem(sample(kind));
      const two = toProblem({
        ...sample(kind),
        message: "different occurrence",
      });
      expect(two.title).toBe(one.title);
      titles.set(one.type, one.title);
    }
    expect(titles.size).toBe(KINDS.length);
  });

  it("the response has application/problem+json and the same status as the body (section 3.1.2)", async () => {
    for (const kind of KINDS) {
      const response = problemResponse(sample(kind));
      expect(response.headers.get("content-type")).toBe(PROBLEM_CONTENT_TYPE);
      expect(PROBLEM_CONTENT_TYPE).toBe("application/problem+json");
      expect(((await response.json()) as { status: number }).status).toBe(
        response.status,
      );
    }
  });

  it("hides details of internal errors unless exposed (section 5, security considerations)", () => {
    for (const kind of ["unexpected", "network", "invalid_request"] as const) {
      expect(
        toProblem(dbError(kind, "select * from secrets")),
      ).not.toHaveProperty("detail");
      expect(toProblem(dbError(kind, "x"), { expose: true }).detail).toBe("x");
    }
  });

  it("round-trips through fromProblem, and unknown kinds fall back to unexpected (extension members, section 3.2)", () => {
    for (const kind of KINDS)
      expect(fromProblem(toProblem(sample(kind))).kind).toBe(kind);
    expect(
      fromProblem({
        type: "about:blank",
        title: "Teapot",
        status: 418,
        kind: "teapot" as DbErrorKind,
      }).kind,
    ).toBe("unexpected");
  });

  it("the Hono and edge adapters answer errors with Problem Details", async () => {
    const hono = createHono(betterSupabase, {
      env,
      auth: { jwks: signer.jwks as never },
    });
    const app = new Hono<HonoEnv<Models, Functions, unknown>>()
      .onError(hono.onError)
      .use("/api/*", hono.middleware())
      .get(
        "/api/x",
        hono.handler(() => err(dbError("conflict", "Taken"))),
      );
    const edge = createEdge(betterSupabase, {
      env,
      auth: { jwks: signer.jwks as never },
    });
    const serve = edge.handler(() => err(dbError("stale", "Changed")));
    const token = await signer.sign({
      sub: "11111111-1111-4111-8111-111111111111",
    });
    const responses = [
      await app.request("/api/x"),
      await app.request("/api/x", {
        headers: { authorization: `Bearer ${token}` },
      }),
      await serve(
        new Request("https://fn.test/x", {
          headers: { authorization: `Bearer ${token}` },
        }),
      ),
    ];
    expect(responses.map((response) => response.status)).toEqual([
      401, 409, 412,
    ]);
    for (const response of responses) {
      expect(response.headers.get("content-type")).toBe(PROBLEM_CONTENT_TYPE);
      const body = await response.json();
      expect(validProblem(body)).toBe(true);
      expect(body).toMatchObject({ status: response.status });
    }
  });
});
