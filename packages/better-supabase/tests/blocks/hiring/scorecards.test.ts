import { describe, expect, it } from "vitest";

import { createHiring } from "../../../src/blocks/hiring/index.ts";

function transport(result: (args: Record<string, unknown>) => unknown) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    call(_schema: string, fn: string, args: Record<string, unknown>) {
      calls.push([fn, args]);

      return Promise.resolve(result(args));
    },
  };
}

const CARD = {
  id: "c1",
  stage_id: null,
  reviewer_user_id: "u1",
  rating: 4,
  notes: null,
  submitted_at: "2026-10-15T09:00:00Z",
};

describe("hiring scorecards", () => {
  it("sends criterion scores and reads a card without a recommendation", async () => {
    const t = transport(() => ({
      ...CARD,
      scores: [
        { criterion: "craft", score: 5, notes: null },
        { criterion: "communication", score: 3, notes: "Clear" },
      ],
    }));

    const card = await createHiring({ transport: t })
      .score("a1", { rating: 4, scores: [{ criterion: "craft", score: 5 }] })
      .orThrow();

    expect(t.calls).toEqual([
      [
        "submit_scorecard",
        {
          application: "a1",
          rating: 4,
          recommendation: null,
          notes: null,
          scores: [{ criterion: "craft", score: 5 }],
        },
      ],
    ]);
    expect(card.recommendation).toBeUndefined();
    expect(card.scores).toEqual([
      { criterion: "craft", score: 5 },
      { criterion: "communication", score: 3, notes: "Clear" },
    ]);
  });

  it("leaves the scores argument out when the caller sends none", async () => {
    const t = transport(() => ({ ...CARD, recommendation: "yes" }));

    const card = await createHiring({ transport: t })
      .score("a1", { rating: 4, recommendation: "yes" })
      .orThrow();

    expect(t.calls[0]?.[1]).not.toHaveProperty("scores");
    expect(card.recommendation).toBe("yes");
    expect(card.scores).toBeUndefined();
  });
});
