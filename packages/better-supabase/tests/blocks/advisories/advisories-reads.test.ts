import { describe, expect, it } from "vitest";

import type {
  OsvRecord,
  VulnerabilityFeed,
} from "../../../src/blocks/advisories/index.ts";

import { createAdvisories } from "../../../src/blocks/advisories/index.ts";
import { AsyncResult } from "../../../src/core/result.ts";
import { fakeTransport } from "../inbox/fixtures.ts";

const AT = "2026-01-01T00:00:00Z";
const V3 = "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:C/C:H/I:H/A:H";
const V4 = "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N";

const productRow = {
  id: "p1",
  organizationId: "org",
  key: "acme",
  name: "Acme",
  vendor: "Acme Inc",
  description: "The app",
  archivedAt: AT,
  createdAt: AT,
  updatedAt: AT,
};

const versionRow = {
  id: "ver1",
  organizationId: "org",
  productId: "p1",
  version: "1.0.0",
  releasedAt: AT,
  endOfSupportAt: AT,
  sbomSerial: "urn:uuid:3e671687-395b-41f5-a30f-a58921a69b79",
  sbomSpec: "1.6",
  sbomComponents: 3,
  sbomImportedAt: AT,
  createdAt: AT,
};

const vulnerabilityRow = {
  id: "v1",
  organizationId: "org",
  vulnId: "CVE-2021-44228",
  aliases: ["GHSA-jfh8-c2jp-5v3q"],
  summary: "Log4Shell",
  details: "Remote code execution",
  cvssVector: V3,
  cvssVersion: "3.1",
  cvssScore: "10",
  severity: "critical",
  epssScore: "0.9",
  epssPercentile: 0.99,
  kev: true,
  kevAddedOn: "2021-12-10",
  kevDueOn: "2021-12-24",
  affectedPurls: ["pkg:maven/log4j"],
  enrichedAt: AT,
  createdAt: AT,
  updatedAt: AT,
};

const statementRow = {
  id: "s1",
  productId: "p1",
  versionId: "ver1",
  version: "1.0.0",
  vulnerabilityId: "v1",
  vulnId: "CVE-2021-44228",
  status: "not_affected",
  justification: "component_not_present",
  impactStatement: "No log4j",
  actionStatement: "None",
  updatedAt: AT,
};

const advisoryRow = {
  id: "a1",
  organizationId: "org",
  trackingId: "ACME-SA-1",
  title: "Title",
  summary: "Summary",
  productId: "p1",
  severity: "high",
  status: "final",
  revision: "2",
  initialReleaseAt: AT,
  currentReleaseAt: AT,
  createdAt: AT,
  updatedAt: AT,
};

const publishedRow = {
  trackingId: "ACME-SA-1",
  title: "Title",
  summary: "Summary",
  status: "final",
  version: "2",
  initialReleaseAt: AT,
  currentReleaseAt: AT,
  revisionHistory: [{ number: "1", date: AT, summary: "First" }],
  product: { key: "acme", name: "Acme", versions: ["1.0.0"] },
  vulnerabilities: [
    {
      vulnId: "CVE-2021-44228",
      aliases: ["GHSA-x"],
      summary: "Log4Shell",
      details: "Details",
      cvssVector: V3,
      cvssVersion: "3.1",
      cvssScore: 10,
      kevAddedOn: "2021-12-10",
      statements: [
        {
          version: "1.0.0",
          status: "affected",
          justification: "component_not_present",
          impactStatement: "i",
          actionStatement: "a",
        },
      ],
    },
  ],
};

const record: OsvRecord = {
  id: "GHSA-x",
  aliases: ["CVE-2021-44228"],
  summary: "Log4Shell",
  details: "Details",
  published: AT,
  modified: AT,
  severity: [
    { type: "CVSS_V4", score: V4 },
    { type: "CVSS_V3", score: V3 },
  ],
  databaseSeverity: "CRITICAL",
  affectedPurls: ["pkg:maven/log4j"],
  references: [{ type: "WEB", url: "https://example.test" }],
};

function feedOf(overrides: Partial<VulnerabilityFeed> = {}): VulnerabilityFeed {
  return {
    apiVersion: 1,
    name: "fake",
    osv: async () => ({ ok: true, data: record }),
    epss: async () => ({
      ok: true,
      data: {
        "CVE-2021-44228": { score: 0.9, percentile: 0.99, date: "2026-10-31" },
      },
    }),
    kev: async () => ({
      ok: true,
      data: {
        "CVE-2021-44228": {
          dateAdded: "2021-12-10",
          dueDate: undefined,
          knownRansomwareUse: true,
        },
      },
    }),
    ...overrides,
  } as VulnerabilityFeed;
}

