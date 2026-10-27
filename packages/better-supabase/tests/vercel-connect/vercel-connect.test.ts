import { describe, expect, it, vi } from "vitest";

import type { VercelConnectModule } from "../../src/vercel-connect/index.ts";

import {
  connectSubject,
  installationRef,
  vercelConnectCredentials,
  withConnectorToken,
} from "../../src/vercel-connect/index.ts";

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

        if (fail) {
          throw fail;
        }

        return { token: "gho_1", expiresAt: 1_700_000_000_000 };
      },
      async revokeToken(...args) {
        calls.push(["revoke", ...args]);
      },
      async startAuthorization(...args) {
        calls.push(["start", ...args]);

        return {
          url: "https://vercel.com/connect/authorize?x",
          request: "req_1",
          verifier: "ver_1",
          deviceCode: "ABCD-1234",
          expiresAt: 1_700_000_600_000,
        };
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
    expect(started.request).toBe("req_1");
    expect(started.verifier).toBe("ver_1");
    expect(started.deviceCode).toBe("ABCD-1234");
    expect(started.expiresAt?.epochMilliseconds).toBe(1_700_000_600_000);
    expect(calls[1]?.[3]).toEqual({
      vercelToken: "vt",
      callbackUrl: "https://app.test/callback",
    });

    expect(await provider.revoke(ref, { subject: user }).orThrow()).toBe(true);
    expect(provider.capabilities(ref).authorization).toBe(true);
  });

  it("passes the ref's token parameters, the region and fresh through", async () => {
    const { module, calls } = fakeConnect();

    const provider = vercelConnectCredentials({
      region: "fra1",
      load: async () => module,
    });

    const exchange = {
      type: "jwt-bearer",
      sub: "agent-7",
      additionalClaims: { act: "bot" },
    } as const;

    await provider
      .getToken(
        {
          ...ref,
          audience: ["https://api.test"],
          resources: ["https://api.test/repos"],
          authorizationDetails: [{ type: "github_app_installation" }, 1],
          validityBufferMs: 60_000,
        },
        { subject: exchange, fresh: true },
      )
      .orThrow();

    expect(calls[0]).toEqual([
      "get",
      "github",
      {
        subject: exchange,
        installationId: "inst_1",
        scopes: ["repo"],
        audience: ["https://api.test"],
        resources: ["https://api.test/repos"],
        authorizationDetails: [{ type: "github_app_installation" }],
        validityBufferMs: 60_000,
      },
      { region: "fra1", forceRefresh: true },
    ]);
    expect(provider.capabilities(ref).exchangeSubjects).toBe(true);
  });

  it("maps the Connect error codes and keeps status and vendor", async () => {
    for (const [code, status, kind, hint] of [
      [
        "connector_not_found",
        404,
        "not_found",
        "CREDENTIAL_CONNECTOR_NOT_FOUND",
      ],
      [
        "client_not_linked_to_project",
        403,
        "forbidden",
        "CREDENTIAL_CONNECTOR_NOT_LINKED",
      ],
      [
        "client_not_enabled_for_environment",
        403,
        "forbidden",
        "CREDENTIAL_CONNECTOR_NOT_ENABLED",
      ],
      [
        "user_authorization_required",
        403,
        "forbidden",
        "CREDENTIAL_AUTHORIZATION_REQUIRED",
      ],
      [undefined, 429, "rate_limited", "CREDENTIAL_RATE_LIMITED"],
    ] as const) {
      const error = Object.assign(named("ConnectError"), {
        code,
        status,
        vendor: { error: "slow_down" },
      });

      const { module } = fakeConnect(error);
      const provider = vercelConnectCredentials({ load: async () => module });
      const result = await provider.getToken(ref, { subject: user });

      expect(
        result.ok ? undefined : [result.error.kind, result.error.hint],
      ).toEqual([kind, hint]);
      expect(result.ok ? undefined : result.error.code).toBe(code);
      expect(result.ok ? undefined : result.error.details).toBe(
        JSON.stringify({ status, vendor: { error: "slow_down" } }),
      );
    }
  });

  it("verifies forwarded webhooks only for an inbound ref", async () => {
    const seen: unknown[] = [];

    const provider = vercelConnectCredentials({
      inbound: { projectId: "prj_1" },
      load: async () => fakeConnect().module,
      loadChat: async () => ({
        createConnectWebhookVerifier(options?: Record<string, unknown>) {
          seen.push(options);

          return (request: Request, body: string) => {
            seen.push(body);

            if (request.headers.get("authorization") !== "Bearer oidc") {
              throw new Error("bad token");
            }

            return { sub: "connect" };
          };
        },
      }),
    });

    const inbound = { ...ref, inbound: true };

    const request = (token: string): Request =>
      new Request("https://app.test/hook", {
        method: "POST",
        headers: { authorization: `Bearer ${token}` },
        body: "{}",
      });

    expect(provider.capabilities(inbound).inbound).toBe(true);
    expect(provider.capabilities(ref).inbound).toBe(false);
    expect(
      await provider.verifyInbound!(request("oidc"), inbound).orThrow(),
    ).toBe(true);
    expect(
      await provider.verifyInbound!(request("forged"), inbound).orThrow(),
    ).toBe(false);
    expect(seen).toEqual([{ projectId: "prj_1" }, "{}", "{}"]);

    const off = await provider.verifyInbound!(request("oidc"), ref);
    expect(off.ok ? undefined : off.error.hint).toBe(
      "CREDENTIAL_INBOUND_DISABLED",
    );
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

    const tenantRef = {
      provider: "vercel-connect",
      connector: "github",
      tenant: "acme",
    };

    for (const result of [
      await provider.getToken(tenantRef, { subject: { type: "app" } }),
      await provider.revoke(tenantRef, { subject: { type: "app" } }),
    ]) {
      expect(result.ok ? undefined : result.error.hint).toBe(
        "CREDENTIAL_REF_FOREIGN",
      );
    }

    expect(load).not.toHaveBeenCalled();
    const forUser = await provider.getToken(tenantRef, { subject: user });
    expect(forUser.ok ? undefined : forUser.error.message).toMatch(
      /pnpm add @vercel\/connect/,
    );
  });

  it("returns the whole token response and clears its cache entry", async () => {
    const { module, calls } = fakeConnect();
    const deleteTokenCacheEntry = vi.fn();

    const provider = vercelConnectCredentials({
      load: async () => ({
        ...module,
        deleteTokenCacheEntry,
        async getTokenResponse(...args: unknown[]) {
          calls.push(["get", ...args]);

          return {
            token: "gho_1",
            tokenId: "tok_1",
            expiresAt: 1,
            installationId: "inst_1",
            externalSubject: "octocat",
          };
        },
      }),
    });

    const details = await provider
      .tokenDetails(ref, { subject: user })
      .orThrow();

    expect(details).toMatchObject({
      tokenId: "tok_1",
      externalSubject: "octocat",
    });

    expect(
      await provider.invalidateToken(ref, { subject: user }).orThrow(),
    ).toBe(true);
    expect(deleteTokenCacheEntry).toHaveBeenCalledWith("github", {
      subject: user,
      installationId: "inst_1",
      scopes: ["repo"],
    });

    const old = vercelConnectCredentials({ load: async () => module });
    expect(await old.invalidateToken(ref, { subject: user }).orThrow()).toBe(
      false,
    );
  });

  it("reads connector metadata and starts a tenant installation", async () => {
    const { module } = fakeConnect();

    const startInstallation = vi.fn(async () => ({
      url: "https://vercel.com/connect/install",
      request: "req_2",
      verifier: "ver_2",
      expiresAt: 2,
      connector: { id: "c1", uid: "github", type: "github", name: "GitHub" },
    }));

    const provider = vercelConnectCredentials({
      region: "iad1",
      load: async () => ({
        ...module,
        getConnectorMetadata: async () => ({
          id: "c1",
          uid: "github",
          name: "GitHub",
          type: "github",
          service: "github",
        }),
        experimental_startInstallation: startInstallation,
      }),
    });

    expect((await provider.connectorMetadata(ref).orThrow()).name).toBe(
      "GitHub",
    );

    const installed = await provider
      .startInstallation(ref, { tenantId: "acme", returnUrl: "https://a.test" })
      .orThrow();

    expect(installed.url).toBe("https://vercel.com/connect/install");
    expect(startInstallation).toHaveBeenCalledWith(
      "github",
      { installationId: "inst_1", scopes: ["repo"] },
      { region: "iad1", tenantId: "acme", returnUrl: "https://a.test" },
    );

    const old = vercelConnectCredentials({ load: async () => module });
    const missing = await old.connectorMetadata(ref);
    expect(missing.ok ? undefined : missing.error.message).toMatch(
      /newer @vercel\/connect/,
    );
  });

  it("resolves a tenant installation only when Connect names the tenant", async () => {
    const tenantOf = (tenantId: string): VercelConnectModule => ({
      ...fakeConnect().module,
      async getTokenResponse() {
        return { token: "xoxb", expiresAt: 1, tenantId };
      },
    });

    const scoped = installationRef(
      { provider: "vercel-connect", connector: "slack", tenant: "acme" },
      "inst_acme",
    );

    const app = { subject: { type: "app" } } as const;

    const own = vercelConnectCredentials({
      load: async () => tenantOf("acme"),
    });

    expect((await own.getToken(scoped, app).orThrow()).token).toBe("xoxb");

    const other = vercelConnectCredentials({
      load: async () => tenantOf("globex"),
    });

    const foreign = await other.getToken(scoped, app);
    expect(foreign.ok ? undefined : foreign.error.hint).toBe(
      "CREDENTIAL_REF_FOREIGN",
    );

    const revoked = await own.revoke(scoped, app);
    expect(revoked.ok ? undefined : revoked.error.hint).toBe(
      "CREDENTIAL_REF_FOREIGN",
    );
  });

  it("builds a Chat SDK adapter config for the connector", async () => {
    const connectSlackAdapter = vi.fn(() => ({
      botToken: async () => "xoxb",
      webhookVerifier: () => true,
    }));

    const provider = vercelConnectCredentials({
      load: async () => fakeConnect().module,
      loadChat: async () => ({
        createConnectWebhookVerifier: () => () => true,
        connectSlackAdapter,
      }),
    });

    const config = await provider.channelConfig(ref, "slack").orThrow();
    expect("botToken" in config).toBe(true);
    expect(connectSlackAdapter).toHaveBeenCalledWith(
      "github",
      { installationId: "inst_1", scopes: ["repo"] },
      {},
    );

    const missing = await provider.channelConfig(ref, "teams");
    expect(missing.ok ? undefined : missing.error.kind).toBe("invalid_request");
  });

  it("pins the Supabase Auth issuer on a user subject", () => {
    expect(
      connectSubject({ id: "u1" }, { supabaseUrl: "https://p.supabase.co/" }),
    ).toEqual({
      type: "user",
      id: "u1",
      issuer: "https://p.supabase.co/auth/v1",
    });
  });

  it("returns the consent URL when the user hasn't authorized", async () => {
    const options = { subject: user, redirectUri: "https://app.test/callback" };

    const denied = vercelConnectCredentials({
      load: async () =>
        fakeConnect(named("UserAuthorizationRequiredError")).module,
    });

    const outcome = await withConnectorToken(
      denied,
      ref,
      options,
      async () => 1,
    );

    expect(outcome.ok ? outcome.data : undefined).toEqual({
      status: "authorization_required",
      url: "https://vercel.com/connect/authorize?x",
      deviceCode: "ABCD-1234",
    });

    const granted = vercelConnectCredentials({
      load: async () => fakeConnect().module,
    });

    const ran = await withConnectorToken(
      granted,
      ref,
      options,
      async (token) => token.token,
    );

    expect(ran.ok ? ran.data : undefined).toEqual({
      status: "ok",
      value: "gho_1",
    });

    const broken = vercelConnectCredentials({
      load: async () => fakeConnect(named("TypeError")).module,
    });

    const failed = await withConnectorToken(
      broken,
      ref,
      options,
      async () => 1,
    );

    expect(failed.ok ? undefined : failed.error.kind).toBe("network");
  });
});
