import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../../src/blocks/domains/index.ts";

import {
  createDomains,
  createDomainsAdmin,
  domainsBlock,
  normalizeHostname,
  vercelDomainProvider,
} from "../../../src/blocks/domains/index.ts";
import { CHALLENGE, FakeVercelError, fakeVercel } from "./fixtures.ts";

type Answer = (args: Record<string, unknown>) => unknown;

function fakeTransport(results: Record<string, unknown>) {
  const calls: [string, Record<string, unknown>][] = [];

  const transport: BlockTransport = {
    call(_schema, fn, args) {
      calls.push([fn, { ...args }]);
      const result = results[fn];

      const value =
        typeof result === "function" ? (result as Answer)({ ...args }) : result;

      return Promise.resolve(value);
    },
  };

  return { calls, transport };
}

const RECORD = {
  type: "TXT",
  name: "_better-supabase.app.acme.test",
  value: "better-supabase-hostname-verification=abc",
};

const hostnameRow = (overrides: Record<string, unknown> = {}) => ({
  id: "h1",
  tenant_id: "org-1",
  hostname: "app.acme.test",
  kind: "custom",
  verified_at: null,
  is_primary: false,
  created_by: "u1",
  created_at: "2026-10-19T12:00:00Z",
  record: RECORD,
  ...overrides,
});

const verified = { verified_at: "2026-10-19T12:05:00Z", record: undefined };

describe("normalizeHostname", () => {
  it("drops the port and the trailing dot, and lowercases", () => {
    expect(normalizeHostname("App.Acme.Test:3000")).toBe("app.acme.test");
    expect(normalizeHostname(" acme.test. ")).toBe("acme.test");
    expect(normalizeHostname("[::1]:3000")).toBe("[::1]");
  });
});

describe("createDomains", () => {
  it("maps hostnames and the proxy lookup", async () => {
    const { calls, transport } = fakeTransport({
      add_hostname: hostnameRow(),
      list_hostnames: (args: Record<string, unknown>) => {
        const rows = [
          hostnameRow({ ...verified, is_primary: true }),
          hostnameRow({
            id: "h2",
            hostname: "acme.acme.app",
            kind: "subdomain",
            ...verified,
          }),
        ];

        const filters = (args["filters"] ?? {}) as Record<string, unknown>;

        if (filters["count"] === true) {
          return { value: rows.length, exact: true };
        }

        return filters["paged"] === true
          ? { items: rows, hasMore: false, nextCursor: null }
          : rows;
      },
      set_primary_hostname: hostnameRow({ ...verified, is_primary: true }),
      remove_hostname: true,
      resolve_hostname: {
        organizationId: "org-1",
        hostname: "acme.acme.app",
        primary: false,
        primaryHostname: "app.acme.test",
      },
    });

    const domains = createDomains({ transport });

    const added = await domains
      .add({ organizationId: "org-1", hostname: "app.acme.test" })
      .orThrow();

    expect(added).toMatchObject({
      id: "h1",
      organizationId: "org-1",
      kind: "custom",
      verifiedAt: undefined,
      primary: false,
      record: RECORD,
    });
    expect(added.createdAt.toString()).toBe("2026-10-19T12:00:00Z");

    const list = await domains.list("org-1").orThrow();
    expect(list.map((row) => [row.hostname, row.kind, row.primary])).toEqual([
      ["app.acme.test", "custom", true],
      ["acme.acme.app", "subdomain", false],
    ]);
    expect(list[0]!.record).toBeUndefined();
    expect(list[0]!.verifiedAt?.toString()).toBe("2026-10-19T12:05:00Z");

    const page = await domains
      .page({
        organizationId: "org-2",
        sort: { by: "hostname" },
        filters: { verified: ["true"] },
      })
      .orThrow();

    expect(page.items.map((row) => row.hostname)).toEqual([
      "app.acme.test",
      "acme.acme.app",
    ]);
    expect(await domains.count({ organizationId: "org-1" }).orThrow()).toEqual({
      value: 2,
      exact: true,
    });
    expect(
      (await domains.page({ organizationId: "o", sort: { by: "x" } })).ok,
    ).toBe(false);

    expect((await domains.setPrimary("h1").orThrow()).primary).toBe(true);
    expect(await domains.remove("h1").orThrow()).toBe(true);
    expect(await domains.resolve("Acme.Acme.App:443").orThrow()).toEqual({
      organizationId: "org-1",
      hostname: "acme.acme.app",
      primary: false,
      primaryHostname: "app.acme.test",
    });

    expect(calls).toEqual([
      ["add_hostname", { tenant: "org-1", hostname: "app.acme.test" }],
      ["list_hostnames", { tenant: "org-1" }],
      [
        "list_hostnames",
        {
          tenant: "org-2",
          filters: { verified: ["true"], sort: "hostname", paged: true },
        },
      ],
      ["list_hostnames", { tenant: "org-1", filters: { count: true } }],
      ["set_primary_hostname", { id: "h1" }],
      ["remove_hostname", { id: "h1" }],
      ["resolve_hostname", { hostname: "acme.acme.app" }],
    ]);
  });

  it("resolves an unknown hostname to undefined", async () => {
    const { transport } = fakeTransport({ resolve_hostname: null });

    expect(
      await createDomains({ transport }).resolve("nope.test").orThrow(),
    ).toBeUndefined();
  });

  it("is the domains block", () => {
    expect(domainsBlock.name).toBe("domains");
    expect(domainsBlock.sql).toEqual(["domains"]);
    expect(domainsBlock.events.types).toEqual([
      "hostname.added",
      "hostname.verified",
      "hostname.primary_changed",
      "hostname.deleted",
    ]);
  });
});