const failure = { ok: false as const, error: { kind: "unavailable" as const } };

describe("createAdvisories reads and writes", () => {
  it("maps products, versions and components", async () => {
    const { transport, call } = fakeTransport({
      list_advisory_products: [productRow],
      create_product_version: versionRow,
      list_product_versions: [versionRow],
      list_sbom_components: [
        {
          id: "c1",
          bomRef: "ref",
          type: "library",
          name: "log4j",
          version: "2.0",
          purl: "pkg:maven/log4j",
          cpe: "cpe",
          supplier: "Apache",
          licenses: ["Apache-2.0"],
        },
        { id: "c2", type: "library", name: "bare", licenses: "x" },
      ],
    });

    const advisories = createAdvisories({
      transport,
      tenant: "org",
      feed: feedOf(),
    });

    const products = await advisories.products().orThrow();

    expect(products[0]).toMatchObject({
      vendor: "Acme Inc",
      description: "The app",
    });
    expect(products[0]?.archivedAt?.toString()).toBe(AT);

    const created = await advisories
      .createVersion({
        productId: "p1",
        version: "1.0.0",
        releasedAt: Temporal.Instant.from(AT),
        endOfSupportAt: Temporal.Instant.from(AT),
      })
      .orThrow();

    expect(created.sbomComponents).toBe(3);
    expect(call.mock.calls[1]?.[2]).toMatchObject({ released_at: AT });

    const versions = await advisories.versions("p1").orThrow();

    expect(versions[0]?.sbomSpec).toBe("1.6");

    const components = await advisories
      .components({ versionId: "ver1", limit: 5 })
      .orThrow();

    expect(components[0]).toMatchObject({
      bomRef: "ref",
      licenses: ["Apache-2.0"],
    });
    expect(components[1]).toMatchObject({ bomRef: undefined, licenses: [] });
  });

  it("imports a CycloneDX BOM and prefixes the group", async () => {
    const { transport, call } = fakeTransport({ import_sbom: versionRow });

    const advisories = createAdvisories({
      transport,
      tenant: "org",
      feed: feedOf(),
    });

    await advisories
      .importSbom({
        versionId: "ver1",
        bom: {
          bomFormat: "CycloneDX",
          specVersion: "1.6",
          serialNumber: "urn:uuid:3e671687-395b-41f5-a30f-a58921a69b79",
          components: [
            { name: "core", group: "org.acme", version: "1" },
            { name: "plain" },
          ],
        },
      })
      .orThrow();

    const args = call.mock.calls[0]?.[2] as {
      components: { name: string }[];
      spec_version: string;
    };

    expect(args.components.map((c) => c.name)).toEqual([
      "org.acme/core",
      "plain",
    ]);
    expect(args.spec_version).toBe("1.6");

    const refused = await advisories.importSbom({
      versionId: "ver1",
      bom: { nope: true },
    });

    expect(refused.ok).toBe(false);
  });

  it("maps vulnerabilities and sparse rows", async () => {
    const { transport, call } = fakeTransport({
      save_vulnerability: vulnerabilityRow,
      list_vulnerabilities: [
        vulnerabilityRow,
        {
          ...vulnerabilityRow,
          cvssScore: undefined,
          epssScore: null,
          aliases: "x",
          kev: "yes",
        },
      ],
    });

    const advisories = createAdvisories({
      transport,
      tenant: "org",
      feed: feedOf(),
    });

    const saved = await advisories
      .saveVulnerability({ vulnId: "CVE-2021-44228", cvssVector: V4 })
      .orThrow();

    expect(saved).toMatchObject({ cvssScore: 10, epssScore: 0.9, kev: true });
    expect(call.mock.calls[0]?.[2]).toMatchObject({
      cvss_version: "4.0",
      cvss_score: null,
    });

    const plain = await advisories
      .saveVulnerability({ vulnId: "CVE-2021-44228" })
      .orThrow();

    expect(plain.id).toBe("v1");

    const listed = await advisories
      .vulnerabilities({ kevOnly: true, limit: 2 })
      .orThrow();

    expect(listed[1]).toMatchObject({
      cvssScore: undefined,
      epssScore: undefined,
      aliases: [],
      kev: false,
    });
    expect(call.mock.calls.at(-1)?.[2]).toMatchObject({
      kev_only: true,
      max_count: 2,
    });
  });

  it("maps exposure rows and refuses an unknown VEX status", async () => {
    const row = {
      vulnerabilityId: "v1",
      vulnId: "CVE-1",
      severity: "high",
      cvssScore: 7.5,
      epssScore: 0.1,
      kev: true,
      componentId: "c1",
      componentName: "log4j",
      componentVersion: "2.0",
      purl: "pkg:maven/log4j",
      vexStatus: "fixed",
    };

    const { transport } = fakeTransport({
      version_exposure: [row, { ...row, vexStatus: null, severity: null }],
    });

    const advisories = createAdvisories({
      transport,
      tenant: "org",
      feed: feedOf(),
    });

    const exposure = await advisories.exposure("ver1").orThrow();

    expect(exposure[0]?.vexStatus).toBe("fixed");
    expect(exposure[1]).toMatchObject({
      vexStatus: undefined,
      severity: undefined,
    });

    const bad = fakeTransport({
      version_exposure: [{ ...row, vexStatus: "bogus" }],
    });

    const broken = await createAdvisories({
      transport: bad.transport,
      tenant: "org",
      feed: feedOf(),
    }).exposure("ver1");

    expect(broken.ok).toBe(false);
  });

  it("saves and lists VEX statements and rejects malformed ones", async () => {
    const { transport, call } = fakeTransport({
      save_vex_statement: statementRow,
      list_vex_statements: [
        statementRow,
        {
          ...statementRow,
          status: "affected",
          justification: null,
          versionId: null,
          version: null,
        },
      ],
    });

    const advisories = createAdvisories({
      transport,
      tenant: "org",
      feed: feedOf(),
    });

    const saved = await advisories
      .saveVexStatement({
        productId: "p1",
        vulnerabilityId: "v1",
        status: "not_affected",
        versionId: "ver1",
        justification: "component_not_present",
        impactStatement: "No log4j",
        actionStatement: "None",
      })
      .orThrow();

    expect(saved.justification).toBe("component_not_present");
    expect(call.mock.calls[0]?.[2]).toMatchObject({ version_id: "ver1" });

    const listed = await advisories
      .vexStatements({ productId: "p1", versionId: "ver1" })
      .orThrow();

    expect(listed[1]).toMatchObject({
      justification: undefined,
      versionId: undefined,
    });

    const bad = fakeTransport({
      list_vex_statements: [{ ...statementRow, justification: "bogus" }],
    });

    const result = await createAdvisories({
      transport: bad.transport,
      tenant: "org",
      feed: feedOf(),
    }).vexStatements({ productId: "p1" });

    expect(result.ok).toBe(false);
  });

  it("renders an OpenVEX document and reports an unknown product", async () => {
    const { transport } = fakeTransport({
      list_vex_statements: [statementRow],
      list_advisory_products: [productRow],
    });

    const advisories = createAdvisories({
      transport,
      tenant: "org",
      feed: feedOf(),
    });

    const document = await advisories
      .openVex({
        productId: "p1",
        author: "Acme",
        role: "Vendor",
        purl: "pkg:generic/acme",
        id: "https://example.test/vex",
        version: 2,
      })
      .orThrow();

    expect(document["version"]).toBe(2);

    const plain = await advisories.openVex({ productId: "p1", author: "Acme" });

    expect(plain.ok).toBe(true);

    const missing = await advisories.openVex({
      productId: "other",
      author: "Acme",
    });

    expect(!missing.ok && missing.error.kind).toBe("not_found");

    const failing = fakeTransport({
      list_vex_statements: () => {
        throw new Error("down");
      },
      list_advisory_products: [productRow],
    });

    const down = await createAdvisories({
      transport: failing.transport,
      tenant: "org",
      feed: feedOf(),
    }).openVex({ productId: "p1", author: "Acme" });

    expect(down.ok).toBe(false);

    const noProducts = fakeTransport({
      list_vex_statements: [],
      list_advisory_products: () => {
        throw new Error("down");
      },
    });

    const downProducts = await createAdvisories({
      transport: noProducts.transport,
      tenant: "org",
      feed: feedOf(),
    }).openVex({ productId: "p1", author: "Acme" });

    expect(downProducts.ok).toBe(false);
  });

  it("saves, publishes, lists and reads advisories", async () => {
    const { transport, call } = fakeTransport({
      save_advisory: advisoryRow,
      publish_advisory: advisoryRow,
      list_advisories: [advisoryRow, { ...advisoryRow, status: "draft" }],
      get_advisory: {
        ...advisoryRow,
        revision: undefined,
        vulnerabilityIds: ["v1"],
        revisionHistory: [{ number: "1", date: AT, summary: "First" }],
      },
    });

    const advisories = createAdvisories({
      transport,
      tenant: "org",
      feed: feedOf(),
    });

    const saved = await advisories
      .saveAdvisory({
        trackingId: "ACME-SA-1",
        title: "Title",
        summary: "Summary",
        productId: "p1",
        vulnerabilityIds: ["v1"],
        severity: "high",
        id: "a1",
      })
      .orThrow();

    expect(saved.revision).toBe(2);

    await advisories.publishAdvisory({ id: "a1" }).orThrow();
    await advisories
      .publishAdvisory({ id: "a1", status: "interim", note: "n" })
      .orThrow();

    expect(call.mock.calls[1]?.[2]).toMatchObject({ status: "final" });
    expect(call.mock.calls[2]?.[2]).toMatchObject({
      status: "interim",
      note: "n",
    });

    const listed = await advisories.advisories({ status: "final" }).orThrow();

    expect(listed).toHaveLength(2);

    const detail = await advisories.getAdvisory("a1").orThrow();

    expect(detail).toMatchObject({ revision: 0, vulnerabilityIds: ["v1"] });
    expect(detail.revisionHistory[0]?.number).toBe("1");

    const bad = fakeTransport({
      get_advisory: { ...advisoryRow, status: "bogus" },
    });

    const result = await createAdvisories({
      transport: bad.transport,
      tenant: "org",
      feed: feedOf(),
    }).getAdvisory("a1");

    expect(result.ok).toBe(false);
  });

  it("tolerates a detail without lists", async () => {
    const { transport } = fakeTransport({ get_advisory: advisoryRow });

    const detail = await createAdvisories({
      transport,
      tenant: "org",
      feed: feedOf(),
    })
      .getAdvisory("a1")
      .orThrow();

    expect(detail.vulnerabilityIds).toEqual([]);
    expect(detail.revisionHistory).toEqual([]);
  });
});

