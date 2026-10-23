import * as v from "valibot";
import { describe, expectTypeOf, it } from "vitest";

import type { AuthState } from "../../src/auth/resolve.ts";
import type { BucketClient } from "../../src/storage/index.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { createEdge } from "../../src/edge/index.ts";
import { defineBucket } from "../../src/storage/index.ts";
import { schema } from "../fixtures/generated-camel.ts";

const Claims = v.object({ tenant_id: v.string(), user_role: v.string() });

type Claims = v.InferOutput<typeof Claims>;

describe("betterSupabase.claims(schema) in Edge", () => {
  it("types the claims in the handler context", () => {
    const bsb = createEdge(defineSupabase(schema).claims(Claims));
    bsb.handler((_request, ctx) => {
      expectTypeOf(ctx.auth).toEqualTypeOf<AuthState<Claims>>();

      if (ctx.auth.kind === "user") {
        expectTypeOf(ctx.auth.claims.tenant_id).toEqualTypeOf<string>();
      }

      return null;
    });
  });

  it("keeps untyped claims for untyped definitions", () => {
    const bsb = createEdge(defineSupabase(schema));
    bsb.handler((_request, ctx) => {
      expectTypeOf(ctx.auth).toEqualTypeOf<AuthState>();

      return null;
    });
  });
});

describe("bsb.routes params", () => {
  it("types ctx.params from each route key", () => {
    const bsb = createEdge(defineSupabase(schema));
    bsb.routes({
      "GET /orgs/:org/customers/:id": (_request, { params }) => {
        expectTypeOf(params).toEqualTypeOf<{
          readonly org: string;
          readonly id: string;
        }>();

        return null;
      },
      "/files/*": {
        requireOrganization: true,
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

describe("betterSupabase.buckets() in Edge", () => {
  it("types db.$buckets in handlers and routes", () => {
    const logos = defineBucket({ id: "logos", path: "{userId}/logo.webp" });
    const bsb = createEdge(defineSupabase(schema).buckets({ logos }));

    type Logos = BucketClient<"{userId}/logo.webp", "logos">;

    bsb.handler((_request, ctx) => {
      expectTypeOf(ctx.db.$buckets.logos).toEqualTypeOf<Logos>();

      return null;
    });
    bsb.routes({
      "GET /logo": (_request, ctx) => {
        expectTypeOf(ctx.db.$buckets.logos).toEqualTypeOf<Logos>();

        return null;
      },
    });
  });
});
