import type { JWTClaims, UserClaims } from "@supabase/server";

import { describe, expectTypeOf, it } from "vitest";
import { z } from "zod";

import type { AuthState } from "../../src/auth/resolve.ts";
import type { AuthSession } from "../../src/next/index.ts";

import { createBrowser } from "../../src/client/index.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { createNext } from "../../src/next/index.ts";
import { tenant } from "../../src/plugins/tenant/index.ts";
import { createHooks, useSession } from "../../src/react/index.ts";
import { createServer } from "../../src/server/server.ts";
import { schema } from "../fixtures/generated-camel.ts";

const next = createNext(defineSupabase(schema));

describe("next.session", () => {
  it("returns the serializable session union", () => {
    expectTypeOf(next.session()).resolves.toEqualTypeOf<AuthSession>();
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
      "user" | "service" | "anon" | "invalid"
    >();
  });
});

const Claims = z.object({
  tenant_id: z.uuid(),
  app_metadata: z.object({ plan: z.enum(["free", "pro"]) }),
  memberships: z.array(z.object({ scope: z.string(), id: z.string() })),
});
type Claims = z.infer<typeof Claims>;

describe("sb.claims(schema)", () => {
  const sb = defineSupabase(schema).claims(Claims).use(tenant());

  it("types the claims of every session and auth state", async () => {
    const typed = createNext(sb);
    const session = await typed.session();
    if (session.kind === "user") {
      expectTypeOf(session.claims.tenant_id).toEqualTypeOf<string>();
      expectTypeOf(session.claims.app_metadata.plan).toEqualTypeOf<
        "free" | "pro"
      >();
      expectTypeOf(session.claims.sub).toEqualTypeOf<string>();
    }
    const ctx = await createServer(sb).context(new Request("http://x/"));
    expectTypeOf(ctx.auth).toEqualTypeOf<AuthState<Claims>>();
    expectTypeOf(ctx.auth).toExtend<AuthState>();
  });

  it("keeps an untyped session for untyped definitions", () => {
    expectTypeOf(next.session()).resolves.toEqualTypeOf<AuthSession>();
  });

  it("distinguishes token from claims failures", () => {
    const session = {} as AuthSession<Claims>;
    if (session.kind === "invalid") {
      expectTypeOf(session.reason).toEqualTypeOf<"token" | "claims">();
    }
  });

  it("infers claims in createHooks and takes them in useSession", () => {
    const browser = createBrowser(sb);
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

const Profile = z.object({ display_name: z.string() });
type Profile = z.infer<typeof Profile>;

describe("sb.userMetadata(schema)", () => {
  const sb = defineSupabase(schema)
    .claims(Claims)
    .userMetadata(Profile)
    .use(tenant());

  it("types the profile next to the claims, possibly undefined", async () => {
    const session = await createNext(sb).session();
    if (session.kind === "user") {
      expectTypeOf(session.profile).toEqualTypeOf<Profile | undefined>();
      expectTypeOf(session.claims.tenant_id).toEqualTypeOf<string>();
    }
    const ctx = await createServer(sb).context(new Request("http://x/"));
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
    const browser = createBrowser(sb);
    const hooks = createHooks<typeof browser>();
    expectTypeOf(hooks.useSession).returns.toEqualTypeOf<
      AuthSession<Claims, Profile>
    >();
  });

  it("leaves the profile unknown without a schema", async () => {
    const session = await next.session();
    if (session.kind === "user") {
      expectTypeOf(session.profile).toEqualTypeOf<unknown>();
    }
  });
});
