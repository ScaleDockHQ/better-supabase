import { describe, expect, it } from "vitest";

import type { GateRpc } from "../../src/core/gates.ts";
import type { ReadSetEntry } from "../../src/core/spec.ts";

import { openGates } from "../../src/core/gates.ts";
import { AsyncResult, ok } from "../../src/core/result.ts";

function entry(permission: string, id?: string): ReadSetEntry {
  // SAFETY: openGates reads only the gate of an entry.
  return {
    gate: { scope: "tenant", permission, ...(id === undefined ? {} : { id }) },
  } as unknown as ReadSetEntry;
}

describe("openGates", () => {
  it("asks every distinct gate in one wave and each gate once", async () => {
    let inFlight = 0;
    let peak = 0;
    const asked: string[] = [];

    const rpc: GateRpc = (name, args) =>
      AsyncResult.from(async () => {
        asked.push(name);
        inFlight += 1;
        peak = Math.max(peak, inFlight);
        await new Promise<void>((resolve) => {
          setTimeout(resolve, 5);
        });
        inFlight -= 1;

        return ok(
          name === "current_tenant_id" ? "t1" : args["permission"] !== "b",
        );
      });

    const result = await openGates(
      rpc,
      {
        free: {} as ReadSetEntry,
        a: entry("a"),
        a2: entry("a"),
        b: entry("b"),
        c: entry("c", "t2"),
      },
      undefined,
    );

    expect(result.ok && [...result.data].toSorted()).toEqual([
      "a",
      "a2",
      "c",
      "free",
    ]);
    expect(asked.filter((name) => name === "current_tenant_id")).toHaveLength(
      1,
    );
    expect(asked.filter((name) => name === "can")).toHaveLength(3);
    expect(peak).toBe(3);
  });

  it("skips the tenant lookup when every gate names its id", async () => {
    const asked: string[] = [];

    const rpc: GateRpc = (name) =>
      AsyncResult.from(async () => {
        asked.push(name);

        return ok(true);
      });

    await openGates(rpc, { a: entry("a", "t1") }, undefined);

    expect(asked).toEqual(["can"]);
  });
});