describe("csafSource reads", () => {
  it("maps summaries and published advisories", async () => {
    const { transport } = fakeTransport({
      list_published_advisories: [publishedRow],
      get_published_advisory: publishedRow,
    });

    const source = createAdvisories({ transport, feed: feedOf() }).csafSource(
      "org",
    );

    const listed = await source.listPublished().orThrow();

    expect(listed[0]).toMatchObject({ trackingId: "ACME-SA-1", version: 2 });

    const found = await source.getPublished("ACME-SA-1").orThrow();

    expect(found?.vulnerabilities[0]?.statements[0]).toMatchObject({
      status: "affected",
      justification: "component_not_present",
    });
    expect(found?.product.versions).toEqual(["1.0.0"]);
  });

  it("maps a sparse published advisory", async () => {
    const { transport } = fakeTransport({
      get_published_advisory: {
        ...publishedRow,
        revisionHistory: undefined,
        vulnerabilities: undefined,
        product: { key: "acme", name: "Acme" },
      },
    });

    const found = await createAdvisories({ transport, feed: feedOf() })
      .csafSource("org")
      .getPublished("ACME-SA-1")
      .orThrow();

    expect(found).toMatchObject({
      revisionHistory: [],
      vulnerabilities: [],
      product: { versions: [] },
    });
  });

  it("answers undefined for a missing or non-record row", async () => {
    const { transport } = fakeTransport({ get_published_advisory: null });

    const source = createAdvisories({ transport, feed: feedOf() }).csafSource(
      "org",
    );

    expect(await source.getPublished("x").orThrow()).toBeUndefined();

    const missing = fakeTransport({
      get_published_advisory: () => {
        throw new Error("down");
      },
    });

    const failed = await createAdvisories({
      transport: missing.transport,
      feed: feedOf(),
    })
      .csafSource("org")
      .getPublished("x");

    expect(failed.ok).toBe(false);
  });

  it("rejects a published advisory with an unknown status", async () => {
    const { transport } = fakeTransport({
      get_published_advisory: { ...publishedRow, status: "draft" },
      list_published_advisories: [{ ...publishedRow, status: "draft" }],
    });

    const source = createAdvisories({ transport, feed: feedOf() }).csafSource(
      "org",
    );

    expect((await source.getPublished("x")).ok).toBe(false);
    expect((await source.listPublished()).ok).toBe(false);
  });

  it("rejects a statement with an unknown status", async () => {
    const statement = publishedRow.vulnerabilities[0]?.statements[0];

    const { transport } = fakeTransport({
      get_published_advisory: {
        ...publishedRow,
        vulnerabilities: [
          {
            ...publishedRow.vulnerabilities[0],
            statements: [{ ...statement, status: "bogus" }],
          },
        ],
      },
    });

    const result = await createAdvisories({ transport, feed: feedOf() })
      .csafSource("org")
      .getPublished("x");

    expect(result.ok).toBe(false);
  });
});

