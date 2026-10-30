import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../../src/blocks/domains/index.ts";

import {
  createDomains,
  createDomainsAdmin,
  domainsBlock,
  normalizeHostname,
} from "../../../src/blocks/domains/index.ts";

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
  organization_id: "org-1",
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
      list_hostnames: [
        hostnameRow({ ...verified, is_primary: true }),
        hostnameRow({
          id: "h2",
          hostname: "acme.acme.app",
          kind: "subdomain",
          ...verified,
        }),
      ],
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

    const added = await domains.add("org-1", "app.acme.test").orThrow();
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

    const result = await admin.verify("h1", { actorId: "u1" }).orThrow();

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

    const result = await admin.verify("h1");

    expect(result.ok).toBe(false);
    expect(result.ok ? undefined : result.error.hint).toBe(
      "HOSTNAME_RECORD_MISSING",
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
        }).verify("h1")
      ).ok,
    ).toBe(true);
    expect(lookups).toEqual([]);

    const unknown = fakeTransport({ hostname_by_id: null });

    const missing = await createDomainsAdmin({
      transport: unknown.transport,
      resolver,
    }).verify("nope");

    expect(missing.ok ? undefined : missing.error.kind).toBe("not_found");
  });

  it("turns a failed lookup into a network error", async () => {
    const { transport } = fakeTransport({ hostname_by_id: hostnameRow() });

    const result = await createDomainsAdmin({
      transport,
      resolver: () => Promise.reject(new Error("DNS down")),
    }).verify("h1");

    expect(result.ok ? undefined : result.error.kind).toBe("network");
  });
});
