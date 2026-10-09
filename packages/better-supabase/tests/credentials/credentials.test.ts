import { describe, expect, it } from "vitest";

import type { AuthState } from "../../src/auth/resolve.ts";
import type { BlockTransport } from "../../src/core/block-transport.ts";
import type {
  CredentialProvider,
  CredentialRef,
  CredentialSubject,
} from "../../src/credentials/index.ts";

import { signWebhook } from "../../src/blocks/webhooks/verify.ts";
import {
  credentialRefInTenant,
  foreignCredentialRef,
  subjectFor,
  tenantCredentialRef,
  vaultCredentials,
} from "../../src/credentials/index.ts";
import { credentialProviderOf } from "../../src/credentials/provider.ts";
import { testCredentialProvider } from "../../src/testing/index.ts";

/** The `credentials` module's functions over a map. */
function fakeVault(): {
  transport: BlockTransport;
  secrets: Map<string, string>;
  calls: string[];
} {
  const secrets = new Map<string, string>();
  const calls: string[] = [];
  const key = (args: Readonly<Record<string, unknown>>): string =>
    `bs:cred:${String(args["provider"])}:${String(args["name"])}`;
  return {
    secrets,
    calls,
    transport: {
      async call(_schema, fn, args) {
        calls.push(fn);
        switch (fn) {
          case "credential_get": {
            return secrets.get(key(args)) ?? null;
          }
          case "credential_set": {
            secrets.set(key(args), String(args["secret"]));
            return crypto.randomUUID();
          }
          case "credential_delete": {
            return secrets.delete(key(args));
          }
          default: {
            throw new Error(`unexpected ${fn}`);
          }
        }
      },
    },
  };
}

const APP: CredentialSubject = { type: "app" };
const tokenRef: CredentialRef = { provider: "vault", secret: "slack" };

