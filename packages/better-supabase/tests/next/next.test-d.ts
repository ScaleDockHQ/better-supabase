import type { JWTClaims, UserClaims } from "@supabase/server";

import * as v from "valibot";
import { describe, expectTypeOf, it } from "vitest";

import type { AuthState } from "../../src/auth/resolve.ts";
import type { ActionResult, AuthSession } from "../../src/next/index.ts";
import type { ActionInputOf } from "../../src/react/index.ts";

import { createClient } from "../../src/client/index.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { dbError } from "../../src/core/errors.ts";
import { AsyncResult, err, ok } from "../../src/core/result.ts";
import { createNext } from "../../src/next/index.ts";
import { tenant } from "../../src/plugins/tenant/index.ts";
import { createHooks, useSession } from "../../src/react/index.ts";
import { createServer } from "../../src/server/server.ts";
import { schema } from "../fixtures/generated-camel.ts";

const bs = createNext(defineSupabase(schema));

describe("next.session", () => {
  it("returns the serializable session union", () => {
    expectTypeOf(bs.session()).resolves.toEqualTypeOf<AuthSession>();
    expectTypeOf(useSession).returns.toEqualTypeOf<AuthSession>();
  });

  it("narrows to claims only for users and never exposes the token", () => {
    const session = {} as AuthSession;
    if (session.kind === "user") {
      expectTypeOf(session.claims).toEqualTypeOf<JWTClaims>();
      expectTypeOf(session.user).toEqualTypeOf<UserClaims>();
      expectTypeOf(session).not.toHaveProperty("token");
    }
    expectTypeOf<AuthSession["kind"]>().toEqualTypeOf<
      "user" | "service" | "apiKey" | "anon" | "invalid"
    >();
  });
});

const Claims = v.object({
  tenant_id: v.pipe(v.string(), v.uuid()),
  app_metadata: v.object({ plan: v.picklist(["free", "pro"]) }),
  memberships: v.array(v.object({ scope: v.string(), id: v.string() })),
});
type Claims = v.InferOutput<typeof Claims>;

describe("betterSupabase.claims(schema)", () => {
  const betterSupabase = defineSupabase(schema).claims(Claims).use(tenant());

  it("types the claims of every session and auth state", async () => {
    const typed = createNext(betterSupabase);
    const session = await typed.session();
    if (session.kind === "user") {
      expectTypeOf(session.claims.tenant_id).toEqualTypeOf<string>();
      expectTypeOf(session.claims.app_metadata.plan).toEqualTypeOf<
        "free" | "pro"
      >();
      expectTypeOf(session.claims.sub).toEqualTypeOf<string>();
    }
    const ctx = await createServer(betterSupabase).context(
      new Request("http://x/"),
    );
    expectTypeOf(ctx.auth).toEqualTypeOf<AuthState<Claims>>();
    expectTypeOf(ctx.auth).toExtend<AuthState>();
  });

  it("keeps an untyped session for untyped definitions", () => {
    expectTypeOf(bs.session()).resolves.toEqualTypeOf<AuthSession>();
  });

  it("distinguishes token, claims and actor failures", () => {
    const session = {} as AuthSession<Claims>;
    if (session.kind === "invalid") {
      expectTypeOf(session.reason).toEqualTypeOf<
        "token" | "claims" | "actor"
      >();
    }
    if (session.kind === "user") {
      expectTypeOf(session.actor?.kind).toEqualTypeOf<
        "oauth-client" | "support" | "impersonation" | undefined
      >();
      expectTypeOf(session.delegation?.scopes).toEqualTypeOf<
        readonly string[] | undefined
      >();
    }
  });

  it("infers claims in createHooks and takes them in useSession", () => {
    const browser = createClient(betterSupabase);
    const hooks = createHooks<typeof browser>();
    expectTypeOf(hooks.useSession).returns.toEqualTypeOf<AuthSession<Claims>>();
    expectTypeOf(useSession<Claims>()).toEqualTypeOf<AuthSession<Claims>>();
  });

  it("types tenant claim paths", () => {
    tenant<Claims>({ claim: "tenant_id" });
    tenant<Claims>({ claim: ["tenant_id", "app_metadata.plan"] });
    // @ts-expect-error not a string claim
    tenant<Claims>({ claim: "memberships" });
    // @ts-expect-error unknown claim
    tenant<Claims>({ claim: "org_id" });
    tenant({ claim: "anything.goes" });
  });
});

