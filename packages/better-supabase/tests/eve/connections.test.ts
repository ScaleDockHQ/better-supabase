import { describe, expect, it } from "vitest";

import type { EveSessionContext } from "../../src/eve/index.ts";

import { DbException } from "../../src/core/errors.ts";
import { tenantArgument } from "../../src/eve/index.ts";

const ORG = "22222222-2222-4222-8222-222222222222";

const session = (attributes: Record<string, string>): EveSessionContext => ({
  session: {
    id: "sess_1",
    auth: {
      current: {
        authenticator: "supabase",
        principalType: "user",
        principalId: "user_1",
        attributes,
      },
    },
  },
});

describe("tenantArgument", () => {
  it("fills the named argument with the session's tenant", () => {
    const args = tenantArgument("orgId");

    expect(Object.keys(args)).toEqual(["orgId"]);
    expect(args["orgId"]?.(session({ tenantId: ORG }))).toBe(ORG);
  });

  it("refuses a session without a tenant", () => {
    const resolve = tenantArgument("orgId")["orgId"];

    expect(() => resolve?.(session({}))).toThrow(DbException);
    expect(() => resolve?.(session({}))).toThrow(
      expect.objectContaining({ kind: "forbidden", hint: "TENANT_REQUIRED" }),
    );
  });
});
