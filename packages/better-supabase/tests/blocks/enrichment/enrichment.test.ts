import { describe, expect, it, vi } from "vitest";

import type { EnrichmentProvider } from "../../../src/blocks/enrichment/index.ts";

import {
  createEnrichment,
  domainOf,
  enrichmentBlock,
  enrichmentProviderOf,
  peopleDataLabsEnrichment,
} from "../../../src/blocks/enrichment/index.ts";
import { dbError } from "../../../src/core/errors.ts";
import { AsyncResult } from "../../../src/core/result.ts";
import { fakeTransport } from "../inbox/fixtures.ts";

const AT = "2026-01-01T00:00:00Z";

const companyTarget = {
  kind: "company",
  organizationId: "org",
  subjectType: "company",
  subjectId: "c1",
  name: "Acme",
  domain: "acme.com",
  website: null,
};

const personTarget = {
  kind: "person",
  organizationId: "org",
  subjectType: "person",
  subjectId: "p1",
  name: "Ada",
  email: "ada@acme.com",
  phone: "+3100",
  title: null,
  companyDomain: "acme.com",
};

const resultRow = (status: string, data: unknown = {}) => ({
  id: "e1",
  organizationId: "org",
  subjectType: "company",
  subjectId: "c1",
  provider: "test",
  status,
  data,
  filled: ["website"],
  fetchedAt: AT,
  requestedBy: null,
});

function fakeProvider(
  overrides: Partial<Pick<EnrichmentProvider, "company" | "person">> = {},
) {
  return {
    apiVersion: 1 as const,
    name: "test",
    company: vi.fn<EnrichmentProvider["company"]>(
      overrides.company ?? (() => AsyncResult.ok({ industry: "Software" })),
    ),
    person: vi.fn<EnrichmentProvider["person"]>(
      overrides.person ?? (() => AsyncResult.ok({ title: "CTO" })),
    ),
  };
}

const json = (body: unknown, status = 200, headers: HeadersInit = {}) =>
  Response.json(body, { status, headers });

describe("enrichmentProviderOf", () => {
  it("refuses another API version and a name results can't be stored under", () => {
    expect(() =>
      enrichmentProviderOf({ ...fakeProvider(), apiVersion: 2 as never }),
    ).toThrow(/enrichment provider API 2/u);
    expect(() =>
      enrichmentProviderOf({ ...fakeProvider(), name: "People Data" }),
    ).toThrow(/must be lowercase/u);
  });
});

describe("domainOf", () => {
  it("reduces a website to its host", () => {
    expect(domainOf(undefined)).toBeUndefined();
    expect(domainOf("https://www.Acme.com:443/about?x#y")).toBe("acme.com");
    expect(domainOf("acme.io")).toBe("acme.io");
    expect(domainOf("localhost")).toBeUndefined();
  });
});

