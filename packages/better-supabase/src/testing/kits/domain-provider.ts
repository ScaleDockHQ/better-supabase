import type {
  DomainProvider,
  DomainProviderStatus,
} from "../../blocks/domains/provider.ts";
import type { ConformanceReport } from "../conformance.ts";

import { conform, expect } from "../conformance.ts";

export interface TestDomainProviderOptions {
  /**
   * A hostname the kit may add to the platform's project and remove again, such
   * as `conformance.example.com` on a test project. It must not be on the
   * project before the run.
   */
  readonly hostname: string;
}

function recordsValid(status: DomainProviderStatus, where: string): void {
  for (const [index, record] of status.records.entries()) {
    expect(
      record.type.length > 0 &&
        record.name.length > 0 &&
        record.value.length > 0,
      `${where}: record ${index} lacks a type, name or value`,
    );
  }

  expect(
    !status.verified || status.records.length === 0,
    `${where}: a verified hostname still lists records`,
  );
}

/**
 * Runs the `DomainProvider` contract against `provider`: the API version,
 * adding `hostname` (twice, since adding is idempotent), its status, verifying
 * it, removing it, a second remove that returns `false`, and a status of
 * `undefined` afterwards. Run it against a test project: it adds the hostname
 * and removes it again.
 */
export function testDomainProvider(
  provider: DomainProvider,
  options: TestDomainProviderOptions,
): Promise<ConformanceReport> {
  const { hostname } = options;

  return conform(`DomainProvider "${provider.name}"`, [
    [
      "has apiVersion 1 and a name",
      () => {
        const version: unknown = provider.apiVersion;
        expect(version === 1, `apiVersion is ${String(version)}`);
        expect(provider.name.length > 0, "name is empty");
      },
    ],
    [
      "adds the hostname, and adding it again returns its status",
      async () => {
        const added = await provider.add(hostname).orThrow();
        expect(
          added.hostname === hostname,
          `add returned hostname "${added.hostname}"`,
        );
        recordsValid(added, "add");

        const again = await provider.add(hostname).orThrow();
        expect(
          again.hostname === hostname,
          `a second add returned hostname "${again.hostname}"`,
        );
      },
    ],
    [
      "reports the status of the added hostname",
      async () => {
        const status = await provider.status(hostname).orThrow();
        expect(status !== undefined, "status is undefined after add");
        expect(
          status.hostname === hostname,
          `status returned hostname "${status.hostname}"`,
        );
        recordsValid(status, "status");
      },
    ],
    [
      "verifies the hostname, or reports it unverified without an error",
      async () => {
        const verified = await provider.verify(hostname);
        expect(
          verified.ok,
          `verify failed with ${verified.ok ? "" : verified.error.kind}`,
        );
        expect(
          verified.data.hostname === hostname,
          `verify returned hostname "${verified.data.hostname}"`,
        );
        recordsValid(verified.data, "verify");
      },
    ],
    [
      "removes the hostname, and a second remove returns false",
      async () => {
        const removed = await provider.remove(hostname).orThrow();
        expect(removed, "remove returned false for an added hostname");

        const again = await provider.remove(hostname).orThrow();
        expect(!again, "a second remove returned true");
      },
    ],
    [
      "has no status for the removed hostname",
      async () => {
        const status = await provider.status(hostname).orThrow();
        expect(status === undefined, "status is not undefined after remove");
      },
    ],
  ]);
}