const Profile = v.object({ display_name: v.string() });
type Profile = v.InferOutput<typeof Profile>;

describe("betterSupabase.userMetadata(schema)", () => {
  const betterSupabase = defineSupabase(schema)
    .claims(Claims)
    .userMetadata(Profile)
    .use(tenant());

  it("types the profile next to the claims, possibly undefined", async () => {
    const session = await createNext(betterSupabase).session();
    if (session.kind === "user") {
      expectTypeOf(session.profile).toEqualTypeOf<Profile | undefined>();
      expectTypeOf(session.claims.tenant_id).toEqualTypeOf<string>();
    }
    const ctx = await createServer(betterSupabase).context(
      new Request("http://x/"),
    );
    expectTypeOf(ctx.auth).toEqualTypeOf<AuthState<Claims, Profile>>();
  });

  it("keeps the profile through claims() and use() in either order", () => {
    const later = defineSupabase(schema)
      .userMetadata(Profile)
      .use(tenant())
      .claims(Claims);
    expectTypeOf(createNext(later).session()).resolves.toEqualTypeOf<
      AuthSession<Claims, Profile>
    >();
  });

  it("infers the profile in createHooks", () => {
    const browser = createClient(betterSupabase);
    const hooks = createHooks<typeof browser>();
    expectTypeOf(hooks.useSession).returns.toEqualTypeOf<
      AuthSession<Claims, Profile>
    >();
  });

  it("leaves the profile unknown without a schema", async () => {
    const session = await bs.session();
    if (session.kind === "user") {
      expectTypeOf(session.profile).toEqualTypeOf<unknown>();
    }
  });
});

describe("next.action", () => {
  it("keeps the data type when one path returns err()", () => {
    const action = bs.action({}, async () => {
      if (Math.random() > 0.5) return err(dbError("forbidden", "no"));
      return ok({ token: "t" });
    });
    expectTypeOf(action).returns.resolves.toEqualTypeOf<
      ActionResult<{ token: string }>
    >();
  });

  it("unwraps an AsyncResult and passes plain values through", () => {
    const fromResult = bs.action(
      {},
      () => new AsyncResult(Promise.resolve(ok(1))),
    );
    expectTypeOf(fromResult).returns.resolves.toEqualTypeOf<
      ActionResult<number>
    >();
    const plain = bs.action({}, () => "done" as const);
    expectTypeOf(plain).returns.resolves.toEqualTypeOf<ActionResult<"done">>();
  });
});

describe("authorize and requireTenant", () => {
  it("narrows ctx.tenant to a string only with requireTenant", () => {
    bs.action({ requireTenant: true }, (_input, ctx) => {
      expectTypeOf(ctx.tenant).toEqualTypeOf<string>();
      expectTypeOf(ctx.session).toEqualTypeOf<AuthSession>();
    });
    bs.action({}, (_input, ctx) => {
      expectTypeOf(ctx.tenant).toEqualTypeOf<string | undefined>();
    });
    bs.action(
      {
        input: v.object({ id: v.string() }),
        authorize: (session, input) => {
          expectTypeOf(session).toEqualTypeOf<AuthSession>();
          expectTypeOf(input).toEqualTypeOf<{ id: string }>();
          return true;
        },
      },
      () => undefined,
    );
    bs.route(
      (_request, ctx) => {
        expectTypeOf(ctx.tenant).toEqualTypeOf<string>();
      },
      { requireTenant: true },
    );
    expectTypeOf(bs.require({ requireTenant: true }))
      .resolves.toHaveProperty("tenant")
      .toEqualTypeOf<string>();
  });

  it("types bs.cached tables by the schema", () => {
    void bs.cached({ tables: ["customers"], id: "c1" });
    // @ts-expect-error not a table
    void bs.cached({ tables: ["nope"] });
  });
});

describe("ActionInputOf", () => {
  it("drops FormData from a schema action's input", () => {
    const save = bs.action(
      { input: v.object({ id: v.string() }) },
      () => "saved" as const,
    );
    expectTypeOf<ActionInputOf<Parameters<typeof save>[0]>>().toEqualTypeOf<{
      id: string;
    }>();
    expectTypeOf<ActionInputOf<FormData>>().toEqualTypeOf<FormData>();
  });
});