describe("peopleDataLabsEnrichment", () => {
  it("looks a company up by its domain and maps the profile", async () => {
    const fetcher = vi.fn<typeof fetch>(async () =>
      json({
        status: 200,
        name: "acme",
        display_name: "Acme",
        website: "www.acme.com",
        industry: "software",
        employee_count: 120,
        founded: 2001,
        location: { country: "netherlands", locality: "amsterdam" },
        linkedin_url: "linkedin.com/company/acme",
        summary: " Makes anvils. ",
        size: "",
      }),
    );

    const provider = peopleDataLabsEnrichment({
      apiKey: "key",
      fetch: fetcher,
    });

    const profile = await provider
      .company({ name: "Acme", domain: "acme.com" })
      .orThrow();

    expect(profile).toEqual({
      name: "Acme",
      domain: "acme.com",
      website: "www.acme.com",
      industry: "software",
      employees: 120,
      foundedYear: 2001,
      country: "netherlands",
      city: "amsterdam",
      linkedinUrl: "linkedin.com/company/acme",
      description: "Makes anvils.",
    });

    const [url, init] = fetcher.mock.calls[0] ?? [];

    expect(url).toBe(
      "https://api.peopledatalabs.com/v5/company/enrich?website=acme.com&name=Acme",
    );
    expect(init?.headers).toMatchObject({ "x-api-key": "key" });
    expect(init?.signal).toBeUndefined();
  });

  it("falls back to the website and the name field", async () => {
    const fetcher = vi.fn<typeof fetch>(async () => json({ name: "acme" }));
    const signal = new AbortController().signal;

    const provider = peopleDataLabsEnrichment({
      apiKey: "key",
      fetch: fetcher,
      baseUrl: "https://pdl.test",
    });

    const profile = await provider
      .company({ name: "Acme", website: "https://acme.com/", signal })
      .orThrow();

    expect(profile).toEqual({ name: "acme" });

    const [url, init] = fetcher.mock.calls[0] ?? [];

    expect(url).toBe(
      "https://pdl.test/v5/company/enrich?website=acme.com&name=Acme",
    );
    expect(init?.signal).toBe(signal);
  });

  it("reads a body that isn't an object as an empty profile", async () => {
    const provider = peopleDataLabsEnrichment({
      apiKey: "key",
      fetch: async () => json([1, 2]),
    });

    expect(await provider.company({ name: "Acme" }).orThrow()).toEqual({});
  });

  it("looks a person up and maps their job", async () => {
    const fetcher = vi.fn<typeof fetch>(async () =>
      json({
        status: 200,
        likelihood: 8,
        data: {
          job_title: "cto",
          mobile_phone: "+31600000000",
          job_company_name: "acme",
          location_country: "netherlands",
          location_locality: null,
          linkedin_url: "linkedin.com/in/ada",
        },
      }),
    );

    const provider = peopleDataLabsEnrichment({
      apiKey: "key",
      fetch: fetcher,
      minLikelihood: 8,
    });

    const profile = await provider
      .person({ name: "Ada", email: "ada@acme.com", companyDomain: "acme.com" })
      .orThrow();

    expect(profile).toEqual({
      title: "cto",
      phone: "+31600000000",
      companyName: "acme",
      country: "netherlands",
      linkedinUrl: "linkedin.com/in/ada",
    });
    expect(fetcher.mock.calls[0]?.[0]).toBe(
      "https://api.peopledatalabs.com/v5/person/enrich?email=ada%40acme.com&name=Ada&company=acme.com&min_likelihood=8",
    );
  });

  it("returns undefined without a match", async () => {
    const missing = peopleDataLabsEnrichment({
      apiKey: "key",
      fetch: async () => json({ status: 404 }, 404),
    });

    expect(await missing.company({ name: "Acme" }).orThrow()).toBeUndefined();
    expect(await missing.person({ name: "Ada" }).orThrow()).toBeUndefined();

    const empty = peopleDataLabsEnrichment({
      apiKey: "key",
      fetch: async () => json({ status: 200 }),
    });

    expect(
      await empty.person({ name: "Ada", phone: "+31" }).orThrow(),
    ).toBeUndefined();
  });

  it("turns a refused key, a rate limit and an outage into DbErrors", async () => {
    const answering = (response: Response) =>
      peopleDataLabsEnrichment({ apiKey: "key", fetch: async () => response });

    const refused = await answering(json({ error: "bad key" }, 401)).company({
      name: "Acme",
    });

    expect(refused.error).toMatchObject({
      kind: "unauthorized",
      hint: "ENRICHMENT_KEY_REFUSED",
    });
    expect(refused.error?.message).toContain("peopledatalabs answered 401");

    const forbidden = await answering(new Response("", { status: 403 })).person(
      { name: "Ada" },
    );

    expect(forbidden.error?.kind).toBe("unauthorized");
    expect(forbidden.error?.message).toBe("peopledatalabs answered 403");

    const limited = await answering(
      json({}, 429, { "retry-after": "30" }),
    ).company({ name: "Acme" });

    expect(limited.error).toMatchObject({
      kind: "rate_limited",
      retryAfter: 30,
    });

    const down = await answering(json({}, 503)).company({ name: "Acme" });
    expect(down.error?.kind).toBe("network");
    expect(down.error).not.toHaveProperty("retryAfter");

    const unreadable = new Response("", { status: 502 });
    vi.spyOn(unreadable, "text").mockRejectedValue(new Error("reset"));
    const lost = await answering(unreadable).company({ name: "Acme" });
    expect(lost.error?.message).toBe("peopledatalabs answered 502");
  });
});

