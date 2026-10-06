import type { AuthMode, JWTClaims, UserClaims } from "@supabase/server";
import type { PostgresApi } from "@supabase/server/middleware/postgres";
import type { SupabaseClient } from "@supabase/supabase-js";

import {
  type Contributions,
  defineMiddleware,
  pipeline,
} from "@supabase/middleware";
import { withSupabase } from "@supabase/server";
import { withPostgresClient } from "@supabase/server/middleware/postgres";
import { withPostgresAdminClient } from "@supabase/server/middleware/postgres-admin";
import { describe, expectTypeOf, it } from "vitest";

import { createJobs } from "../../src/blocks/jobs/index.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { withBetterSupabase } from "../../src/server/composite.ts";
import { withBlock } from "../../src/server/entries/block.ts";
import { withServerContext } from "../../src/server/entries/context.ts";
import { serverCore } from "../../src/server/entries/core.ts";
import { withSession } from "../../src/server/entries/session.ts";
import { withTenant } from "../../src/server/entries/tenant.ts";
import { createServer } from "../../src/server/server.ts";
import { schema } from "../fixtures/generated-camel.ts";

const betterSupabase = defineSupabase(schema);
const server = createServer(betterSupabase);
const entry = withBetterSupabase(server);
type Keys = Contributions<readonly [typeof entry]>;

describe("withBetterSupabase", () => {
  it("publishes the context, the repositories and the withSupabase keys", () => {
    expectTypeOf<keyof Keys>().toEqualTypeOf<
      | "bs"
      | "jwtClaims"
      | "userClaims"
      | "authMode"
      | "db"
      | "sql"
      | "tenant"
      | "support"
      | "replica"
    >();
    expectTypeOf<Keys["authMode"]>().toEqualTypeOf<AuthMode>();
    expectTypeOf<Keys["userClaims"]>().toEqualTypeOf<UserClaims | null>();
    expectTypeOf<Keys["jwtClaims"]>().toExtend<JWTClaims | null>();
    expectTypeOf<Keys["bs"]>().toHaveProperty("apply");
    expectTypeOf<Keys["sql"]>().toEqualTypeOf<
      ReturnType<typeof server.actingAs> | undefined
    >();
  });

  it("types ctx in a pipeline", () => {
    pipeline([entry], (_req, ctx) => {
      expectTypeOf(ctx.db).toEqualTypeOf<Keys["db"]>();
      expectTypeOf(ctx.db.$client).toEqualTypeOf<SupabaseClient>();
      expectTypeOf(ctx.authMode).toEqualTypeOf<AuthMode>();
      // @ts-expect-error -- `session`, `auth` and `guard` are internal to the composite.
      void ctx.session;
      return Promise.resolve(new Response(null));
    });
  });

  it("composes withPostgresClient downstream", () => {
    pipeline([entry, withPostgresClient()], (_req, ctx) => {
      expectTypeOf(ctx.postgres).not.toBeNever();
      return Promise.resolve(new Response(null));
    });
  });

  it("types a block that withBlock builds from upstream keys", () => {
    pipeline(
      [
        entry,
        withPostgresAdminClient(),
        withBlock("jobs", (ctx: { readonly postgresAdmin: PostgresApi }) =>
          createJobs(ctx.postgresAdmin, {}),
        ),
      ],
      (_req, ctx) => {
        expectTypeOf(ctx.jobs).toHaveProperty("drainRoute");
        expectTypeOf(ctx.db).toEqualTypeOf<Keys["db"]>();
        return Promise.resolve(new Response(null));
      },
    );
  });

  it("rejects a block before the entry that contributes its keys", () => {
    pipeline(
      [
        entry,
        withBlock("jobs", (ctx: { readonly postgresAdmin: PostgresApi }) =>
          createJobs(ctx.postgresAdmin, {}),
        ),
        withPostgresAdminClient(),
      ],
      // @ts-expect-error -- postgresAdmin is not on the context before withPostgresAdminClient.
      (_req: Request, _ctx: object) => Promise.resolve(new Response(null)),
    );
  });

  it("rejects a stack that already has the withSupabase keys", () => {
    pipeline(
      [withSupabase({ auth: "user" }), entry],
      // @ts-expect-error -- middleware-conflict: jwtClaims is already on the context.
      (_req: Request, _ctx: object) => Promise.resolve(new Response(null)),
    );
  });

  it("rejects a key collision with an earlier entry", () => {
    const withDb = defineMiddleware<
      "db",
      undefined,
      Record<never, never>,
      string
    >({ key: "db", run: () => () => Promise.resolve({ db: "taken" }) });
    pipeline(
      [withDb(), entry],
      // @ts-expect-error -- middleware-conflict: key 'db' is already present.
      (_req: Request, _ctx: object) => Promise.resolve(new Response(null)),
    );
  });
});

describe("the single-key entries", () => {
  const core = serverCore(server);

  it("compose in order", () => {
    pipeline(
      [withSession(core), withTenant(core), withServerContext(core)] as const,
      // @ts-expect-error -- middleware-prereq: withServerContext needs `support`.
      (_req: Request, _ctx: object) => Promise.resolve(new Response(null)),
    );
  });

  it("refuse an entry placed before its prerequisite", () => {
    pipeline(
      [withTenant(core), withSession(core)] as const,
      // @ts-expect-error -- middleware-prereq: key 'session' is not yet on the context.
      (_req: Request, _ctx: object) => Promise.resolve(new Response(null)),
    );
  });
});
