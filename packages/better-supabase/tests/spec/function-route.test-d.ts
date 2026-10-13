import { describe, expectTypeOf, it } from "vitest";

import type { EdgeHandler } from "../../src/bridges/edge.ts";
import type { TypedFunction } from "../../src/edge/index.ts";
import type { RouteSpec } from "../../src/spec/options.ts";

import { functionRoute } from "../../src/spec/function-route.ts";

declare const typed: TypedFunction<{ email: string }, { sent: boolean }>;
declare const plain: EdgeHandler;

describe("functionRoute", () => {
  it("takes only a defineFunction handler", () => {
    expectTypeOf(
      functionRoute("send-invite", typed),
    ).toEqualTypeOf<RouteSpec>();
    // @ts-expect-error a plain handler carries no schemas
    functionRoute("plain", plain);
  });
});
