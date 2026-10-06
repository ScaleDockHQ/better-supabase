import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../../src/blocks/sso/index.ts";

import {
  createSso,
  createSsoAdmin,
  dohResolver,
} from "../../../src/blocks/sso/index.ts";

type Answer = (args: Record<string, unknown>) => unknown;

function fakeTransport(results: Record<string, unknown>) {
  const calls: [string, Record<string, unknown>][] = [];
  const transport: BlockTransport = {
    call(_schema, fn, args) {
      calls.push([fn, { ...args }]);
      const result = results[fn];
      const value =
        typeof result === "function" ? (result as Answer)({ ...args }) : result;
      return value instanceof Error ||
        (typeof value === "object" && value !== null && "code" in value)
        ? Promise.reject(value)
        : Promise.resolve(value);
    },
  };
  return { calls, transport };
}

const domainRow = (overrides: Record<string, unknown> = {}) => ({
  id: "d1",
  organization_id: "org-1",
  domain: "acme.test",
  verified_at: null,
  auto_join_role: null,
  enforce_sso: false,
  created_by: "u1",
  created_at: "2026-10-06T12:00:00Z",
  record: {
    type: "TXT",
    name: "_better-supabase.acme.test",
    value: "better-supabase-domain-verification=abc",
  },
  ...overrides,
});

const providerRow = (overrides: Record<string, unknown> = {}) => ({
  id: "p1",
  organization_id: "org-1",
  type: "saml",
  metadata_url: "https://idp.test/metadata",
  domains: ["acme.test"],
  created_at: "2026-10-06T12:00:00Z",
  ...overrides,
});

function fakeFetch(
  answer: (url: string, init: RequestInit) => Response | Promise<Response>,
) {
  const requests: { url: string; init: RequestInit }[] = [];
  const fetcher = ((input: RequestInfo | URL, init: RequestInit = {}) => {
    const url = input instanceof Request ? input.url : String(input);
    requests.push({ url, init });
    return Promise.resolve(answer(url, init));
  }) as typeof fetch;
  return { requests, fetch: fetcher };
}

describe("createSso", () => {
  it("maps domains, providers and the sign-in lookup", async () => {
    const { calls, transport } = fakeTransport({
      add_organization_domain: domainRow(),
      list_organization_domains: [
        domainRow({ verified_at: "2026-10-06T12:05:00Z" }),
      ],
      organization_domain: domainRow({
        verified_at: "2026-10-06T12:05:00Z",
        auto_join_role: "member",
      }),
      update_organization_domain: (args: Record<string, unknown>) =>
        domainRow({
          auto_join_role: args["auto_join_role"],
          enforce_sso: args["enforce_sso"],
        }),
      remove_organization_domain: true,
      list_sso_providers: [providerRow()],
      sso_domain_for: (args: Record<string, unknown>) =>
        args["email"] === "a@acme.test"
          ? {
              domain: "acme.test",
              organizationId: "org-1",
              providerId: "p1",
              enforceSso: true,
            }
          : null,
    });
    const sso = createSso({ transport });
    const added = await sso.addDomain("org-1", "Acme.test").orThrow();
    expect(added.record.name).toBe("_better-supabase.acme.test");
    expect(added.verifiedAt).toBeUndefined();
    const [listed] = await sso.domains("org-1").orThrow();
    expect(listed?.verifiedAt?.toString()).toBe("2026-10-06T12:05:00Z");

    const updated = await sso
      .updateDomain("d1", { enforceSso: true })
      .orThrow();
    expect(updated).toMatchObject({ autoJoinRole: "member", enforceSso: true });
    await sso.updateDomain("d1", { autoJoinRole: null }).orThrow();
    expect(calls.at(-1)).toEqual([
      "update_organization_domain",
      { id: "d1", auto_join_role: null, enforce_sso: false },
    ]);

    expect(await sso.removeDomain("d1").orThrow()).toBe(true);
    const [provider] = await sso.providers("org-1").orThrow();
    expect(provider).toMatchObject({
      id: "p1",
      type: "saml",
      domains: ["acme.test"],
    });
    expect(await sso.domainFor("a@acme.test").orThrow()).toEqual({
      domain: "acme.test",
      organizationId: "org-1",
      providerId: "p1",
      enforceSso: true,
    });
    expect(await sso.domainFor("b@other.test").orThrow()).toBeUndefined();
  });

  it("returns not_found when updating a domain the caller can't see", async () => {
    const { transport } = fakeTransport({ organization_domain: null });
    const result = await createSso({ transport }).updateDomain("d1", {});
    expect(result.ok).toBe(false);
    expect(!result.ok && result.error).toMatchObject({
      kind: "not_found",
      hint: "SSO_DOMAIN_NOT_FOUND",
    });
  });
});

