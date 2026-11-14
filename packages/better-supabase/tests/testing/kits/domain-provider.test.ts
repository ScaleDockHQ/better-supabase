import { describe, expect, it } from "vitest";

import type {
  DomainProvider,
  DomainProviderStatus,
} from "../../../src/blocks/domains/index.ts";
import type { Result } from "../../../src/core/result.ts";

import { vercelDomainProvider } from "../../../src/blocks/domains/index.ts";
import { dbError } from "../../../src/core/errors.ts";
import { err } from "../../../src/core/result.ts";
import { ConformanceError } from "../../../src/testing/conformance.ts";
import { testDomainProvider } from "../../../src/testing/kits/domain-provider.ts";
import { fakeVercel } from "../../blocks/domains/fixtures.ts";

const options = { hostname: "conformance.acme.test" };

async function failures(provider: DomainProvider): Promise<string[]> {
  const error = await testDomainProvider(provider, options).then(
    () => undefined,
    (cause: unknown) => cause,
  );

  expect(error).toBeInstanceOf(ConformanceError);

  return (error as ConformanceError).report.checks
    .filter((check) => !check.ok)
    .map((check) => check.name);
}

describe("testDomainProvider", () => {
  it("passes the Vercel provider, with and without a challenge", async () => {
    for (const challenge of [false, true]) {
      const vercel = fakeVercel({ challenge });

      const report = await testDomainProvider(
        vercelDomainProvider(vercel.sdk, { projectId: "prj_1" }),
        options,
      );

      expect(report.subject).toBe('DomainProvider "vercel"');
      expect(report.checks.every((check) => check.ok)).toBe(true);
      expect(vercel.domains.size).toBe(0);
    }
  });

  it("fails a provider whose remove always reports true", async () => {
    const provider = vercelDomainProvider(fakeVercel().sdk, {
      projectId: "prj_1",
    });

    expect(
      await failures({
        ...provider,
        remove: (hostname, call) =>
          provider.remove(hostname, call).map(() => true),
      }),
    ).toEqual(["removes the hostname, and a second remove returns false"]);
  });

  it("fails another apiVersion and a verify that errors while pending", async () => {
    const vercel = fakeVercel({ challenge: true });
    const provider = vercelDomainProvider(vercel.sdk, { projectId: "prj_1" });

    expect(
      await failures({
        ...provider,
        // SAFETY: simulates a provider built for a newer API.
        apiVersion: 2 as never,
        verify: (hostname, call) =>
          provider
            .verify(hostname, call)
            .andThen((): Promise<Result<DomainProviderStatus>> =>
              Promise.resolve(err(dbError("invalid_input", "pending"))),
            ),
      }),
    ).toEqual([
      "has apiVersion 1 and a name",
      "verifies the hostname, or reports it unverified without an error",
    ]);
  });
});