describe("vaultCredentials", () => {
  it("passes the CredentialProvider kit", async () => {
    const { transport } = fakeVault();
    const vault = vaultCredentials({ transport });
    const report = await testCredentialProvider(vault, {
      ref: tokenRef,
      userRef: { provider: "vault", secret: "github", scope: "user" },
      inbound: {
        ref: {
          provider: "vault",
          secret: "hooks",
          inbound: "standard-webhooks",
        },
        async sign(body, secret) {
          return new Request("https://app.test/hooks", {
            method: "POST",
            headers: await signWebhook(secret, { id: "msg_1", body }),
            body,
          });
        },
      },
      seed: (ref, subject, value) =>
        vault.set(ref, value, { subject }).orThrow(),
    });
    expect(report.checks.every((check) => check.ok)).toBe(true);
    expect(report.checks).toHaveLength(8);
  });

  it("stores a tenant's ref under tenant/<tenant>/ and refuses slash tricks", async () => {
    const vault = fakeVault();
    const provider = vaultCredentials({ transport: vault.transport });
    const ref = tenantCredentialRef("org-1", tokenRef);
    await provider.set(ref, "tenant-token").orThrow();
    expect(vault.secrets.get("bs:cred:vault:tenant/org-1/slack")).toBe(
      "tenant-token",
    );
    vault.secrets.set("bs:cred:vault:slack", "app-token");
    expect(
      (await provider.getToken(ref, { subject: APP }).orThrow()).token,
    ).toBe("tenant-token");
    for (const bad of [
      { provider: "vault", secret: "x", tenant: "org/../other" },
      { provider: "vault", secret: "other/x", tenant: "org-1" },
      { provider: "vault", secret: "tenant/org-2/slack" },
      { provider: "vault", secret: "x", tenant: 7 } as unknown as CredentialRef,
    ]) {
      const result = await provider.getToken(bad, { subject: APP });
      expect(result.ok ? undefined : result.error.hint).toBe(
        "CREDENTIAL_REF_INVALID",
      );
    }
  });

  it("binds refs to a tenant", () => {
    const ref = tenantCredentialRef("org-1", tokenRef);
    expect(ref).toEqual({
      provider: "vault",
      secret: "slack",
      tenant: "org-1",
    });
    expect(credentialRefInTenant(ref, "org-1")).toBe(true);
    expect(credentialRefInTenant(ref, "org-2")).toBe(false);
    expect(credentialRefInTenant(tokenRef, "org-1")).toBe(false);
    expect(credentialRefInTenant(tokenRef, undefined)).toBe(true);
    expect(credentialRefInTenant(ref, undefined)).toBe(false);
    expect(foreignCredentialRef("org-1")).toMatchObject({
      kind: "forbidden",
      hint: "CREDENTIAL_REF_FOREIGN",
    });
  });

  it("builds the header from the ref", async () => {
    const { transport } = fakeVault();
    const vault = vaultCredentials({ transport });
    const ref = {
      provider: "vault",
      secret: "openai",
      header: "X-Api-Key",
      scheme: null,
    };
    await vault.set(ref, "sk-1").orThrow();
    const token = await vault.getToken(ref, { subject: APP }).orThrow();
    expect(token.headers).toEqual({ "x-api-key": "sk-1" });
    await vault.set(tokenRef, "xoxb").orThrow();
    expect(
      (await vault.getToken(tokenRef, { subject: APP }).orThrow()).headers,
    ).toEqual({ authorization: "Bearer xoxb" });
  });

  it("caches reads for cacheMs and reads every time at 0", async () => {
    const cached = fakeVault();
    const vault = vaultCredentials({ transport: cached.transport });
    cached.secrets.set("bs:cred:vault:slack", "a");
    await vault.getToken(tokenRef, { subject: APP }).orThrow();
    await vault.getToken(tokenRef, { subject: APP }).orThrow();
    expect(cached.calls.filter((fn) => fn === "credential_get")).toHaveLength(
      1,
    );

    const uncached = fakeVault();
    const live = vaultCredentials({
      transport: uncached.transport,
      cacheMs: 0,
    });
    uncached.secrets.set("bs:cred:vault:slack", "a");
    await live.getToken(tokenRef, { subject: APP }).orThrow();
    uncached.secrets.set("bs:cred:vault:slack", "b");
    const next = await live.getToken(tokenRef, { subject: APP }).orThrow();
    expect(next.token).toBe("b");
  });

  it("refuses malformed refs", async () => {
    const vault = vaultCredentials({ transport: fakeVault().transport });
    for (const ref of [
      { provider: "vault" },
      { provider: "vault", secret: "x", scope: "team" },
      { provider: "vault", secret: "x", header: 1 },
      { provider: "vault", secret: "x", scheme: 2 },
      { provider: "vault", secret: "x", inbound: "basic" },
      { provider: "vault", secret: "x", signatureHeader: false },
    ]) {
      const result = await vault.getToken(ref, { subject: APP });
      expect(result.ok ? undefined : result.error.hint).toBe(
        "CREDENTIAL_REF_INVALID",
      );
    }
    expect(vault.capabilities({ provider: "other" })).toEqual({
      userSubjects: false,
      authorization: false,
      revoke: true,
      inbound: false,
    });
    const set = await vault.set({ provider: "other" }, "x");
    expect(set.ok).toBe(false);
    const revoked = await vault.revoke(
      { provider: "vault", secret: "x", scope: "user" },
      { subject: APP },
    );
    expect(revoked.ok ? undefined : revoked.error.hint).toBe(
      "CREDENTIAL_SUBJECT_REQUIRED",
    );
  });

  it("verifies hmac-sha256 and shared-secret requests", async () => {
    const { transport, secrets } = fakeVault();
    const vault = vaultCredentials({ transport });
    secrets.set("bs:cred:vault:gh", "s3cret");
    secrets.set("bs:cred:vault:db", "shared");
    const body = '{"action":"opened"}';
    const key = await crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode("s3cret"),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"],
    );
    const hex = Array.from(
      new Uint8Array(
        await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body)),
      ),
      (byte) => byte.toString(16).padStart(2, "0"),
    ).join("");
    const gh = { provider: "vault", secret: "gh", inbound: "hmac-sha256" };
    const signed = new Request("https://app.test", {
      method: "POST",
      headers: { "x-hub-signature-256": `sha256=${hex}` },
      body,
    });
    expect(await vault.verifyInbound(signed, gh).orThrow()).toBe(true);
    expect(await signed.text()).toBe(body);
    const wrong = new Request("https://app.test", {
      method: "POST",
      headers: { "x-hub-signature-256": "sha256=00" },
      body,
    });
    expect(await vault.verifyInbound(wrong, gh).orThrow()).toBe(false);

    const db = {
      provider: "vault",
      secret: "db",
      inbound: "shared-secret",
      signatureHeader: "x-webhook-secret",
    };
    const shared = new Request("https://app.test", {
      method: "POST",
      headers: { "x-webhook-secret": "shared" },
      body,
    });
    expect(await vault.verifyInbound(shared, db).orThrow()).toBe(true);
    expect(vault.capabilities(db).inbound).toBe(true);

    const none = await vault.verifyInbound(shared, tokenRef);
    expect(none.ok ? undefined : none.error.hint).toBe(
      "CREDENTIAL_REF_INVALID",
    );
  });

  it("accepts a signed Standard Webhooks body that is not JSON", async () => {
    const { transport } = fakeVault();
    const vault = vaultCredentials({ transport });
    const ref = {
      provider: "vault",
      secret: "sw",
      inbound: "standard-webhooks",
    };
    const secret = `whsec_${btoa("0123456789abcdef")}`;
    await vault.set(ref, secret).orThrow();
    const request = new Request("https://app.test", {
      method: "POST",
      headers: await signWebhook(secret, { id: "msg_2", body: "plain" }),
      body: "plain",
    });
    expect(await vault.verifyInbound(request, ref).orThrow()).toBe(true);
  });
});

