import { describe, expect, it, vi } from "vitest";

import type { StatsRecorder } from "../../src/core/stats.ts";
import type { CollectorView } from "../../src/next/collector.ts";

import { requestRecording } from "../../src/next/request-recording.ts";

vi.mock(import("next/headers.js"), () => ({
  headers: () => Promise.resolve(new Headers({ "x-bsb-request-id": "r1" })),
}));

vi.mock(import("../../src/next/collector.ts"), () => ({
  requestIdOf: () => "r1",
}));

const collectorWith = (entries: unknown[]): CollectorView =>
  ({
    recorderFor: () =>
      ({ entry: (e: unknown) => entries.push(e) }) as unknown as StatsRecorder,
  }) as unknown as CollectorView;

describe("requestRecording.missed", () => {
  it("records private and public misses, not remote entries", async () => {
    const entries: unknown[] = [];
    const { missed } = requestRecording(collectorWith(entries));

    missed("private", { tables: ["deals"] });
    missed("remote", { tags: ["a"] });
    missed("remote", { scope: "remote", tables: ["x"] });
    await vi.waitFor(() => {
      expect(entries).toHaveLength(2);
    });

    expect(entries).toEqual([
      { id: "deals", kind: "private", outcome: "miss" },
      { id: "a", kind: "public", outcome: "miss" },
    ]);
  });
});
