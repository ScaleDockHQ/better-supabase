import { describe, expect, it } from "vitest";

import { createDataLifecycle } from "../../../src/blocks/data-lifecycle/index.ts";

describe("executeErasure", () => {
  it("calls erase_data_subject and returns what was removed, blanked, kept and held", async () => {
    const calls: [string, Record<string, unknown>][] = [];

    const transport = {
      call(
        _schema: string,
        fn: string,
        args: Readonly<Record<string, unknown>>,
      ) {
        calls.push([fn, { ...args }]);

        return Promise.resolve({
          removed: { "public.notes": 2 },
          blanked: { "public.consents": 1 },
          kept: { "public.data_subject_requests": 1 },
          held: { "public.field_changes": 4 },
        });
      },
    };

    const result = await createDataLifecycle({ transport })
      .executeErasure({ requestId: "r1" })
      .orThrow();

    expect(calls).toStrictEqual([["erase_data_subject", { request_id: "r1" }]]);

    expect(result).toStrictEqual({
      removed: { "public.notes": 2 },
      blanked: { "public.consents": 1 },
      kept: { "public.data_subject_requests": 1 },
      held: { "public.field_changes": 4 },
    });
  });

  it("returns empty groups when the function reports none", async () => {
    const transport = { call: () => Promise.resolve({}) };

    const result = await createDataLifecycle({ transport })
      .executeErasure({ requestId: "r1" })
      .orThrow();

    expect(result).toStrictEqual({
      removed: {},
      blanked: {},
      kept: {},
      held: {},
    });
  });
});
