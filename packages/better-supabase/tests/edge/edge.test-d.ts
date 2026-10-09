import * as v from "valibot";
import { describe, expectTypeOf, it } from "vitest";

import type { AuthState } from "../../src/auth/resolve.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { createEdge } from "../../src/edge/index.ts";
import { schema } from "../fixtures/generated-camel.ts";

const Claims = v.object({ tenant_id: v.string(), user_role: v.string() });
type Claims = v.InferOutput<typeof Claims>;

describe("betterSupabase.claims(schema) in Edge", () => {
  it("types the claims in the handler context", () => {
    const bs = createEdge(defineSupabase(schema).claims(Claims));
    bs.handler((_request, ctx) => {
      expectTypeOf(ctx.auth).toEqualTypeOf<AuthState<Claims>>();
      if (ctx.auth.kind === "user") {
        expectTypeOf(ctx.auth.claims.tenant_id).toEqualTypeOf<string>();
      }
      return null;
    });
  });

  it("keeps untyped claims for untyped definitions", () => {
    const bs = createEdge(defineSupabase(schema));
    bs.handler((_request, ctx) => {
      expectTypeOf(ctx.auth).toEqualTypeOf<AuthState>();
      return null;
    });
  });
});

describe("bs.routes params", () => {
  it("types ctx.params from each route key", () => {
    const bs = createEdge(defineSupabase(schema));
    bs.routes({
      "GET /orgs/:org/customers/:id": (_request, { params }) => {
        expectTypeOf(params).toEqualTypeOf<{
          readonly org: string;
          readonly id: string;
        }>();
        return null;
      },
      "/files/*": {
        requireTenant: true,
        handler: (_request, { params }) => {
          expectTypeOf(params).toEqualTypeOf<{ readonly "*": string }>();
          return null;
        },
      },
      "GET /me": (_request, { params }) => {
        expectTypeOf(params).toEqualTypeOf<Readonly<Record<never, string>>>();
        return null;
      },
    });
  });
});
