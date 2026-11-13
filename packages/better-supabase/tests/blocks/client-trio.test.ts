import { describe, expect, it } from "vitest";

import { BLOCK_MANIFESTS } from "../../src/blocks/registry.ts";

/**
 * The canonical trio (ADR 0821): a block's client (`create<Name>`), the generic
 * `block-controller` and the hooks over it (`useBlockQuery`,
 * `useBlockMutation`). The controller and hooks take any client, so the one
 * part a block has to supply is the client. A block that declares an entity
 * that changes after it is created has to ship one. The list holds the
 * deliberate exceptions; shrink it, never grow it.
 */
const NO_CLIENT: Readonly<Record<string, string>> = {
  // Read and written through `vaultCredentials()` in `better-supabase/credentials`,
  // which calls the service-role functions; an app never calls them from a client.
  credentials: "vaultCredentials() in better-supabase/credentials",
};

describe("block client trio", () => {
  const writable = BLOCK_MANIFESTS.filter((block) =>
    Object.values(block.entities ?? {}).some(
      (entity) =>
        entity.mutability !== undefined && entity.mutability !== "read-only",
    ),
  );

  it("gives every block with a writable entity a client, except the listed", () => {
    const missing = writable
      .filter((block) => block.create === undefined)
      .map((block) => block.name)
      .toSorted();

    expect(missing).toEqual(Object.keys(NO_CLIENT).toSorted());
  });

  it("keeps no entry for a block that has a client now", () => {
    const stale = Object.keys(NO_CLIENT).filter((name) =>
      BLOCK_MANIFESTS.some(
        (block) => block.name === name && block.create !== undefined,
      ),
    );

    expect(stale).toEqual([]);
  });
});