describe("createDomainsAdmin", () => {
  it("verifies once the TXT record holds the value", async () => {
    const { calls, transport } = fakeTransport({
      hostname_by_id: hostnameRow(),
      verify_hostname: hostnameRow(verified),
    });

    const lookups: string[] = [];

    const admin = createDomainsAdmin({
      transport,
      resolver: (name) => {
        lookups.push(name);

        return Promise.resolve(["other", RECORD.value]);
      },
    });

    const result = await admin
      .verify({ hostnameId: "h1", actorId: "u1" })
      .orThrow();

    expect(result.verifiedAt?.toString()).toBe("2026-10-19T12:05:00Z");
    expect(lookups).toEqual([RECORD.name]);
    expect(calls.at(-1)).toEqual([
      "verify_hostname",
      { id: "h1", actor: "u1" },
    ]);
  });

  it("refuses while the record is missing", async () => {
    const { calls, transport } = fakeTransport({
      hostname_by_id: hostnameRow(),
    });

    const admin = createDomainsAdmin({
      transport,
      resolver: () => Promise.resolve([]),
    });

    const result = await admin.verify({ hostnameId: "h1" });

    expect(result.ok).toBe(false);
    expect(result.ok ? undefined : result.error.hint).toBe(
      "DOMAIN_RECORD_MISSING",
    );
    expect(calls.map(([fn]) => fn)).toEqual(["hostname_by_id"]);
  });

  it("skips the lookup for a verified hostname and reports an unknown id", async () => {
    const lookups: string[] = [];

    const resolver = (name: string) => {
      lookups.push(name);

      return Promise.resolve([]);
    };

    const known = fakeTransport({
      hostname_by_id: hostnameRow(verified),
      verify_hostname: hostnameRow(verified),
    });

    expect(
      (
        await createDomainsAdmin({
          transport: known.transport,
          resolver,
        }).verify({ hostnameId: "h1" })
      ).ok,
    ).toBe(true);
    expect(lookups).toEqual([]);

    const unknown = fakeTransport({ hostname_by_id: null });

    const missing = await createDomainsAdmin({
      transport: unknown.transport,
      resolver,
    }).verify({ hostnameId: "nope" });

    expect(missing.ok ? undefined : missing.error.kind).toBe("not_found");
  });

  it("turns a failed lookup into a network error", async () => {
    const { transport } = fakeTransport({ hostname_by_id: hostnameRow() });

    const result = await createDomainsAdmin({
      transport,
      resolver: () => Promise.reject(new Error("DNS down")),
    }).verify({ hostnameId: "h1" });

    expect(result.ok ? undefined : result.error.kind).toBe("network");
  });
});

