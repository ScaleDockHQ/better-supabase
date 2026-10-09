import { describe, expect, it, vi } from "vitest";

import type { VercelConnectModule } from "../../src/vercel-connect/index.ts";

import { vercelConnectCredentials } from "../../src/vercel-connect/index.ts";

function named(name: string): Error {
  const error = new Error(name);
  error.name = name;
  return error;
}

function fakeConnect(fail?: Error): {
  module: VercelConnectModule;
  calls: unknown[][];
} {
  const calls: unknown[][] = [];
  return {
    calls,
    module: {
      async getTokenResponse(...args) {
        calls.push(["get", ...args]);
        if (fail) throw fail;
        return { token: "gho_1", expiresAt: 1_700_000_000_000 };
      },
      async revokeToken(...args) {
        calls.push(["revoke", ...args]);
      },
      async startAuthorization(...args) {
        calls.push(["start", ...args]);
        return { url: "https://vercel.com/connect/authorize?x" };
      },
    },
  };
}

const ref = {
  provider: "vercel-connect",
  connector: "github",
  installationId: "inst_1",
  scopes: ["repo"],
};
const user = { type: "user", id: "u1" } as const;

describe("vercelConnectCredentials", () => {
  it("gets, authorizes and revokes through @vercel/connect", async () => {
    const { module, calls } = fakeConnect();
    const provider = vercelConnectCredentials({
      vercelToken: "vt",
      load: async () => module,
    });
    expect(provider.apiVersion).toBe(1);
    const token = await provider.getToken(ref, { subject: user }).orThrow();
    expect(token.token).toBe("gho_1");
    expect(token.headers).toEqual({ authorization: "Bearer gho_1" });
    expect(token.expiresAt?.epochMilliseconds).toBe(1_700_000_000_000);
    expect(calls[0]).toEqual([
      "get",
      "github",
      { subject: user, installationId: "inst_1", scopes: ["repo"] },
      { vercelToken: "vt" },
    ]);

    const started = await provider.startAuthorization!(ref, {
      subject: user,
      redirectUri: "https://app.test/callback",
    }).orThrow();
    expect(started.url).toContain("vercel.com");
    expect(calls[1]?.[3]).toEqual({
      vercelToken: "vt",
      callbackUrl: "https://app.test/callback",
    });

    expect(await provider.revoke(ref, { subject: user }).orThrow()).toBe(true);
    expect(provider.capabilities(ref).authorization).toBe(true);
  });

  it("maps the Connect errors", async () => {
    for (const [name, kind, hint] of [
      [
        "UserAuthorizationRequiredError",
        "forbidden",
        "CREDENTIAL_AUTHORIZATION_REQUIRED",
      ],
      [
        "ConnectorInstallationRequiredError",
        "forbidden",
        "CREDENTIAL_INSTALLATION_REQUIRED",
      ],
      ["NoValidTokenError", "not_found", "CREDENTIAL_NOT_FOUND"],
      ["TypeError", "network", undefined],
    ] as const) {
      const { module } = fakeConnect(named(name));
      const provider = vercelConnectCredentials({ load: async () => module });
      const result = await provider.getToken(ref, { subject: user });
      expect(
        result.ok ? undefined : [result.error.kind, result.error.hint],
      ).toEqual([kind, hint]);
    }
  });

  it("refuses other refs and explains a missing install", async () => {
    const provider = vercelConnectCredentials({ load: async () => undefined });
    const other = await provider.getToken(
      { provider: "vault", secret: "x" },
      { subject: user },
    );
    expect(other.ok ? undefined : other.error.hint).toBe(
      "CREDENTIAL_REF_INVALID",
    );
    const missing = await provider.getToken(ref, { subject: user });
    expect(missing.ok ? undefined : missing.error.message).toMatch(
      /pnpm add @vercel\/connect/,
    );
  });

  it("refuses a tenant's ref for the app subject", async () => {
    const load = vi.fn(async () => undefined);
    const provider = vercelConnectCredentials({ load });
    const tenantRef = { ...ref, tenant: "acme" };
    for (const result of [
      await provider.getToken(tenantRef, { subject: { type: "app" } }),
      await provider.revoke(tenantRef, { subject: { type: "app" } }),
    ])
      expect(result.ok ? undefined : result.error.hint).toBe(
        "CREDENTIAL_REF_FOREIGN",
      );
    expect(load).not.toHaveBeenCalled();
    const forUser = await provider.getToken(tenantRef, { subject: user });
    expect(forUser.ok ? undefined : forUser.error.message).toMatch(
      /pnpm add @vercel\/connect/,
    );
  });
});