describe("enrichDue feed branches", () => {
  const due = { vulnerabilities_due: [{ vulnId: "CVE-2021-44228" }] };

  it("sends the record, the EPSS score and the KEV entry", async () => {
    let enrichment: Record<string, unknown> = {};

    const { transport } = fakeTransport({
      ...due,
      record_vulnerability_enrichment: (args: Record<string, unknown>) => {
        enrichment = args["enrichment"] as Record<string, unknown>;

        return vulnerabilityRow;
      },
    });

    const report = await createAdvisories({
      transport,
      tenant: "org",
      feed: feedOf(),
    })
      .enrichDue({ limit: 5, staleAfter: "2 days" })
      .orThrow();

    expect(report.enriched).toBe(1);
    expect(enrichment).toMatchObject({
      cvssVersion: "3.1",
      cvssScore: 10,
      summary: "Log4Shell",
      epss: { score: 0.9 },
      kev: { addedOn: "2021-12-10", dueOn: null, ransomware: true },
    });
  });

  it("keeps a vector without a score", async () => {
    let enrichment: Record<string, unknown> = {};

    const { transport } = fakeTransport({
      ...due,
      record_vulnerability_enrichment: (args: Record<string, unknown>) => {
        enrichment = args["enrichment"] as Record<string, unknown>;

        return vulnerabilityRow;
      },
    });

    await createAdvisories({
      transport,
      tenant: "org",
      feed: feedOf({
        osv: () =>
          AsyncResult.ok({
            ...record,
            severity: [{ type: "CVSS_V4", score: V4 }],
          }),
      }),
    })
      .enrichDue({ signal: new AbortController().signal })
      .orThrow();

    expect(enrichment["cvssVersion"]).toBe("4.0");
    expect(enrichment["cvssScore"]).toBeUndefined();
  });

  it("counts a failing OSV or EPSS read and continues", async () => {
    const { transport } = fakeTransport({
      vulnerabilities_due: [{ vulnId: "CVE-1" }, { vulnId: "CVE-2" }],
    });

    const osv = await createAdvisories({
      transport,
      tenant: "org",
      feed: feedOf({ osv: async () => failure } as never),
    })
      .enrichDue()
      .orThrow();

    expect(osv).toMatchObject({ checked: 2, failed: 2 });

    const epss = await createAdvisories({
      transport,
      tenant: "org",
      feed: feedOf({ epss: async () => failure } as never),
    })
      .enrichDue()
      .orThrow();

    expect(epss).toMatchObject({ failed: 2 });
  });

  it("returns the KEV failure and counts a failed write", async () => {
    const { transport } = fakeTransport(due);

    const kev = await createAdvisories({
      transport,
      tenant: "org",
      feed: feedOf({ kev: async () => failure } as never),
    }).enrichDue();

    expect(kev.ok).toBe(false);

    const writing = fakeTransport({
      ...due,
      record_vulnerability_enrichment: () => {
        throw new Error("down");
      },
    });

    const report = await createAdvisories({
      transport: writing.transport,
      tenant: "org",
      feed: feedOf(),
    })
      .enrichDue()
      .orThrow();

    expect(report.failed).toBe(1);
  });

  it("returns the due-list failure and the tenant failure", async () => {
    const broken = fakeTransport({
      vulnerabilities_due: () => {
        throw new Error("down");
      },
    });

    const result = await createAdvisories({
      transport: broken.transport,
      tenant: "org",
      feed: feedOf(),
    }).enrichDue();

    expect(result.ok).toBe(false);

    const none = await createAdvisories({
      transport: broken.transport,
      feed: feedOf(),
    }).enrichDue();

    expect(!none.ok && none.error.hint).toBe("TENANT_REQUIRED");
  });
});
