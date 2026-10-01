import type { StandardSchemaV1 } from "@standard-schema/spec";

import * as v from "valibot";
import { describe, expect, it } from "vitest";

import { hasEntitlement } from "../../src/auth/entitlements.ts";
import { toSession } from "../../src/auth/view.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { createServer } from "../../src/server/server.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";
import claims from "../fixtures/permdock-claims.json" with { type: "json" };

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};
const signer = await createTestSigner();

interface LooseClaims {
  readonly memberships?: readonly {
    readonly scope?: string;
    readonly id?: string;
    readonly roles: readonly string[];
  }[];
  readonly tenant_id?: string;
  readonly [claim: string]: unknown;
}

type ClaimsSchema<Extra> = StandardSchemaV1<unknown, LooseClaims & Extra> & {
  extend<App extends StandardSchemaV1>(
    app: App,
  ): ClaimsSchema<Extra & StandardSchemaV1.InferOutput<App>>;
};

// A loose stand-in for permdock/supabase's supabaseClaims(): it checks that
// memberships carry roles, passes other claims through, and merges an
// extension's output over the claims, as PermDock's schema does.
function supabaseClaims<Extra = unknown>(
  apps: readonly StandardSchemaV1[] = [],
): ClaimsSchema<Extra> {
  return {
    "~standard": {
      version: 1,
      vendor: "permdock-stand-in",
      validate: async (value) => {
        const record = value as Record<string, unknown>;
        const memberships = record["memberships"];
        if (
          memberships !== undefined &&
          !(
            Array.isArray(memberships) &&
            memberships.every((entry) => Array.isArray(entry?.roles))
          )
        ) {
          return {
            issues: [{ message: "memberships", path: ["memberships"] }],
          };
        }
        let merged = { ...record };
        for (const app of apps) {
          const result = await app["~standard"].validate(value);
          if (result.issues) return { issues: result.issues };
          merged = { ...merged, ...(result.value as object) };
        }
        return { value: merged as LooseClaims & Extra };
      },
    },
    extend: (app) => supabaseClaims([...apps, app]),
  };
}

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
const server = createServer(sb, {
  env,
  auth: { jwks: signer.jwks as never },
});

const sessionFor = async (token: Record<string, unknown>) => {
  const { iat: _iat, exp: _exp, iss: _iss, ...rest } = token;
  const jwt = await signer.sign(rest as { sub: string });
  return (
    await server.context(
      new Request("https://api.test/", {
        headers: { authorization: `Bearer ${jwt}` },
      }),
    )
  ).auth;
};

describe("PermDock claims through sb.claims()", () => {
  it("keeps PermDock's claims and adds the app's", async () => {
    const session = await sessionFor(claims.full);
    expect(session.kind).toBe("user");
    if (session.kind !== "user") return;
    expect(session.claims.memberships).toHaveLength(3);
    expect(session.claims.tenant_id).toBe(claims.full.tenant_id);
    expect(session.claims.datetime_preferences).toEqual({
      timezone: "Europe/Amsterdam",
      week_start: "monday",
      date_format: "dd-MM-yyyy",
      time_format: "24h",
    });
    expect(session.claims["authz_ver"]).toBe(7);
    expect(session.claims["attrs"]).toEqual({
      department: "finance",
      clearance: 2,
    });
  });

  it("reads a portal contact's customer membership", async () => {
    const session = await sessionFor(claims.portalContact);
    expect(session.kind === "user" && session.claims.memberships).toEqual(
      claims.portalContact.memberships,
    );
  });

  it("denies claims either schema rejects", async () => {
    expect(
      await sessionFor({
        ...claims.full,
        datetime_preferences: {
          ...claims.full.datetime_preferences,
          week_start: "tuesday",
        },
      }),
    ).toMatchObject({ kind: "invalid", reason: "claims" });
    expect(
      await sessionFor({ ...claims.portalContact, memberships: [{}] }),
    ).toMatchObject({ kind: "invalid", reason: "claims" });
  });

  it("keeps hasEntitlement working on the extended claims", async () => {
    const org = claims.full.tenant_id;
    const session = toSession(
      await sessionFor({ ...claims.full, features: { [org]: ["exports"] } }),
    );
    expect(hasEntitlement(session, org, "exports")).toBe(true);
    expect(hasEntitlement(session, org, "sso")).toBe(false);
  });
});
