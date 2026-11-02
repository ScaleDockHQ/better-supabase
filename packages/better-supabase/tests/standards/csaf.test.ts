import { describe, expect, it } from "vitest";

import type {
  CsafSource,
  PublishedAdvisory,
} from "../../src/blocks/advisories/index.ts";

import {
  createCsafHandler,
  csafFileName,
  renderCsaf,
} from "../../src/blocks/advisories/index.ts";
import { AsyncResult } from "../../src/core/result.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";

const advisory: PublishedAdvisory = {
  trackingId: "ACME-SA-2026-001",
  title: "Log4Shell in Acme App",
  summary: "Acme App bundles a vulnerable Log4j.",
  status: "final",
  version: 2,
  initialReleaseAt: Temporal.Instant.from("2026-02-01T10:00:00Z"),
  currentReleaseAt: Temporal.Instant.from("2026-02-03T10:00:00Z"),
  revisionHistory: [
    {
      number: "1",
      date: Temporal.Instant.from("2026-02-01T10:00:00Z"),
      summary: "Initial release",
    },
    {
      number: "2",
      date: Temporal.Instant.from("2026-02-03T10:00:00Z"),
      summary: "Fixed in 2.1.0",
    },
  ],
  product: { key: "acme-app", name: "Acme App", versions: ["2.0.0", "2.1.0"] },
  vulnerabilities: [
    {
      vulnId: "CVE-2021-44228",
      aliases: ["GHSA-jfh8-c2jp-5v3q"],
      summary: "Remote code injection",
      details: undefined,
      cvssVector: "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:C/C:H/I:H/A:H",
      cvssVersion: "3.1",
      cvssScore: 10,
      kevAddedOn: "2021-12-10",
      statements: [
        {
          version: "2.0.0",
          status: "affected",
          justification: undefined,
          impactStatement: undefined,
          actionStatement: "Upgrade to 2.1.0.",
        },
        {
          version: "2.1.0",
          status: "fixed",
          justification: undefined,
          impactStatement: undefined,
          actionStatement: undefined,
        },
      ],
    },
  ],
};

const publisher = {
  name: "Acme",
  namespace: "https://acme.example",
  contactDetails: "security@acme.example",
};

const source: CsafSource = {
  listPublished: () =>
    AsyncResult.ok([
      {
        trackingId: advisory.trackingId,
        title: advisory.title,
        status: advisory.status,
        version: advisory.version,
        initialReleaseAt: advisory.initialReleaseAt,
        currentReleaseAt: advisory.currentReleaseAt,
      },
    ]),
  getPublished: (trackingId) =>
    AsyncResult.ok(trackingId === advisory.trackingId ? advisory : undefined),
};

describe("renderCsaf", () => {
  const document = renderCsaf(advisory, { publisher }) as {
    document: Record<string, unknown> & { tracking: Record<string, unknown> };
    product_tree: unknown;
    vulnerabilities: readonly Record<string, unknown>[];
  };

  it("writes the document header from the advisory", () => {
    expect(document.document["category"]).toBe("csaf_security_advisory");
    expect(document.document["csaf_version"]).toBe("2.0");
    expect(document.document["title"]).toBe(advisory.title);
    expect(document.document.tracking).toMatchObject({
      id: "ACME-SA-2026-001",
      status: "final",
      version: "2",
      initial_release_date: "2026-02-01T10:00:00Z",
      current_release_date: "2026-02-03T10:00:00Z",
    });
    expect(document.document["publisher"]).toMatchObject({
      category: "vendor",
      name: "Acme",
      namespace: "https://acme.example",
    });
  });

  it("states each version's status under the matching product group", () => {
    const [vulnerability] = document.vulnerabilities;

    const status = vulnerability?.["product_status"] as Record<
      string,
      readonly string[]
    >;

    expect(vulnerability?.["cve"]).toBe("CVE-2021-44228");
    expect(status["known_affected"]).toHaveLength(1);
    expect(status["fixed"]).toHaveLength(1);
    expect(JSON.stringify(document.product_tree)).toContain("2.1.0");
    expect(vulnerability?.["scores"]).toBeDefined();
  });
});

describe("csafFileName", () => {
  it("lowercases a tracking id and replaces what the spec forbids", () => {
    expect(csafFileName("ACME-SA-2026-001")).toBe("acme-sa-2026-001");
    expect(csafFileName("Acme SA/1")).toBe("acme_sa_1");
  });
});

describe("createCsafHandler", () => {
  const handler = createCsafHandler({
    source,
    publisher,
    baseUrl: "https://acme.example/",
  });

  const get = (path: string, method = "GET") =>
    handler(new Request(`https://acme.example${path}`, { method }));

  it("serves provider-metadata.json", async () => {
    const response = await get("/.well-known/csaf/provider-metadata.json");
    const body = (await response.json()) as Record<string, unknown>;

    expect(response.status).toBe(200);
    expect(body["metadata_version"]).toBe("2.0");
    expect(body["role"]).toBe("csaf_publisher");
    expect(body["canonical_url"]).toBe(
      "https://acme.example/.well-known/csaf/provider-metadata.json",
    );
    expect(response.headers.get("cache-control")).toBe("public, max-age=300");
  });

  it("lists the documents in index.txt and changes.csv", async () => {
    const index = await (await get("/.well-known/csaf/white/index.txt")).text();

    const changes = await (
      await get("/.well-known/csaf/white/changes.csv")
    ).text();

    expect(index).toBe("2026/acme-sa-2026-001.json\n");
    expect(changes).toBe(
      '"2026/acme-sa-2026-001.json","2026-02-03T10:00:00Z"\n',
    );
  });

  it("serves a document and its hashes", async () => {
    const path = "/.well-known/csaf/white/2026/acme-sa-2026-001.json";
    const response = await get(path);
    const body = await response.text();
    const sha256 = await (await get(`${path}.sha256`)).text();
    const sha512 = await (await get(`${path}.sha512`)).text();

    const digest = async (algorithm: string) =>
      [
        ...new Uint8Array(
          await crypto.subtle.digest(algorithm, new TextEncoder().encode(body)),
        ),
      ]
        .map((byte) => byte.toString(16).padStart(2, "0"))
        .join("");

    expect(response.status).toBe(200);
    expect(JSON.parse(body).document.tracking.id).toBe("ACME-SA-2026-001");
    expect(sha256).toBe(`${await digest("SHA-256")}  acme-sa-2026-001.json\n`);
    expect(sha512).toBe(`${await digest("SHA-512")}  acme-sa-2026-001.json\n`);
  });

  it("answers 404 for an unknown document and 405 for a write", async () => {
    expect((await get("/.well-known/csaf/white/2026/other.json")).status).toBe(
      404,
    );
    expect((await get("/elsewhere")).status).toBe(404);
    expect(
      (await get("/.well-known/csaf/provider-metadata.json", "POST")).status,
    ).toBe(405);
  });
});

describe("csaf spec pin", () => {
  it("names the version the code follows", () => {
    expect(SPEC_PINS.csaf).toBe("2.0");
  });
});
