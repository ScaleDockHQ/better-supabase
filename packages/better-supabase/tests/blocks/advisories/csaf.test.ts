import { describe, expect, it } from "vitest";

import type {
  CsafSource,
  PublishedAdvisory,
  PublishedAdvisorySummary,
  PublishedStatement,
} from "../../../src/blocks/advisories/index.ts";

import {
  createCsafHandler,
  csafFileName,
  renderCsaf,
} from "../../../src/blocks/advisories/index.ts";
import { AsyncResult } from "../../../src/core/result.ts";

const FIRST = Temporal.Instant.from("2026-01-01T00:00:00Z");
const SECOND = Temporal.Instant.from("2026-03-01T00:00:00Z");

const publisher = { name: "Acme", namespace: "https://acme.test" };

function statement(overrides: Partial<PublishedStatement>): PublishedStatement {
  return {
    version: undefined,
    status: "affected",
    justification: undefined,
    impactStatement: undefined,
    actionStatement: undefined,
    ...overrides,
  };
}

function advisoryOf(
  overrides: Partial<PublishedAdvisory> = {},
): PublishedAdvisory {
  return {
    trackingId: "ACME-SA-2026-001",
    title: "Title",
    summary: "Summary",
    status: "final",
    version: 1,
    initialReleaseAt: FIRST,
    currentReleaseAt: SECOND,
    revisionHistory: [{ number: "1", date: FIRST, summary: "First" }],
    product: { key: "acme", name: "Acme App", versions: [] },
    vulnerabilities: [],
    ...overrides,
  };
}

const summaryOf = (
  trackingId: string,
  at: Temporal.Instant,
): PublishedAdvisorySummary => ({
  trackingId,
  title: "Title",
  status: "final",
  version: 1,
  initialReleaseAt: at,
  currentReleaseAt: at,
});

type Doc = {
  document: Record<string, unknown>;
  product_tree: {
    branches: { branches: { product?: unknown; branches?: unknown[] }[] }[];
  };
  vulnerabilities: Record<string, unknown>[];
};

describe("renderCsaf", () => {
  it("renders a product without versions and optional parts", () => {
    const doc = renderCsaf(advisoryOf(), {
      publisher: {
        ...publisher,
        category: "coordinator",
        contactDetails: "sec@acme.test",
      },
      lang: "nl",
      url: "https://acme.test/doc.json",
      vendor: "Acme Vendor",
    }) as Doc;

    expect(doc.document).toMatchObject({
      lang: "nl",
      publisher: { category: "coordinator", contact_details: "sec@acme.test" },
      references: [{ category: "self", url: "https://acme.test/doc.json" }],
    });
    expect(doc.product_tree.branches[0]?.branches[0]?.product).toMatchObject({
      product_id: "CSAFPID-0001",
    });
  });

  it("renders the defaults", () => {
    const doc = renderCsaf(advisoryOf(), { publisher }) as Doc;

    expect(doc.document).toMatchObject({
      lang: "en",
      publisher: { category: "vendor" },
    });
    expect(doc.document["references"]).toBeUndefined();
  });

  it("maps every statement kind onto the version tree", () => {
    const doc = renderCsaf(
      advisoryOf({
        product: { key: "acme", name: "Acme App", versions: ["1", "2", "3"] },
        vulnerabilities: [
          {
            vulnId: "GHSA-aaaa",
            aliases: ["CVE-2026-1234"],
            summary: "Sum",
            details: "Det",
            cvssVector: "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:C/C:H/I:H/A:H",
            cvssVersion: "3.1",
            cvssScore: 10,
            kevAddedOn: "2026-02-02",
            statements: [
              statement({
                version: "1",
                status: "not_affected",
                justification: "component_not_present",
                impactStatement: "Not shipped",
              }),
              statement({ version: "1", status: "not_affected" }),
              statement({ version: "2", status: "affected" }),
              statement({
                version: "2",
                status: "affected",
                actionStatement: "Disable it",
              }),
              statement({ version: "2", status: "fixed" }),
              statement({
                version: "missing",
                status: "fixed",
                actionStatement: "Patch",
              }),
            ],
          },
          {
            vulnId: "CVE-2026-9999",
            aliases: [],
            summary: undefined,
            details: undefined,
            cvssVector: "CVSS:4.0/AV:N",
            cvssVersion: "4.0",
            cvssScore: undefined,
            kevAddedOn: undefined,
            statements: [statement({ status: "affected" })],
          },
        ],
      }),
      { publisher },
    ) as Doc;

    const [first, second] = doc.vulnerabilities;

    expect(first).toMatchObject({
      cve: "CVE-2026-1234",
      ids: [{ system_name: "OSV", text: "GHSA-aaaa" }],
      product_status: {
        known_not_affected: ["CSAFPID-0002"],
        known_affected: ["CSAFPID-0003"],
        fixed: ["CSAFPID-0003"],
        under_investigation: ["CSAFPID-0004"],
      },
      flags: [{ label: "component_not_present" }],
      threats: [{ details: "Not shipped" }],
    });
    expect(first?.["notes"]).toHaveLength(3);
    expect(first?.["scores"]).toHaveLength(1);
    expect(JSON.stringify(first?.["remediations"])).toContain("Disable it");
    expect(JSON.stringify(first?.["remediations"])).toContain(
      "No remediation is available yet.",
    );
    expect(JSON.stringify(first?.["remediations"])).toContain("Patch");
    expect(second).toMatchObject({
      cve: "CVE-2026-9999",
      title: "CVE-2026-9999",
    });
    expect(second?.["ids"]).toBeUndefined();
    expect(second?.["scores"]).toBeUndefined();
    expect(second?.["notes"]).toBeUndefined();
    expect(second?.["remediations"]).toHaveLength(1);
  });

  it("covers every version when a fixed statement names none", () => {
    const doc = renderCsaf(
      advisoryOf({
        product: { key: "acme", name: "Acme App", versions: ["1", "2"] },
        vulnerabilities: [
          {
            vulnId: "OSV-1",
            aliases: [],
            summary: undefined,
            details: undefined,
            cvssVector: undefined,
            cvssVersion: undefined,
            cvssScore: undefined,
            kevAddedOn: undefined,
            statements: [statement({ status: "fixed" })],
          },
        ],
      }),
      { publisher },
    ) as Doc;

    expect(doc.vulnerabilities[0]?.["cve"]).toBeUndefined();
    expect(doc.vulnerabilities[0]).toMatchObject({
      product_status: { fixed: ["CSAFPID-0002", "CSAFPID-0003"] },
    });
  });
});