describe("createDomainsAdmin with a provider", () => {
  const hasRecord = () => Promise.resolve([RECORD.value]);

  it("adds, reads and removes the hostname on the platform", async () => {
    const vercel = fakeVercel({ challenge: true });

    const { calls, transport } = fakeTransport({
      hostname_by_id: hostnameRow(),
    });

    const admin = createDomainsAdmin({
      transport,
      provider: vercelDomainProvider(vercel.sdk, { projectId: "prj_1" }),
    });

    const { signal } = new AbortController();

    expect(await admin.add({ hostnameId: "h1", signal }).orThrow()).toEqual({
      hostname: "app.acme.test",
      verified: false,
      records: [
        {
          type: "TXT",
          name: CHALLENGE.domain,
          value: CHALLENGE.value,
          reason: CHALLENGE.reason,
        },
      ],
    });
    expect((await admin.status({ hostnameId: "h1" }).orThrow())?.verified).toBe(
      false,
    );
    expect(await admin.remove({ hostname: "App.Acme.Test." }).orThrow()).toBe(
      true,
    );
    expect(await admin.status({ hostnameId: "h1" }).orThrow()).toBeUndefined();
    expect(await admin.remove({ hostname: "app.acme.test" }).orThrow()).toBe(
      false,
    );

    expect(calls).toEqual([
      ["hostname_by_id", { id: "h1" }],
      ["hostname_by_id", { id: "h1" }],
      ["hostname_by_id", { id: "h1" }],
    ]);
    expect(vercel.calls[0]).toEqual([
      "addProjectDomain",
      { idOrName: "prj_1", requestBody: { name: "app.acme.test" } },
      { signal },
    ]);
    expect(vercel.calls[2]?.[1]).toEqual({
      idOrName: "prj_1",
      domain: "app.acme.test",
    });
  });

  it("reports an unknown id before calling the platform", async () => {
    const vercel = fakeVercel();
    const { transport } = fakeTransport({ hostname_by_id: null });

    const admin = createDomainsAdmin({
      transport,
      provider: vercelDomainProvider(vercel.sdk, { projectId: "prj_1" }),
    });

    const added = await admin.add({ hostnameId: "nope" });

    expect(added.ok ? undefined : added.error.hint).toBe("DOMAIN_NOT_FOUND");
    expect(vercel.calls).toEqual([]);
  });

  it("verifies on the platform after the TXT record, then in the database", async () => {
    const vercel = fakeVercel({ challenge: true });
    vercel.domains.set("app.acme.test", { verified: false });

    const { calls, transport } = fakeTransport({
      hostname_by_id: hostnameRow(),
      verify_hostname: hostnameRow(verified),
    });

    const admin = createDomainsAdmin({
      transport,
      resolver: hasRecord,
      provider: vercelDomainProvider(vercel.sdk, { projectId: "prj_1" }),
    });

    const pending = await admin.verify({ hostnameId: "h1", actorId: "u1" });

    expect(pending.ok ? undefined : pending.error).toMatchObject({
      kind: "invalid_request",
      hint: "DOMAIN_PROVIDER_UNVERIFIED",
      message: `vercel has not verified app.acme.test yet; publish TXT ${CHALLENGE.domain} ${CHALLENGE.value}`,
    });
    expect(calls.map(([fn]) => fn)).toEqual(["hostname_by_id"]);

    vercel.publish();

    const done = await admin
      .verify({ hostnameId: "h1", actorId: "u1" })
      .orThrow();

    expect(done.verifiedAt?.toString()).toBe("2026-10-19T12:05:00Z");
    expect(calls.map(([fn]) => fn)).toEqual([
      "hostname_by_id",
      "hostname_by_id",
      "verify_hostname",
    ]);
  });

  it("doesn't call the platform while the TXT record is missing", async () => {
    const vercel = fakeVercel();
    const { transport } = fakeTransport({ hostname_by_id: hostnameRow() });

    const result = await createDomainsAdmin({
      transport,
      resolver: () => Promise.resolve([]),
      provider: vercelDomainProvider(vercel.sdk, { projectId: "prj_1" }),
    }).verify({ hostnameId: "h1" });

    expect(result.ok ? undefined : result.error.hint).toBe(
      "DOMAIN_RECORD_MISSING",
    );
    expect(vercel.calls).toEqual([]);
  });

  it("checks a subdomain on the platform without a TXT lookup", async () => {
    const vercel = fakeVercel();
    vercel.domains.set("acme.acme.app", { verified: true });
    const lookups: string[] = [];

    const { calls, transport } = fakeTransport({
      hostname_by_id: hostnameRow({
        hostname: "acme.acme.app",
        kind: "subdomain",
        ...verified,
      }),
      verify_hostname: hostnameRow({
        hostname: "acme.acme.app",
        kind: "subdomain",
        ...verified,
      }),
    });

    const result = await createDomainsAdmin({
      transport,
      resolver: (name) => {
        lookups.push(name);

        return Promise.resolve([]);
      },
      provider: vercelDomainProvider(vercel.sdk, { projectId: "prj_1" }),
    }).verify({ hostnameId: "h1" });

    expect(result.ok).toBe(true);
    expect(lookups).toEqual([]);
    expect(vercel.calls.map(([method]) => method)).toEqual([
      "verifyProjectDomain",
    ]);
    expect(calls.at(-1)?.[0]).toBe("verify_hostname");
  });

  it("returns the platform's error without verifying in the database", async () => {
    const vercel = fakeVercel();

    vercel.failWith(
      "verifyProjectDomain",
      new FakeVercelError(403, "forbidden", "Not authorized"),
    );

    const { calls, transport } = fakeTransport({
      hostname_by_id: hostnameRow(),
    });

    const result = await createDomainsAdmin({
      transport,
      resolver: hasRecord,
      provider: vercelDomainProvider(vercel.sdk, { projectId: "prj_1" }),
    }).verify({ hostnameId: "h1" });

    expect(result.ok ? undefined : result.error.kind).toBe("forbidden");
    expect(calls.map(([fn]) => fn)).toEqual(["hostname_by_id"]);
  });

  it("refuses add, remove and status without a provider", async () => {
    const { calls, transport } = fakeTransport({
      hostname_by_id: hostnameRow(),
    });

    const admin = createDomainsAdmin({ transport, resolver: hasRecord });

    for (const result of [
      await admin.add({ hostnameId: "h1" }),
      await admin.remove({ hostname: "app.acme.test" }),
      await admin.status({ hostnameId: "h1" }),
    ]) {
      expect(result.ok ? undefined : result.error).toMatchObject({
        kind: "invalid_request",
        hint: "DOMAIN_PROVIDER_MISSING",
      });
    }

    expect(calls).toEqual([]);
  });

  it("refuses a provider for another apiVersion", () => {
    const { transport } = fakeTransport({});

    const provider = vercelDomainProvider(fakeVercel().sdk, {
      projectId: "prj_1",
    });

    expect(() =>
      createDomainsAdmin({
        transport,
        // SAFETY: simulates a provider built for a newer API.
        provider: { ...provider, apiVersion: 2 } as never,
      }),
    ).toThrow(TypeError);
  });
});
