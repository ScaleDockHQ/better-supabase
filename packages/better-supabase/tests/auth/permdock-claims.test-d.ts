import type { StandardSchemaV1 } from "@standard-schema/spec";

import * as v from "valibot";
import { describe, expectTypeOf, it } from "vitest";

import type { EntitlementKey } from "../../src/auth/entitlements.ts";
import type { AuthSession } from "../../src/auth/view.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { schema } from "../fixtures/generated-camel.ts";

// The types of permdock/supabase's supabaseClaims() on PermDock main
// (src/supabase/claims.ts), until permdock 0.1.0 is a devDependency.
type SupabaseMembershipClaim = {
  readonly scope?: string;
  readonly id?: string;
  readonly within?: Readonly<Record<string, string>>;
  readonly roles: readonly string[];
  readonly via?: string;
  readonly expiresAt?: number;
};
type SupabaseClaims = {
  readonly user_role?: string | readonly string[] | null;
  readonly roles?: readonly string[];
  readonly memberships?: readonly SupabaseMembershipClaim[];
  readonly memberships_truncated?: boolean;
  readonly attrs?: Readonly<Record<string, unknown>>;
  readonly authz_ver?: number;
  readonly tenant_id?: string;
  readonly client_id?: string;
  readonly [claim: string]: unknown;
};
type SupabaseClaimsSchema<Extra = unknown> = StandardSchemaV1<
  unknown,
  SupabaseClaims & Extra
> & {
  extend<App extends StandardSchemaV1>(
    app: App,
  ): SupabaseClaimsSchema<Extra & StandardSchemaV1.InferOutput<App>>;
};
declare function supabaseClaims(): SupabaseClaimsSchema;

const sb = defineSupabase(schema).claims(
  supabaseClaims().extend(
    v.object({
      datetime_preferences: v.optional(
        v.object({
          timezone: v.string(),
          week_start: v.picklist(["monday", "sunday"]),
          date_format: v.string(),
          time_format: v.picklist(["12h", "24h"]),
        }),
      ),
      features: v.optional(
        v.record(v.string(), v.array(v.picklist(["exports", "sso"]))),
      ),
    }),
  ),
);
type Claims =
  NonNullable<typeof sb.claimsSchema> extends StandardSchemaV1<unknown, infer C>
    ? C
    : never;

describe("sb.claims(supabaseClaims().extend(app))", () => {
  it("types PermDock's claims and the app's", () => {
    expectTypeOf<Claims["memberships"]>().toEqualTypeOf<
      readonly SupabaseMembershipClaim[] | undefined
    >();
    expectTypeOf<Claims["tenant_id"]>().toEqualTypeOf<string | undefined>();
    expectTypeOf<
      NonNullable<Claims["datetime_preferences"]>["week_start"]
    >().toEqualTypeOf<"monday" | "sunday">();
  });

  it("keeps hasEntitlement's keys from the features claim", () => {
    expectTypeOf<EntitlementKey<Claims>>().toEqualTypeOf<"exports" | "sso">();
    expectTypeOf<AuthSession<Claims>>().not.toBeNever();
  });
});
