import { describe, expect, it } from "vitest";

import {
  osvRecordOf,
  publicVulnerabilityFeed,
  vulnerabilityFeedOf,
} from "../../../src/blocks/advisories/feed.ts";

type Handler = (url: string) => Response | Promise<Response>;

function feedWith(handler: Handler) {
  const urls: string[] = [];

  const fetcher = ((input: string | URL | Request) => {
    const url = String(input);
    urls.push(url);

    return Promise.resolve(handler(url));
  }) as typeof fetch;

  return { urls, feed: publicVulnerabilityFeed({ fetch: fetcher }) };
}

const json = (body: unknown, status = 200): Response =>
  Response.json(body, { status });

describe("vulnerabilityFeedOf", () => {
  const feed = publicVulnerabilityFeed();

  it("accepts a valid feed", () => {
    expect(vulnerabilityFeedOf(feed)).toBe(feed);
  });

  it("rejects another api version and a bad name", () => {
    expect(() =>
      vulnerabilityFeedOf({ ...feed, apiVersion: 2 } as never),
    ).toThrow(/API 2/u);
    expect(() => vulnerabilityFeedOf({ ...feed, name: "Bad Name" })).toThrow(
      /lowercase/u,
    );
  });
});

describe("osvRecordOf", () => {
  it("returns undefined without a record or an id", () => {
    expect(osvRecordOf("x")).toBeUndefined();
    expect(osvRecordOf({ id: "  " })).toBeUndefined();
  });

  it("reduces a sparse record", () => {
    expect(osvRecordOf({ id: "A-1" })).toEqual({
      id: "A-1",
      aliases: [],
      summary: undefined,
      details: undefined,
      published: undefined,
      modified: undefined,
      severity: [],
      databaseSeverity: undefined,
      affectedPurls: [],
      references: [],
    });
  });

  it("reduces a full record and skips malformed entries", () => {
    const record = osvRecordOf({
      id: " GHSA-1 ",
      aliases: ["CVE-2026-0001", 4, " "],
      summary: "s",
      details: "d",
      published: "2026-01-01T00:00:00Z",
      modified: "2026-01-02T00:00:00Z",
      severity: [
        { type: "CVSS_V3", score: "CVSS:3.1/AV:N" },
        { type: "CVSS_V3" },
        "no",
      ],
      database_specific: { severity: "HIGH" },
      affected: [
        { package: { purl: "pkg:npm/left-pad@1.0.0?x=1" } },
        { package: { ecosystem: "npm:registry", name: "@scope/pkg" } },
        { package: { ecosystem: "Maven", name: "org.acme:lib" } },
        { package: { ecosystem: "Unknown", name: "x" } },
        { package: { ecosystem: "npm" } },
        { package: "nope" },
        "nope",
        { package: { purl: "pkg:npm/left-pad@2" } },
      ],
      references: [
        { url: "https://a.test" },
        { type: "FIX", url: "https://b" },
        {},
        1,
      ],
    });

    expect(record).toMatchObject({
      id: "GHSA-1",
      aliases: ["CVE-2026-0001"],
      severity: [{ type: "CVSS_V3", score: "CVSS:3.1/AV:N" }],
      databaseSeverity: "HIGH",
      affectedPurls: [
        "pkg:npm/left-pad",
        "pkg:npm/%40scope/pkg",
        "pkg:maven/org.acme/lib",
      ],
      references: [
        { type: "WEB", url: "https://a.test" },
        { type: "FIX", url: "https://b" },
      ],
    });
  });
});

describe("publicVulnerabilityFeed osv", () => {
  it("reads a record and answers undefined for 404", async () => {
    const { feed, urls } = feedWith((url) =>
      url.includes("MISSING")
        ? new Response("", { status: 404 })
        : json({ id: "A/1" }),
    );

    const found = await feed.osv("A/1");
    expect(found.data?.id).toBe("A/1");
    expect(urls[0]).toContain("A%2F1");
    expect((await feed.osv("MISSING")).data).toBeUndefined();
  });

  it("maps http failures with retry-after", async () => {
    const limited = await feedWith(
      () =>
        new Response("slow down", {
          status: 429,
          headers: { "retry-after": "7" },
        }),
    ).feed.osv("A");

    expect(limited.error).toMatchObject({
      kind: "rate_limited",
      retryAfter: 7,
    });

    const broken = await feedWith(
      () => new Response("", { status: 500, headers: { "retry-after": "x" } }),
    ).feed.osv("A");

    expect(broken.error?.kind).toBe("network");
    expect(broken.error).not.toHaveProperty("retryAfter");
  });

  it("maps a network failure and rethrows an abort", async () => {
    const down = publicVulnerabilityFeed({
      fetch: () => Promise.reject(new Error("offline")),
    });

    expect((await down.osv("A")).error?.message).toContain("offline");

    const odd = publicVulnerabilityFeed({
      fetch: () => Promise.reject("text"),
    });

    expect((await odd.osv("A")).error?.message).toContain("text");

    const controller = new AbortController();
    controller.abort();

    const aborted = publicVulnerabilityFeed({
      fetch: () => Promise.reject(new Error("aborted")),
    });

    const result = await aborted.osv("A", { signal: controller.signal });

    expect(result.error?.kind).toBe("unexpected");
  });

  it("passes the signal and survives an unreadable error body", async () => {
    let seen: AbortSignal | null | undefined;

    const feed = publicVulnerabilityFeed({
      fetch: (_: unknown, init?: RequestInit) => {
        seen = init?.signal;

        return Promise.resolve({
          ok: false,
          status: 503,
          headers: new Headers(),
          text: () => Promise.reject(new Error("x")),
        } as unknown as Response);
      },
    });

    const controller = new AbortController();
    const result = await feed.osv("A", { signal: controller.signal });

    expect(seen).toBe(controller.signal);
    expect(result.error?.message).toBe("osv answered 503");
  });
});

