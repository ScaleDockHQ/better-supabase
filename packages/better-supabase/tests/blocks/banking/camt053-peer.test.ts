import { describe, expect, it, vi } from "vitest";

import type * as OptionalPeer from "../../../src/core/optional-peer.ts";

vi.mock(import("../../../src/core/optional-peer.ts"), async (load) => ({
  ...(await load<typeof OptionalPeer>()),
  importOptionalPeer: () => Promise.resolve(undefined),
}));

const { parseCamt053 } = await import("../../../src/blocks/banking/camt053.ts");

describe("parseCamt053 without fast-xml-parser", () => {
  it("says how to install the optional peer", async () => {
    await expect(
      parseCamt053(
        '<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.08"/>',
      ),
    ).rejects.toThrow("pnpm add fast-xml-parser");
  });
});
