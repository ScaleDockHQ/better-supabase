import { describe, expect, it } from "vitest";

import type { StandardSchemaV1 } from "../../src/core/standard.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { FUNCTION_DESCRIPTOR } from "../../src/core/function-contract.ts";
import { createEdge, defineFunction } from "../../src/edge/index.ts";
import { defineApi } from "../../src/spec/api.ts";
import { functionRoute } from "../../src/spec/function-route.ts";
import { schema } from "../fixtures/generated-camel.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";

function described<T>(
  jsonSchema: Record<string, unknown>,
): StandardSchemaV1<T, T> {
  return {
    "~standard": {
      version: 1,
      vendor: "test",
      // SAFETY: the test only sends values of T.
      validate: (value: unknown) => ({ value: value as T }),
      jsonSchema: { input: () => jsonSchema, output: () => jsonSchema },
    },
  } as StandardSchemaV1<T, T>;
}

const betterSupabase = defineSupabase(schema);

const bsb = createEdge(betterSupabase, {
  env: {
    url: PROJECT_URL,
    publishableKey: "sb_publishable_test",
    jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
  },
});

const input = described<{ email: string }>({
  type: "object",
  properties: { email: { type: "string" } },
  required: ["email"],
});

const output = described<{ sent: boolean }>({
  type: "object",
  properties: { sent: { type: "boolean" } },
});

const sendInvite = defineFunction(bsb, {
  input,
  output,
  summary: "Send an invite",
  handler: () => ({ sent: true }),
});

describe("functionRoute", () => {
  it("reads the schemas defineFunction keeps on the handler", () => {
    expect(sendInvite[FUNCTION_DESCRIPTOR]).toEqual({
      input,
      output,
      summary: "Send an invite",
    });
    expect(Object.keys(sendInvite)).not.toContain(FUNCTION_DESCRIPTOR);
    expect(functionRoute("send-invite", sendInvite)).toEqual({
      method: "post",
      path: "/functions/v1/send-invite",
      input,
      output,
      summary: "Send an invite",
    });
  });

  it("documents the function at /functions/v1/<name>", () => {
    const api = defineApi(betterSupabase, {
      info: { title: "CRM", version: "1.0.0" },
      routes: [
        functionRoute("send-invite", sendInvite, {
          summary: "Invite a member",
          tags: ["invites"],
        }),
      ],
    });

    expect(api.diagnostics).toEqual([]);
    expect(api.openapi().document.paths).toMatchObject({
      "/functions/v1/send-invite": {
        post: {
          summary: "Invite a member",
          tags: ["invites"],
          requestBody: {
            required: true,
            content: {
              "application/json": {
                schema: {
                  type: "object",
                  properties: { email: { type: "string" } },
                },
              },
            },
          },
          responses: {
            "200": {
              content: {
                "application/json": {
                  schema: { properties: { sent: { type: "boolean" } } },
                },
              },
            },
          },
        },
      },
    });
  });

  it("takes another method", () => {
    expect(functionRoute("ping", sendInvite, { method: "GET" }).method).toBe(
      "GET",
    );
  });

  it("throws for a handler defineFunction did not build", () => {
    const plain = (() => new Response()) as unknown as typeof sendInvite;
    expect(() => functionRoute("plain", plain)).toThrow(
      'functionRoute("plain") needs a handler from defineFunction',
    );
  });
});