describe("dohResolver", () => {
  it("reads TXT answers and joins split strings", async () => {
    const { requests, fetch } = fakeFetch(() =>
      Response.json({
        Status: 0,
        Answer: [
          { type: 16, data: '"better-supabase-domain-" "verification=abc"' },
          { type: 5, data: "alias.test." },
          { type: 16, data: 'plain \\"quoted\\"' },
        ],
      }),
    );
    const resolve = dohResolver({
      endpoint: "https://dns.test/resolve",
      fetch,
    });
    expect(await resolve("_better-supabase.acme.test")).toEqual([
      "better-supabase-domain-verification=abc",
      'plain \\"quoted\\"',
    ]);
    expect(requests[0]?.url).toBe(
      "https://dns.test/resolve?name=_better-supabase.acme.test&type=TXT",
    );
    expect(new Headers(requests[0]?.init.headers).get("accept")).toBe(
      "application/dns-json",
    );
  });

  it("treats NXDOMAIN as no records and throws on failures", async () => {
    const answers = [
      Response.json({ Status: 3 }),
      Response.json({ Status: 2 }),
      new Response("down", { status: 502 }),
      Response.json([]),
    ];
    const { fetch } = fakeFetch(() => answers.shift()!);
    const resolve = dohResolver({ fetch });
    expect(await resolve("a.test")).toEqual([]);
    await expect(resolve("a.test")).rejects.toThrow("failed with status 2");
    await expect(resolve("a.test")).rejects.toThrow("failed with 502");
    await expect(resolve("a.test")).rejects.toThrow("returned no JSON");
  });
});