describe("subjectFor", () => {
  const user: AuthState = {
    kind: "user",
    token: "t",
    claims: {
      sub: "u1",
      iss: "https://acme.supabase.co/auth/v1",
      role: "authenticated",
      aud: "authenticated",
      exp: 0,
      iat: 0,
    },
    user: { id: "u1", role: "authenticated" },
    source: "bearer",
    expiresAt: null,
  };

  it("maps each auth state", () => {
    expect(subjectFor({ auth: user })).toEqual({
      type: "user",
      id: "u1",
      issuer: "https://acme.supabase.co/auth/v1",
    });
    expect(
      subjectFor({
        auth: { ...user, claims: { ...user.claims, iss: "" } },
      }),
    ).toEqual({ type: "user", id: "u1" });
    expect(
      subjectFor({ auth: { kind: "service", keyName: "secret" } }),
    ).toEqual({ type: "app" });
    const apiKey = {
      kind: "apiKey",
      keyId: "k",
      name: "ci",
      scopes: [],
      claims: user.claims,
    } as const;
    expect(subjectFor({ auth: { ...apiKey, userId: "u2" } })).toEqual({
      type: "user",
      id: "u2",
    });
    expect(subjectFor({ auth: apiKey })).toBeUndefined();
    expect(
      subjectFor({ auth: { kind: "anon", reason: "none" } }),
    ).toBeUndefined();
  });
});

describe("credentialProviderOf", () => {
  it("rejects another apiVersion", () => {
    const provider = vaultCredentials({ transport: fakeVault().transport });
    expect(credentialProviderOf(provider)).toBe(provider);
    expect(() =>
      credentialProviderOf({
        ...provider,
        apiVersion: 2,
      } as unknown as CredentialProvider),
    ).toThrow(/credential provider API 2/);
  });
});
