import { describe, expect, it } from "vitest";

import type { DigestOutcome } from "../../src/blocks/digest.ts";

import { digestLines, runDigests } from "../../src/blocks/digest.ts";
import { dbError } from "../../src/core/errors.ts";
import { AsyncResult } from "../../src/core/result.ts";

const done = <T>(value: T): AsyncResult<T> => AsyncResult.ok(value);

describe("digestLines", () => {
  it("writes one line per entry with its path", () => {
    expect(
      digestLines([
        { label: "Invoice paid", path: "/invoices/1" },
        { label: "New comment" },
      ]),
    ).toBe("- Invoice paid (/invoices/1)\n- New comment");
  });
});

describe("runDigests", () => {
  const digests = [
    { id: "a", email: "a@example.test" },
    { id: "b", email: null },
    { id: "c", email: "c@example.test" },
  ];

  it("sends, skips and keeps a failed send pending", async () => {
    const completed: [string, DigestOutcome][] = [];

    const report = await runDigests({
      claim: () => done(digests),
      send: ({ digest }) =>
        Promise.resolve(
          digest.id === "c"
            ? { ok: false as const, error: "bounced" }
            : { ok: true as const, id: "m1" },
        ),
      complete: ({ digest, outcome }) => {
        completed.push([digest.id, outcome]);

        return done(true);
      },
    });

    expect(report).toMatchObject({
      ok: true,
      data: { claimed: 3, sent: 1, failed: 1, skipped: 1 },
    });
    expect(completed).toEqual([
      ["a", { status: "sent", providerMessageId: "m1" }],
      ["b", { status: "skipped", error: "The member has no email address" }],
      ["c", { status: "pending", error: "bounced" }],
    ]);
  });

  it("stops when a completion fails", async () => {
    const failure = dbError("unexpected", "down");

    const report = await runDigests({
      claim: () => done(digests),
      send: () => Promise.resolve({ ok: true as const, id: "m1" }),
      complete: () => AsyncResult.err(failure),
    });

    expect(report.ok).toBe(false);
  });
});