describe("publicVulnerabilityFeed epss", () => {
  it("skips the call without a CVE id", async () => {
    const { feed, urls } = feedWith(() => json({}));

    expect((await feed.epss(["GHSA-1"])).data).toEqual({});
    expect(urls).toHaveLength(0);
  });

  it("reads scores and ignores bad rows", async () => {
    const { feed, urls } = feedWith(() =>
      json({
        data: [
          {
            cve: "CVE-2026-0001",
            epss: "0.5",
            percentile: 0.9,
            date: "2026-01-01",
          },
          {
            cve: "CVE-2026-0002",
            epss: "x",
            percentile: 0.9,
            date: "2026-01-01",
          },
          { cve: "CVE-2026-0003", epss: 1, percentile: "nope", date: "d" },
          { cve: "CVE-2026-0004", epss: 1, percentile: 1 },
          { epss: 1, percentile: 1, date: "d" },
          "row",
        ],
      }),
    );

    const result = await feed.epss(["CVE-2026-0001", "CVE-2026-0002", "bad"]);

    expect(result.data).toEqual({
      "CVE-2026-0001": { score: 0.5, percentile: 0.9, date: "2026-01-01" },
    });
    expect(urls[0]).toContain("cve=CVE-2026-0001,CVE-2026-0002");
  });

  it("answers empty for a missing body and surfaces errors", async () => {
    expect(
      (await feedWith(() => json([])).feed.epss(["CVE-2026-0001"])).data,
    ).toEqual({});
    expect(
      (
        await feedWith(() => new Response("", { status: 404 })).feed.epss([
          "CVE-2026-0001",
        ])
      ).data,
    ).toEqual({});
    expect(
      (await feedWith(() => json({ data: "x" })).feed.epss(["CVE-2026-0001"]))
        .data,
    ).toEqual({});
    expect(
      (
        await feedWith(() => new Response("", { status: 500 })).feed.epss(
          ["CVE-2026-0001"],
          { signal: new AbortController().signal },
        )
      ).error,
    ).toBeTruthy();
  });
});

describe("publicVulnerabilityFeed kev", () => {
  it("reads the catalog", async () => {
    const { feed } = feedWith(() =>
      json({
        vulnerabilities: [
          {
            cveID: "CVE-2026-0001",
            dateAdded: "2026-01-01",
            dueDate: "2026-02-01",
            knownRansomwareCampaignUse: "Known",
            requiredAction: "Patch",
          },
          { cveID: "CVE-2026-0002", dateAdded: "2026-01-02" },
          { cveID: "CVE-2026-0003" },
          "row",
        ],
      }),
    );

    const { data } = await feed.kev();

    expect(data?.["CVE-2026-0001"]).toMatchObject({
      knownRansomwareUse: true,
      dueDate: "2026-02-01",
      requiredAction: "Patch",
    });
    expect(data?.["CVE-2026-0002"]?.knownRansomwareUse).toBe(false);
    expect(Object.keys(data ?? {})).toHaveLength(2);
  });

  it("answers empty for an unexpected body", async () => {
    expect((await feedWith(() => json(5)).feed.kev({})).data).toEqual({});
    expect(
      (await feedWith(() => json({ vulnerabilities: 1 })).feed.kev()).data,
    ).toEqual({});
  });

  it("honours custom urls", async () => {
    const urls: string[] = [];

    const feed = publicVulnerabilityFeed({
      osvUrl: "https://osv.mirror",
      epssUrl: "https://epss.mirror",
      kevUrl: "https://kev.mirror/k.json",
      fetch: ((input: string) => {
        urls.push(input);

        return Promise.resolve(json({}));
      }) as typeof fetch,
    });

    await feed.osv("A");
    await feed.epss(["CVE-2026-0001"]);
    await feed.kev();

    expect(urls[0]).toMatch(/^https:\/\/osv\.mirror/u);
    expect(urls[1]).toMatch(/^https:\/\/epss\.mirror/u);
    expect(urls[2]).toBe("https://kev.mirror/k.json");
  });
});
