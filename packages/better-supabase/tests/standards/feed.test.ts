import { describe, expect, it, vi } from "vitest";

import {
  osvRecordOf,
  publicVulnerabilityFeed,
  vulnerabilityFeedOf,
} from "../../src/blocks/advisories/index.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import { testVulnerabilityFeed } from "../../src/testing/index.ts";

const osvBody = {
  id: "GHSA-jfh8-c2jp-5v3q",
  aliases: ["CVE-2021-44228"],
  summary: "Remote code injection in Log4j",
  details: "Log4j2 JNDI features do not protect against attacker control.",
  published: "2021-12-10T00:40:56Z",
  modified: "2024-01-01T00:00:00Z",
  severity: [
    { type: "CVSS_V3", score: "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:C/C:H/I:H/A:H" },
  ],
  database_specific: { severity: "CRITICAL" },
  affected: [
    {
      package: {
        ecosystem: "Maven",
        name: "org.apache.logging.log4j:log4j-core",
        purl: "pkg:maven/org.apache.logging.log4j/log4j-core",
      },
    },
    { package: { ecosystem: "npm", name: "left-pad" } },
  ],
  references: [{ type: "ADVISORY", url: "https://example.com/advisory" }],
};

const KEV = {
  vulnerabilities: [
    {
      cveID: "CVE-2021-44228",
      dateAdded: "2021-12-10",
      dueDate: "2021-12-24",
      knownRansomwareCampaignUse: "Known",
      requiredAction: "Apply updates.",
    },
    { cveID: "CVE-2000-0001" },
  ],
};

const EPSS = {
  data: [
    {
      cve: "CVE-2021-44228",
      epss: "0.97565",
      percentile: "0.99997",
      date: "2026-10-31",
    },
  ],
};

function fakeFetch() {
  return vi.fn<typeof fetch>(async (input) => {
    const url = String(input);

    if (url.includes("/v1/vulns/GHSA-jfh8-c2jp-5v3q")) {
      return Response.json(osvBody);
    }

    if (url.includes("/v1/vulns/CVE-2021-44228")) {
      return Response.json(osvBody);
    }

    if (url.includes("/v1/vulns/")) {
      return Response.json({ code: 5 }, { status: 404 });
    }

    if (url.includes("/epss")) {
      return Response.json(EPSS);
    }

    return Response.json(KEV);
  });
}

describe("osvRecordOf", () => {
  it("keeps version-less package URLs and the vectors", () => {
    const record = osvRecordOf(osvBody);

    expect(record?.id).toBe("GHSA-jfh8-c2jp-5v3q");
    expect(record?.aliases).toEqual(["CVE-2021-44228"]);
    expect(record?.affectedPurls).toEqual([
      "pkg:maven/org.apache.logging.log4j/log4j-core",
      "pkg:npm/left-pad",
    ]);
    expect(record?.severity[0]?.type).toBe("CVSS_V3");
    expect(record?.databaseSeverity).toBe("CRITICAL");
  });

  it("answers undefined for what is not a record", () => {
    expect(osvRecordOf({})).toBeUndefined();
    expect(osvRecordOf("x")).toBeUndefined();
  });
});

describe("publicVulnerabilityFeed", () => {
  it("reads OSV, EPSS and KEV over fetch", async () => {
    const fetcher = fakeFetch();
    const feed = publicVulnerabilityFeed({ fetch: fetcher });

    const osv = await feed.osv("CVE-2021-44228");
    const scores = await feed.epss(["CVE-2021-44228", "not-a-cve"]);
    const kev = await feed.kev();

    expect(osv.ok && osv.data?.id).toBe("GHSA-jfh8-c2jp-5v3q");
    expect(scores.ok && scores.data["CVE-2021-44228"]).toEqual({
      score: 0.97565,
      percentile: 0.99997,
      date: "2026-10-31",
    });
    expect(kev.ok && kev.data["CVE-2021-44228"]).toMatchObject({
      cveId: "CVE-2021-44228",
      dateAdded: "2021-12-10",
      dueDate: "2021-12-24",
      knownRansomwareUse: true,
    });
    expect(String(fetcher.mock.calls[1]?.[0])).toContain("cve=CVE-2021-44228");
    expect(String(fetcher.mock.calls[1]?.[0])).not.toContain("not-a-cve");
  });

  it("answers undefined for an unknown id and no call for an empty list", async () => {
    const fetcher = fakeFetch();
    const feed = publicVulnerabilityFeed({ fetch: fetcher });

    const unknown = await feed.osv("GHSA-0000-0000-0000");
    const none = await feed.epss([]);

    expect(unknown.ok && unknown.data).toBeUndefined();
    expect(none.ok && none.data).toEqual({});
    expect(fetcher).toHaveBeenCalledOnce();
  });

  it("returns rate limiting with retryAfter", async () => {
    const feed = publicVulnerabilityFeed({
      fetch: vi.fn<typeof fetch>(async () =>
        Response.json({}, { status: 429, headers: { "retry-after": "30" } }),
      ),
    });

    const result = await feed.osv("CVE-2021-44228");

    expect(result.ok).toBe(false);
    expect(!result.ok && result.error.kind).toBe("rate_limited");
  });

  it("returns a network error when the source is down", async () => {
    const feed = publicVulnerabilityFeed({
      fetch: vi.fn<typeof fetch>(async () => {
        throw new TypeError("offline");
      }),
    });

    const result = await feed.kev();

    expect(!result.ok && result.error.kind).toBe("network");
  });

  it("passes the conformance kit", async () => {
    const report = await testVulnerabilityFeed(
      publicVulnerabilityFeed({ fetch: fakeFetch() }),
      { cveId: "CVE-2021-44228" },
    );

    expect(report.checks.filter((check) => !check.ok)).toEqual([]);
  });
});

describe("vulnerabilityFeedOf", () => {
  it("refuses another API version and a name that cannot be stored", () => {
    const feed = publicVulnerabilityFeed({ fetch: fakeFetch() });

    expect(() =>
      vulnerabilityFeedOf({ ...feed, apiVersion: 2 as never }),
    ).toThrow(/feed API 2/u);
    expect(() => vulnerabilityFeedOf({ ...feed, name: "Public Feed" })).toThrow(
      /must be lowercase/u,
    );
  });
});

describe("feed spec pin", () => {
  it("names the version the code follows", () => {
    expect(SPEC_PINS.osv).toBe("1.9.0");
    expect(SPEC_PINS.epss).toBe("v5");
  });
});
