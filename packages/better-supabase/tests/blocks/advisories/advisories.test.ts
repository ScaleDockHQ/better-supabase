import { describe, expect, it, vi } from "vitest";

import type {
  EpssScore,
  VulnerabilityFeed,
} from "../../../src/blocks/advisories/index.ts";

import {
  advisoriesBlock,
  createAdvisories,
} from "../../../src/blocks/advisories/index.ts";
import { fakeTransport } from "../inbox/fixtures.ts";

const AT = "2026-01-01T00:00:00Z";

const productRow = {
  id: "p1",
  organizationId: "org",
  key: "acme-app",
  name: "Acme App",
  vendor: null,
  description: null,
  archivedAt: null,
  createdAt: AT,
  updatedAt: AT,
};

const vulnerabilityRow = {
  id: "v1",
  organizationId: "org",
  vulnId: "CVE-2021-44228",
  aliases: [],
  summary: null,
  details: null,
  cvssVector: null,
  cvssVersion: null,
  cvssScore: null,
  severity: null,
  epssScore: null,
  epssPercentile: null,
  kev: false,
  kevAddedOn: null,
  kevDueOn: null,
  affectedPurls: [],
  enrichedAt: null,
  createdAt: AT,
  updatedAt: AT,
};

function feedOf(overrides: Partial<VulnerabilityFeed> = {}): VulnerabilityFeed {
  return {
    apiVersion: 1,
    name: "fake",
    osv: async (id) => ({
      ok: true,
      data:
        id === "CVE-2021-44228"
          ? {
              id,
              aliases: [],
              summary: "Log4Shell",
              details: undefined,
              published: undefined,
              modified: undefined,
              severity: [],
              databaseSeverity: undefined,
              affectedPurls: ["pkg:maven/org.apache.logging.log4j/log4j-core"],
              references: [],
            }
          : undefined,
    }),
    epss: async () => ({
      ok: true,
      data: {
        "CVE-2021-44228": {
          score: 0.9,
          percentile: 0.99,
          date: "2026-10-31",
        } satisfies EpssScore,
      },
    }),
    kev: async () => ({ ok: true, data: {} }),
    ...overrides,
  } as VulnerabilityFeed;
}

describe("createAdvisories", () => {
  it("passes the tenant and snake_case arguments to the SQL functions", async () => {
    const { transport, call } = fakeTransport({
      save_advisory_product: productRow,
      list_advisory_products: [productRow],
    });

    const advisories = createAdvisories({
      transport,
      tenant: "org",
      feed: feedOf(),
    });

    const saved = await advisories
      .saveProduct({ key: "acme-app", name: "Acme App" })
      .orThrow();

    const listed = await advisories.products().orThrow();

    expect(saved).toMatchObject({ key: "acme-app", name: "Acme App" });
    expect(listed).toHaveLength(1);
    expect(call).toHaveBeenCalledWith(
      expect.any(String),
      "save_advisory_product",
      expect.objectContaining({ tenant: "org", key: "acme-app" }),
    );
  });

  it("refuses a call without an organization", async () => {
    const { transport, call } = fakeTransport({});
    const advisories = createAdvisories({ transport, feed: feedOf() });

    const result = await advisories.products();

    expect(!result.ok && result.error.hint).toBe("TENANT_REQUIRED");
    expect(call).not.toHaveBeenCalled();
  });

  it("refuses a feed with another API version", () => {
    const { transport } = fakeTransport({});

    expect(() =>
      createAdvisories({
        transport,
        feed: { ...feedOf(), apiVersion: 2 as never },
      }),
    ).toThrow(/feed API 2/u);
  });

  it("rejects a malformed CVSS vector before calling the database", async () => {
    const { transport, call } = fakeTransport({});

    const advisories = createAdvisories({
      transport,
      tenant: "org",
      feed: feedOf(),
    });

    const result = await advisories.saveVulnerability({
      vulnId: "CVE-2021-44228",
      cvssVector: "CVSS:3.1/AV:X",
    });

    expect(result.ok).toBe(false);
    expect(call).not.toHaveBeenCalled();
  });

  it("stores a CVSS 3.1 score computed from the vector", async () => {
    const { transport, call } = fakeTransport({
      save_vulnerability: vulnerabilityRow,
    });

    const advisories = createAdvisories({
      transport,
      tenant: "org",
      feed: feedOf(),
    });

    await advisories
      .saveVulnerability({
        vulnId: "CVE-2021-44228",
        cvssVector: "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:C/C:H/I:H/A:H",
      })
      .orThrow();

    expect(call.mock.calls[0]?.[2]).toMatchObject({
      cvss_version: "3.1",
      cvss_score: 10,
    });
  });
});