describe("createEnrichment", () => {
  it("enriches a company and stores the match", async () => {
    const provider = fakeProvider();

    const { transport, call } = fakeTransport({
      enrichment_target: companyTarget,
      record_enrichment: resultRow("matched", { industry: "Software" }),
    });

    const enrichment = createEnrichment({ transport, provider });

    const result = await enrichment
      .enrich({ subject: { type: "company", id: "c1" } })
      .orThrow();

    expect(result).toMatchObject({
      id: "e1",
      status: "matched",
      data: { industry: "Software" },
      filled: ["website"],
      requestedBy: undefined,
    });
    expect(result.fetchedAt.toString()).toBe(AT);
    expect(provider.company).toHaveBeenCalledWith({
      name: "Acme",
      domain: "acme.com",
    });
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "record_enrichment",
      {
        subject_type: "company",
        subject_id: "c1",
        provider: "test",
        result: { status: "matched", data: { industry: "Software" } },
        fill: true,
      },
    );
  });

  it("enriches a person, and stores a miss without data", async () => {
    const signal = new AbortController().signal;

    const provider = fakeProvider({
      person: vi.fn(() => AsyncResult.ok(undefined)),
    });

    const { transport, call } = fakeTransport({
      enrichment_target: personTarget,
      record_enrichment: {
        ...resultRow("not_found", null),
        subjectType: "person",
        filled: null,
        requestedBy: "u1",
      },
    });

    const enrichment = createEnrichment({ transport, provider, fill: false });

    const result = await enrichment
      .enrich({ subject: { type: "person", id: "p1" }, signal })
      .orThrow();

    expect(result).toMatchObject({
      status: "not_found",
      data: {},
      filled: [],
      requestedBy: "u1",
    });
    expect(provider.person).toHaveBeenCalledWith({
      name: "Ada",
      email: "ada@acme.com",
      phone: "+3100",
      companyDomain: "acme.com",
      signal,
    });
    expect(call.mock.calls.at(-1)?.[2]).toMatchObject({
      result: { status: "not_found" },
      fill: false,
    });
  });

  it("lets one call override the block's fill and looks a bare person up", async () => {
    const provider = fakeProvider();

    const { transport, call } = fakeTransport({
      enrichment_target: {
        kind: "person",
        subjectType: "person",
        subjectId: "p2",
        name: "Bo",
      },
      record_enrichment: resultRow("matched"),
    });

    const enrichment = createEnrichment({ transport, provider, fill: false });

    await enrichment
      .enrich({ subject: { type: "person", id: "p2" }, fill: true })
      .orThrow();
    expect(provider.person).toHaveBeenCalledWith({ name: "Bo" });
    expect(call.mock.calls.at(-1)?.[2]).toMatchObject({ fill: true });
  });

  it("stores nothing when the target or the provider fails", async () => {
    const provider = fakeProvider({
      company: vi.fn(() =>
        AsyncResult.err(dbError("network", "provider down")),
      ),
    });

    const { transport, call } = fakeTransport({
      enrichment_target: {
        ...companyTarget,
        domain: null,
        website: "acme.com",
      },
    });

    const enrichment = createEnrichment({ transport, provider });

    const failed = await enrichment.enrich({
      subject: { type: "company", id: "c1" },
    });

    expect(failed.error?.kind).toBe("network");
    expect(provider.company).toHaveBeenCalledExactlyOnceWith({
      name: "Acme",
      website: "acme.com",
    });
    expect(call).toHaveBeenCalledOnce();

    const missing = createEnrichment({
      transport: fakeTransport({
        enrichment_target: () => {
          throw Object.assign(new Error("No company"), { code: "P0002" });
        },
      }).transport,
      provider,
    });

    const notFound = await missing.enrich({
      subject: { type: "company", id: "x" },
    });

    expect(notFound.ok).toBe(false);
    expect(provider.company).toHaveBeenCalledOnce();
  });

  it("enriches what is due, counts each outcome and stops on a rate limit", async () => {
    const outcomes = [
      AsyncResult.ok({ industry: "Software" }),
      AsyncResult.ok(undefined),
      AsyncResult.err(dbError("network", "down")),
      AsyncResult.err(dbError("rate_limited", "slow down")),
      AsyncResult.ok({ industry: "never asked" }),
    ];

    const provider = fakeProvider({
      company: vi.fn(() => outcomes.shift() ?? AsyncResult.ok(undefined)),
    });

    const logger = {
      warn: vi.fn(),
      error: vi.fn(),
      info: vi.fn(),
      debug: vi.fn(),
    };

    const targets = ["c1", "c2", "c3", "c4", "c5"].map((subjectId) => ({
      ...companyTarget,
      subjectId,
    }));

    const { transport, call } = fakeTransport({
      enrichment_due: targets,
      record_enrichment: (args: Record<string, unknown>) =>
        resultRow((args["result"] as { status: string }).status, {}),
    });

    const enrichment = createEnrichment({ transport, provider, logger });

    const report = await enrichment
      .enrichDue({ limit: 5, staleAfter: "7 days", subjectType: "company" })
      .orThrow();

    expect(report).toEqual({ checked: 4, matched: 1, notFound: 1, failed: 2 });
    expect(call.mock.calls[0]?.[2]).toEqual({
      provider: "test",
      max_count: 5,
      stale_after: "7 days",
      subject_type: "company",
    });
    expect(logger.warn).toHaveBeenCalledTimes(2);
    expect(logger.warn).toHaveBeenLastCalledWith("enrichment failed", {
      provider: "test",
      subjectType: "company",
      subjectId: "c4",
      kind: "rate_limited",
    });
  });

  it("passes defaults to the due list and returns its error", async () => {
    const empty = fakeTransport({ enrichment_due: [] });

    const report = await createEnrichment({
      transport: empty.transport,
      provider: fakeProvider(),
    })
      .enrichDue()
      .orThrow();

    expect(report).toEqual({ checked: 0, matched: 0, notFound: 0, failed: 0 });
    expect(empty.call.mock.calls[0]?.[2]).toEqual({
      provider: "test",
      max_count: null,
      stale_after: null,
      subject_type: null,
    });

    const broken = createEnrichment({
      transport: fakeTransport({
        enrichment_due: () => {
          throw new Error("boom");
        },
      }).transport,
      provider: fakeProvider(),
    });

    expect((await broken.enrichDue()).ok).toBe(false);
  });

  it("keeps going without a logger and lists a record's results", async () => {
    const provider = fakeProvider({
      company: vi.fn(() => AsyncResult.err(dbError("unauthorized", "no"))),
    });

    const { transport, call } = fakeTransport({
      enrichment_due: [companyTarget, companyTarget],
      enrichments_of: [resultRow("matched", { industry: "Software" })],
    });

    const enrichment = createEnrichment({ transport, provider });

    expect(await enrichment.enrichDue().orThrow()).toEqual({
      checked: 1,
      matched: 0,
      notFound: 0,
      failed: 1,
    });

    const results = await enrichment
      .of({ type: "company", id: "c1" })
      .orThrow();

    expect(results).toHaveLength(1);
    expect(results[0]?.data).toEqual({ industry: "Software" });
    expect(call).toHaveBeenLastCalledWith("better_supabase", "enrichments_of", {
      subject_type: "company",
      subject_id: "c1",
    });
  });

  it("refuses a provider for another API version", () => {
    expect(() =>
      createEnrichment({
        transport: fakeTransport({}).transport,
        provider: { ...fakeProvider(), apiVersion: 3 as never },
      }),
    ).toThrow(TypeError);
  });

  it("is the enrichment block", () => {
    expect(enrichmentBlock.name).toBe("enrichment");
    expect(enrichmentBlock.sql).toEqual(["enrichment"]);
  });
});
