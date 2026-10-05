import { describe, expect, it, vi } from "vitest";

import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import {
  TYPEGEN_MISSING,
  TypegenMissingError,
} from "../../../src/cli/introspect/typegen.ts";
import { snapshotFixture } from "../fixtures/library.ts";

vi.mock(import("../../../src/cli/introspect/typegen.ts"), async (original) => ({
  ...(await original()),
  validateGeneratorMetadata: () => Promise.reject(new TypegenMissingError()),
}));

describe("parseSnapshot without postgrest-typegen", () => {
  it("passes the install message through instead of calling the metadata invalid", async () => {
    await expect(parseSnapshot(snapshotFixture)).rejects.toThrow(
      new TypegenMissingError(),
    );
    expect(new TypegenMissingError().message).toBe(TYPEGEN_MISSING);
  });
});
