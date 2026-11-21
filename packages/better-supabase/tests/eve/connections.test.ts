import { describe, expect, it, vi } from "vitest";

import type { CredentialProvider } from "../../src/credentials/provider.ts";
import type { EveSessionContext } from "../../src/eve/index.ts";

import { DbException } from "../../src/core/errors.ts";
import { credentialAuth, tenantArgument } from "../../src/eve/index.ts";

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

describe("credentialAuth", () => {
  const user = { type: "user" as const, id: "user_1" };
  const ref = { provider: "vercel-connect", connector: "github" };

  const provider = (extra: Record<string, unknown> = {}) =>
    ({
      apiVersion: 1,
      name: "test",
      capabilities: () => ({ authorization: true }),
      getToken: async () => ({ ok: true, data: { token: "t" } }),
      startAuthorization: async () => ({
        ok: true,
        data: { url: "https://x.test", deviceCode: "ABCD-1234" },
      }),
      ...extra,
    }) as unknown as CredentialProvider;

  it("sends the device code as userCode", async () => {
    const auth = credentialAuth({ provider: provider(), ref, owner: "user" });

    const started = await auth.startAuthorization?.({
      principal: user,
      connection: { url: "https://mcp.test" },
      callbackUrl: "https://app.test/cb",
    });

    expect(started?.challenge).toMatchObject({
      url: "https://x.test",
      userCode: "ABCD-1234",
    });
  });

  it("evicts through a provider that caches tokens", async () => {
    const invalidateToken = vi.fn(async () => true);

    const auth = credentialAuth({
      provider: provider({ invalidateToken }),
      ref,
      owner: "user",
    });

    await auth.evict?.({
      principal: user,
      connection: { url: "https://mcp.test" },
    });

    expect(invalidateToken).toHaveBeenCalledWith(ref, { subject: user });
    expect(
      credentialAuth({ provider: provider(), ref, owner: "user" }).evict,
    ).toBeUndefined();
  });
});