describe("csafFileName", () => {
  it("lowercases and replaces unsafe characters", () => {
    expect(csafFileName("ACME SA/2026")).toBe("acme_sa_2026");
  });
});

function handlerOf(
  source: CsafSource,
  options: { basePath?: string; role?: "csaf_provider"; maxAge?: number } = {},
): (request: Request) => Promise<Response> {
  return createCsafHandler({
    source,
    publisher: { ...publisher, contactDetails: "sec@acme.test" },
    baseUrl: "https://acme.test/",
    lang: "en",
    ...options,
  });
}

const okSource = (
  list: PublishedAdvisorySummary[],
  found: PublishedAdvisory | undefined = advisoryOf(),
): CsafSource => ({
  listPublished: () => AsyncResult.ok(list),
  getPublished: () => AsyncResult.ok(found),
});

const get = (path: string, method = "GET"): Request =>
  new Request(`https://acme.test/.well-known/csaf/${path}`, { method });

describe("createCsafHandler", () => {
  const list = [
    summaryOf("ACME-SA-2026-001", FIRST),
    summaryOf("ACME-SA-2026-002", SECOND),
  ];

  it("refuses other methods and foreign paths", async () => {
    const handle = handlerOf(okSource(list));

    expect((await handle(get("white/index.txt", "POST"))).status).toBe(405);
    expect(
      (await handle(new Request("https://acme.test/other/x"))).status,
    ).toBe(404);
  });

  it("answers 503 when the source fails", async () => {
    const handle = handlerOf({
      listPublished: async () => ({
        ok: false,
        error: { kind: "unavailable", message: "down" },
      }),
      getPublished: () => AsyncResult.ok(undefined),
    } as unknown as CsafSource);

    expect((await handle(get("provider-metadata.json"))).status).toBe(503);
  });

  it("serves provider metadata, the index and the change list", async () => {
    const handle = handlerOf(okSource(list), {
      basePath: "/.well-known/csaf/",
      role: "csaf_provider",
      maxAge: 60,
    });

    const metadata = await handle(get("provider-metadata.json"));
    const body = (await metadata.json()) as Record<string, unknown>;

    expect(body).toMatchObject({
      role: "csaf_provider",
      last_updated: SECOND.toString(),
      publisher: { contact_details: "sec@acme.test" },
    });
    expect(metadata.headers.get("cache-control")).toContain("max-age=60");

    const index = await (await handle(get("white/index.txt"))).text();

    expect(index).toContain("2026/acme-sa-2026-002.json");

    const changes = await (await handle(get("white/changes.csv"))).text();

    expect(changes.split("\n")[0]).toContain("acme-sa-2026-002");
  });

  it("falls back to the clock for empty metadata", async () => {
    const handle = handlerOf(okSource([]));

    const body = (await (
      await handle(get("provider-metadata.json"))
    ).json()) as { last_updated: string; role: string };

    expect(body.role).toBe("csaf_publisher");
    expect(Number.isNaN(Date.parse(body.last_updated))).toBe(false);
  });

  it("serves a document and its hashes, and HEAD without a body", async () => {
    const handle = handlerOf(okSource(list));

    const doc = await handle(get("white/2026/acme-sa-2026-001.json"));

    expect(doc.status).toBe(200);
    expect(await doc.json()).toMatchObject({
      document: { category: "csaf_security_advisory" },
    });

    const sha256 = await (
      await handle(get("white/2026/acme-sa-2026-001.json.sha256"))
    ).text();

    const sha512 = await (
      await handle(get("white/2026/acme-sa-2026-001.json.sha512"))
    ).text();

    expect(sha256).toMatch(/^[0-9a-f]{64} {2}acme-sa-2026-001\.json\n$/u);
    expect(sha512).toMatch(/^[0-9a-f]{128} {2}/u);

    const head = await handle(get("white/index.txt", "HEAD"));

    expect(head.status).toBe(200);
    expect(await head.text()).toBe("");
  });

  it("answers 404 for unknown files and unreadable documents", async () => {
    const handle = handlerOf({
      listPublished: () => AsyncResult.ok(list),
      getPublished: () => AsyncResult.ok(undefined),
    });

    expect((await handle(get("white/2026/acme-sa-2026-001.json"))).status).toBe(
      404,
    );
    expect((await handle(get("white/2026/unknown.json"))).status).toBe(404);
    expect((await handle(get("nonsense"))).status).toBe(404);

    const failing = handlerOf({
      listPublished: () => AsyncResult.ok(list),
      getPublished: async () => ({
        ok: false,
        error: { kind: "unavailable", message: "down" },
      }),
    } as unknown as CsafSource);

    expect(
      (await failing(get("white/2026/acme-sa-2026-001.json"))).status,
    ).toBe(404);
  });
});