describe("enrichDue", () => {
  it("enriches known ids, stamps unknown ones and keeps failures due", async () => {
    const recorded: string[] = [];

    const { transport } = fakeTransport({
      vulnerabilities_due: [
        { vulnId: "CVE-2021-44228" },
        { vulnId: "CVE-0000-0000" },
      ],
      record_vulnerability_enrichment: (args: Record<string, unknown>) => {
        recorded.push(String(args["vuln_id"]));

        return vulnerabilityRow;
      },
    });

    const advisories = createAdvisories({
      transport,
      tenant: "org",
      feed: feedOf(),
    });

    const report = await advisories.enrichDue().orThrow();

    expect(report).toEqual({ checked: 2, enriched: 1, unknown: 1, failed: 0 });
    expect(recorded).toEqual(["CVE-2021-44228", "CVE-0000-0000"]);
  });

  it("stops at the first rate limit", async () => {
    const osv = vi.fn(async () => ({
      ok: false as const,
      error: {
        kind: "rate_limited" as const,
        message: "slow down",
        retryAfter: 5,
      },
    }));

    const { transport, call } = fakeTransport({
      vulnerabilities_due: [{ vulnId: "CVE-1" }, { vulnId: "CVE-2" }],
    });

    const advisories = createAdvisories({
      transport,
      tenant: "org",
      feed: feedOf({ osv } as never),
    });

    const report = await advisories.enrichDue().orThrow();

    expect(report).toEqual({ checked: 2, enriched: 0, unknown: 0, failed: 1 });
    expect(osv).toHaveBeenCalledOnce();
    expect(call).toHaveBeenCalledOnce();
  });

  it("does not read the catalog when nothing is due", async () => {
    const kev = vi.fn(async () => ({ ok: true as const, data: {} }));
    const { transport } = fakeTransport({ vulnerabilities_due: [] });

    const advisories = createAdvisories({
      transport,
      tenant: "org",
      feed: feedOf({ kev } as never),
    });

    expect(await advisories.enrichDue().orThrow()).toEqual({
      checked: 0,
      enriched: 0,
      unknown: 0,
      failed: 0,
    });
    expect(kev).not.toHaveBeenCalled();
  });
});

describe("csafSource", () => {
  it("reads over the service transport", async () => {
    const user = fakeTransport({});
    const service = fakeTransport({ list_published_advisories: [] });

    const advisories = createAdvisories({
      transport: user.transport,
      service: service.transport,
      feed: feedOf(),
    });

    const listed = await advisories.csafSource("org").listPublished();

    expect(listed.ok && listed.data).toEqual([]);
    expect(user.call).not.toHaveBeenCalled();
    expect(service.call).toHaveBeenCalledOnce();
  });
});

describe("advisoriesBlock", () => {
  it("declares the feed provider and the hourly enrichment schedule", () => {
    expect(advisoriesBlock.name).toBe("advisories");
    expect(advisoriesBlock.providers.map((p) => p.option)).toEqual(["feed"]);
    expect(advisoriesBlock.schedules.map((s) => s.name)).toEqual(["enrich"]);
  });
});
