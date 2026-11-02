import { describe, expect, it } from "vitest";

import { createRank } from "../../../src/blocks/rank/index.ts";

function recorder(result: unknown) {
  const calls: { fn: string; args: unknown }[] = [];

  return {
    calls,
    transport: {
      call(_schema: string, fn: string, args: unknown) {
        calls.push({ fn, args });

        return Promise.resolve(result);
      },
    },
  };
}

describe("rank block", () => {
  it("moves a subject between two rows and into a group", async () => {
    const { calls, transport } = recorder("VV");
    const rank = createRank({ transport });
    expect(
      await rank
        .move({
          subjectType: "deal",
          subjectId: "d1",
          target: { previous: "d2", next: "d3", group: "won" },
        })
        .orThrow(),
    ).toBe("VV");
    expect(
      await rank
        .move({ subjectType: "deal", subjectId: "d1", target: {} })
        .orThrow(),
    ).toBe("VV");
    expect(calls).toEqual([
      {
        fn: "move",
        args: {
          subject_type: "deal",
          subject_id: "d1",
          previous_id: "d2",
          next_id: "d3",
          to_group: "won",
        },
      },
      {
        fn: "move",
        args: {
          subject_type: "deal",
          subject_id: "d1",
          previous_id: null,
          next_id: null,
          to_group: null,
        },
      },
    ]);
  });

  it("rebalances through the service transport, also from the job", async () => {
    const member = recorder(0);
    const service = recorder(3);

    const rank = createRank({
      transport: member.transport,
      service: service.transport,
    });

    expect(
      await rank
        .rebalance({ subjectType: "deal", tenant: "org", group: "won" })
        .orThrow(),
    ).toBe(3);
    await rank.job(
      { subjectType: "note", tenant: null, group: null },
      undefined as never,
      new AbortController().signal,
    );
    expect(member.calls).toEqual([]);
    expect(service.calls).toEqual([
      {
        fn: "rebalance_ranks",
        args: { subject_type: "deal", tenant: "org", rank_group: "won" },
      },
      {
        fn: "rebalance_ranks",
        args: { subject_type: "note", tenant: null, rank_group: null },
      },
    ]);
  });

  it("rejects a job payload that is not an object", async () => {
    const rank = createRank({ transport: recorder(0).transport });
    await expect(
      Promise.resolve(
        rank.job("deal", undefined as never, new AbortController().signal),
      ),
    ).rejects.toThrow(/rank\.rebalance needs an object payload/);
  });
});
