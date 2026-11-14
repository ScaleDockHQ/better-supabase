import { describe, expect, it } from "vitest";

import type { DomainProvider } from "../../../src/blocks/domains/index.ts";

import {
  domainProviderOf,
  vercelDomainProvider,
} from "../../../src/blocks/domains/index.ts";
import { CHALLENGE, FakeVercelError, fakeVercel } from "./fixtures.ts";

const HOST = "app.acme.test";

const RECORD = {
  type: "TXT",
  name: CHALLENGE.domain,
  value: CHALLENGE.value,
  reason: CHALLENGE.reason,
};

describe("domainProviderOf", () => {
  it("refuses another apiVersion", () => {
    const { sdk } = fakeVercel();
    const provider = vercelDomainProvider(sdk, { projectId: "prj_1" });

    expect(domainProviderOf(provider)).toBe(provider);
    expect(() =>
      // SAFETY: simulates a provider built for a newer API.
      domainProviderOf({ ...provider, apiVersion: 2 } as never),
    ).toThrow(/domain provider API 2/u);
  });
});

describe("vercelDomainProvider", () => {
  it("adds a domain with the team scope and passes the signal", async () => {
    const vercel = fakeVercel();

    const provider = vercelDomainProvider(vercel.sdk, {
      projectId: "prj_1",
      teamId: "team_1",
    });

    const { signal } = new AbortController();

    expect(provider.name).toBe("vercel");
    expect(await provider.add(HOST, { signal }).orThrow()).toEqual({
      hostname: HOST,
      verified: true,
      records: [],
    });
    expect(vercel.calls).toEqual([
      [
        "addProjectDomain",
        { idOrName: "prj_1", teamId: "team_1", requestBody: { name: HOST } },
        { signal },
      ],
    ]);
  });

  it("returns Vercel's challenge for a domain that needs one", async () => {
    const vercel = fakeVercel({ challenge: true });
    const provider = vercelDomainProvider(vercel.sdk, { projectId: "prj_1" });

    expect(await provider.add(HOST).orThrow()).toEqual({
      hostname: HOST,
      verified: false,
      records: [RECORD],
    });
    expect(vercel.calls[0]?.[2]).toBeUndefined();
  });

  it("returns the status of a domain already on the project", async () => {
    const vercel = fakeVercel({ challenge: true });
    const provider = vercelDomainProvider(vercel.sdk, { projectId: "prj_1" });

    await provider.add(HOST).orThrow();

    expect(await provider.add(HOST).orThrow()).toEqual({
      hostname: HOST,
      verified: false,
      records: [RECORD],
    });
    expect(vercel.calls.map(([method]) => method)).toEqual([
      "addProjectDomain",
      "addProjectDomain",
      "getProjectDomain",
    ]);
  });

  it("falls back to the project's domain on a 409", async () => {
    const vercel = fakeVercel();
    const provider = vercelDomainProvider(vercel.sdk, { projectId: "prj_1" });
    vercel.domains.set(HOST, { verified: true });

    vercel.failWith(
      "addProjectDomain",
      new FakeVercelError(409, "domain_already_in_use", "in use"),
    );

    expect(await provider.add(HOST).orThrow()).toEqual({
      hostname: HOST,
      verified: true,
      records: [],
    });
  });

  it("is a conflict when another project holds the domain", async () => {
    const vercel = fakeVercel({ elsewhere: { [HOST]: "prj_other" } });
    const provider = vercelDomainProvider(vercel.sdk, { projectId: "prj_1" });

    const result = await provider.add(HOST);

    expect(result.ok ? undefined : result.error).toMatchObject({
      kind: "conflict",
      status: 409,
      hint: "DOMAIN_PROVIDER_CONFLICT",
    });
  });

  it("keeps a 400 for a domain Vercel refuses", async () => {
    const vercel = fakeVercel();
    const provider = vercelDomainProvider(vercel.sdk, { projectId: "prj_1" });

    vercel.failWith(
      "addProjectDomain",
      new FakeVercelError(400, "invalid_domain", "Invalid domain name"),
    );

    const result = await provider.add("not a domain");

    expect(result.ok ? undefined : result.error).toMatchObject({
      kind: "invalid_input",
      code: "invalid_domain",
      message: "Vercel: Invalid domain name",
    });
  });

  it("verifies a domain, and reports it unverified while the challenge is missing", async () => {
    const vercel = fakeVercel({ challenge: true });
    const provider = vercelDomainProvider(vercel.sdk, { projectId: "prj_1" });

    await provider.add(HOST).orThrow();

    expect(await provider.verify(HOST).orThrow()).toEqual({
      hostname: HOST,
      verified: false,
      records: [RECORD],
    });

    vercel.publish();

    expect(await provider.verify(HOST).orThrow()).toEqual({
      hostname: HOST,
      verified: true,
      records: [],
    });
    expect(
      vercel.calls
        .filter(([method]) => method === "verifyProjectDomain")
        .map(([, request]) => request),
    ).toEqual([
      { idOrName: "prj_1", domain: HOST },
      { idOrName: "prj_1", domain: HOST },
    ]);
  });

  it("is not_found when verifying a domain the project lacks", async () => {
    const { sdk } = fakeVercel();

    const result = await vercelDomainProvider(sdk, {
      projectId: "prj_1",
    }).verify(HOST);

    expect(result.ok ? undefined : result.error.kind).toBe("not_found");
  });

  it("removes a domain, and returns false for one that isn't there", async () => {
    const vercel = fakeVercel();

    const provider = vercelDomainProvider(vercel.sdk, {
      projectId: "prj_1",
      slug: "acme",
    });

    await provider.add(HOST).orThrow();

    expect(await provider.remove(HOST).orThrow()).toBe(true);
    expect(await provider.remove(HOST).orThrow()).toBe(false);
    expect(vercel.calls.at(-1)?.[1]).toEqual({
      idOrName: "prj_1",
      slug: "acme",
      domain: HOST,
    });
  });

  it("reads the status, and undefined for a domain that isn't there", async () => {
    const vercel = fakeVercel({ challenge: true });
    const provider = vercelDomainProvider(vercel.sdk, { projectId: "prj_1" });

    expect(await provider.status(HOST).orThrow()).toBeUndefined();

    await provider.add(HOST).orThrow();

    expect(await provider.status(HOST).orThrow()).toEqual({
      hostname: HOST,
      verified: false,
      records: [RECORD],
    });
  });

  describe("maps Vercel errors", () => {
    const failing = (error: Error): DomainProvider => {
      const vercel = fakeVercel();

      for (const method of [
        "addProjectDomain",
        "verifyProjectDomain",
        "removeProjectDomain",
        "getProjectDomain",
      ] as const) {
        vercel.failWith(method, error);
      }

      return vercelDomainProvider(vercel.sdk, { projectId: "prj_1" });
    };

    it("turns a 403 into forbidden", async () => {
      const provider = failing(
        new FakeVercelError(403, "forbidden", "Not authorized"),
      );

      for (const result of [
        await provider.add(HOST),
        await provider.verify(HOST),
        await provider.remove(HOST),
        await provider.status(HOST),
      ]) {
        expect(result.ok ? undefined : result.error).toMatchObject({
          kind: "forbidden",
          code: "forbidden",
          message: "Vercel: Not authorized",
        });
      }
    });

    it("turns a 429 into rate_limited with the Retry-After seconds", async () => {
      const limited = await failing(
        new FakeVercelError(429, "rate_limited", "Slow down", {
          "retry-after": "30",
        }),
      ).add(HOST);

      expect(limited.ok ? undefined : limited.error).toMatchObject({
        kind: "rate_limited",
        retryAfter: 30,
      });

      const bare = await failing(
        new FakeVercelError(429, "rate_limited", "Slow down"),
      ).status(HOST);

      expect(bare.ok ? undefined : bare.error.kind).toBe("rate_limited");
      expect(bare.ok ? undefined : "retryAfter" in bare.error).toBe(false);
    });

    it("turns a 5xx and a network failure into network errors", async () => {
      const outage = await failing(
        new FakeVercelError(503, "internal_error", "Try again"),
      ).remove(HOST);

      expect(outage.ok ? undefined : outage.error).toMatchObject({
        kind: "network",
        hint: "DOMAIN_PROVIDER_FAILED",
      });

      const offline = await failing(new TypeError("fetch failed")).verify(HOST);

      expect(offline.ok ? undefined : offline.error).toMatchObject({
        kind: "network",
        hint: "DOMAIN_PROVIDER_FAILED",
        message: "Vercel: fetch failed",
      });
    });

    it("reads Retry-After as an HTTP date, and ignores an empty or unreadable one", async () => {
      const at = new Date(Date.now() + 90_000).toUTCString();

      const dated = await failing(
        new FakeVercelError(429, "rate_limited", "Slow down", {
          "retry-after": at,
        }),
      ).add(HOST);

      expect(dated.ok ? undefined : dated.error).toMatchObject({
        kind: "rate_limited",
        retryAfter: expect.any(Number),
      });

      for (const value of [" ", "soon"]) {
        const unread = await failing(
          new FakeVercelError(429, "rate_limited", "Slow down", {
            "retry-after": value,
          }),
        ).add(HOST);

        expect(unread.ok ? undefined : "retryAfter" in unread.error).toBe(
          false,
        );
      }
    });

    it("maps 401, 404 and 409 by status, with the body's code", async () => {
      for (const [status, kind] of [
        [401, "forbidden"],
        [404, "not_found"],
        [409, "conflict"],
      ] as const) {
        const result = await failing(
          new FakeVercelError(status, `code_${status}`, "Refused"),
        ).verify(HOST);

        expect(result.ok ? undefined : result.error).toMatchObject({
          kind,
          code: `code_${status}`,
          message: "Vercel: Refused",
        });
      }
    });

    it("uses the error's own text when the body is missing, not JSON or has no error", async () => {
      const withBody = (body: unknown): Error =>
        Object.assign(new Error("API error occurred"), {
          statusCode: 403,
          body,
        });

      for (const body of [undefined, "<html>", '{"error":"nope"}', "[]"]) {
        const result = await failing(withBody(body)).verify(HOST);

        expect(result.ok ? undefined : result.error).toMatchObject({
          kind: "forbidden",
          message: "Vercel: API error occurred",
        });
        expect(result.ok ? undefined : "code" in result.error).toBe(false);
      }

      const status = await failing(
        Object.assign(new Error("Gone"), { status: 404 }),
      ).verify(HOST);

      expect(status.ok ? undefined : status.error.kind).toBe("not_found");
    });

    it("turns another 4xx into unexpected, and an abort into aborted", async () => {
      const gone = await failing(
        new FakeVercelError(402, "payment_required", "Upgrade"),
      ).add(HOST);

      expect(gone.ok ? undefined : gone.error).toMatchObject({
        kind: "unexpected",
        hint: "DOMAIN_PROVIDER_FAILED",
      });

      const abort = new Error("The request was aborted");
      abort.name = "RequestAbortedError";

      const aborted = await failing(abort).status(HOST);

      expect(aborted.ok ? undefined : aborted.error.kind).toBe("aborted");
    });
  });
});