describe("createSsoAdmin", () => {
  it("verifies a domain once its TXT record holds the token", async () => {
    const { calls, transport } = fakeTransport({
      organization_domain: domainRow(),
      verify_organization_domain: domainRow({
        verified_at: "2026-10-06T12:05:00Z",
      }),
    });
    let records: readonly string[] = [];
    const admin = createSsoAdmin({
      transport,
      resolver: () => Promise.resolve(records),
    });
    const missing = await admin.verifyDomain("d1", { actorId: "u1" });
    expect(!missing.ok && missing.error).toMatchObject({
      kind: "invalid_request",
      hint: "SSO_DOMAIN_RECORD_MISSING",
    });
    records = ["better-supabase-domain-verification=abc"];
    const verified = await admin
      .verifyDomain("d1", { actorId: "u1" })
      .orThrow();
    expect(verified.verifiedAt).toBeDefined();
    expect(calls.at(-1)).toEqual([
      "verify_organization_domain",
      { id: "d1", actor: "u1" },
    ]);
  });

  it("reports unknown domains and resolver failures", async () => {
    const unknown = createSsoAdmin({
      transport: fakeTransport({ organization_domain: null }).transport,
      resolver: () => Promise.resolve([]),
    });
    const result = await unknown.verifyDomain("d1");
    expect(!result.ok && result.error.kind).toBe("not_found");
    const failing = createSsoAdmin({
      transport: fakeTransport({ organization_domain: domainRow() }).transport,
      resolver: () => Promise.reject(new Error("dns down")),
    });
    const failed = await failing.verifyDomain("d1");
    expect(!failed.ok && failed.error).toMatchObject({
      kind: "network",
      message: "dns down",
    });
  });

  it("creates, updates and removes SAML providers through the Auth admin API", async () => {
    const { calls, transport } = fakeTransport({
      check_sso_provider: null,
      register_sso_provider: (args: Record<string, unknown>) =>
        providerRow({
          id: args["provider"],
          domains: args["domains"],
          metadata_url: args["metadata_url"],
        }),
      sso_provider: providerRow(),
      unregister_sso_provider: providerRow(),
    });
    const { requests, fetch } = fakeFetch((_url, init) =>
      init.method === "DELETE"
        ? new Response(null, { status: 200 })
        : Response.json({ id: "p1" }),
    );
    const admin = createSsoAdmin({
      transport,
      auth: { url: "https://project.test/", secretKey: "sb_secret_x", fetch },
    });
    const created = await admin
      .addSamlProvider(
        "org-1",
        {
          metadataUrl: "https://idp.test/metadata",
          domains: ["acme.test"],
          attributeMapping: { keys: { email: { name: "mail" } } },
          nameIdFormat:
            "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress",
        },
        { actorId: "u1" },
      )
      .orThrow();
    expect(created.id).toBe("p1");
    expect(requests[0]?.url).toBe(
      "https://project.test/auth/v1/admin/sso/providers",
    );
    expect(requests[0]?.init.method).toBe("POST");
    const headers = new Headers(requests[0]?.init.headers);
    expect(headers.get("apikey")).toBe("sb_secret_x");
    expect(headers.get("authorization")).toBe("Bearer sb_secret_x");
    expect(JSON.parse(String(requests[0]?.init.body))).toEqual({
      type: "saml",
      metadata_url: "https://idp.test/metadata",
      domains: ["acme.test"],
      attribute_mapping: { keys: { email: { name: "mail" } } },
      name_id_format: "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress",
    });

    const updated = await admin
      .updateSamlProvider("p1", {
        metadataXml: "<xml/>",
        domains: ["acme.test", "acme.example"],
      })
      .orThrow();
    expect(updated.metadataUrl).toBeUndefined();
    expect(requests[1]?.init.method).toBe("PUT");
    expect(requests[1]?.url).toBe(
      "https://project.test/auth/v1/admin/sso/providers/p1",
    );
    await admin.updateSamlProvider("p1", { domains: ["acme.test"] }).orThrow();
    expect(calls.at(-1)?.[1]["metadata_url"]).toBe("https://idp.test/metadata");

    const removed = await admin
      .removeSamlProvider("p1", { actorId: "u1" })
      .orThrow();
    expect(removed?.id).toBe("p1");
    expect(requests.at(-1)?.init.method).toBe("DELETE");
    expect(calls.at(-1)).toEqual([
      "unregister_sso_provider",
      { provider: "p1", actor: "u1" },
    ]);
  });

  it("deletes the Auth provider again when recording it fails", async () => {
    const { transport } = fakeTransport({
      check_sso_provider: null,
      register_sso_provider: {
        code: "42501",
        message: "nope",
        hint: "SSO_FORBIDDEN",
      },
    });
    const { requests, fetch } = fakeFetch(() => Response.json({ id: "p9" }));
    const admin = createSsoAdmin({
      transport,
      auth: { url: "https://p.test", secretKey: "k", fetch },
    });
    const result = await admin.addSamlProvider("org-1", {
      metadataXml: "<xml/>",
      domains: ["acme.test"],
    });
    expect(result.ok).toBe(false);
    expect(requests.map((r) => r.init.method)).toEqual(["POST", "DELETE"]);
    expect(requests[1]?.url).toBe(
      "https://p.test/auth/v1/admin/sso/providers/p9",
    );
  });

  it.each([
    [400, "invalid_input"],
    [401, "unauthorized"],
    [403, "forbidden"],
    [404, "not_found"],
    [409, "conflict"],
    [422, "invalid_input"],
    [429, "rate_limited"],
    [500, "network"],
  ])("maps an Auth %i to %s", async (status, kind) => {
    const { transport } = fakeTransport({ check_sso_provider: null });
    const { fetch } = fakeFetch(() =>
      Response.json({ msg: "auth said no" }, { status }),
    );
    const admin = createSsoAdmin({
      transport,
      auth: { url: "https://p.test", secretKey: "k", fetch },
    });
    const result = await admin.addSamlProvider("org-1", {
      metadataXml: "<xml/>",
      domains: ["acme.test"],
    });
    expect(!result.ok && result.error).toMatchObject({
      kind,
      message: "auth said no",
    });
  });

  it("handles missing auth options, network errors and unknown providers", async () => {
    const { transport } = fakeTransport({
      check_sso_provider: null,
      sso_provider: null,
    });
    const without = createSsoAdmin({ transport });
    const result = await without.addSamlProvider("org-1", {
      metadataXml: "<xml/>",
      domains: ["a.test"],
    });
    expect(!result.ok && result.error.kind).toBe("invalid_request");
    const offline = createSsoAdmin({
      transport,
      auth: {
        url: "https://p.test",
        secretKey: "k",
        fetch: () => Promise.reject(new Error("offline")),
      },
    });
    const failed = await offline.addSamlProvider("org-1", {
      metadataXml: "<xml/>",
      domains: ["a.test"],
    });
    expect(!failed.ok && failed.error).toMatchObject({
      kind: "network",
      message: "offline",
    });
    const garbled = createSsoAdmin({
      transport,
      auth: {
        url: "https://p.test",
        secretKey: "k",
        fetch: () => Promise.resolve(new Response("<html>", { status: 502 })),
      },
    });
    const bad = await garbled.addSamlProvider("org-1", {
      metadataXml: "<xml/>",
      domains: ["a.test"],
    });
    expect(!bad.ok && bad.error.message).toBe("Supabase Auth answered 502");
    expect(await offline.removeSamlProvider("p1").orThrow()).toBeUndefined();
    const update = await offline.updateSamlProvider("p1", {
      domains: ["a.test"],
    });
    expect(!update.ok && update.error).toMatchObject({
      kind: "not_found",
      hint: "SSO_PROVIDER_NOT_FOUND",
    });
  });
});
