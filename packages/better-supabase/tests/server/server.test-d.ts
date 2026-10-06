import { describe, expectTypeOf, it } from "vitest";

import type { Db } from "../../src/core/repository-types.ts";
import type { AsyncResult } from "../../src/core/result.ts";
import type { BetterServer } from "../../src/server/server.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { createServer } from "../../src/server/server.ts";
import { schema } from "../fixtures/generated-camel.ts";

const bs = createServer(defineSupabase(schema));
type Server =
  typeof bs extends BetterServer<infer M, infer F, infer E>
    ? { M: M; F: F; E: E }
    : never;

describe("createServer forContext", () => {
  it("resolves to the same Postgres repositories as actingAs", () => {
    expectTypeOf(bs.forContext({})).toEqualTypeOf<
      AsyncResult<Db<Server["M"], Server["F"], Server["E"], undefined>>
    >();
    expectTypeOf(bs.forContext({}).orThrow()).resolves.toEqualTypeOf<
      ReturnType<typeof bs.actingAs>
    >();
  });

  it("takes claimsFor with sync or async claims", () => {
    createServer(defineSupabase(schema), {
      claimsFor: (userId, context) => {
        expectTypeOf(userId).toEqualTypeOf<string>();
        expectTypeOf(context.tenant).toEqualTypeOf<string | undefined>();
        return { organization_ids: [context.tenant] };
      },
    });
    createServer(defineSupabase(schema), {
      claimsFor: async () => ({ user_role: "admin" }),
    });
  });
});
