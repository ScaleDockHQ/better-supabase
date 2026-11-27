import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import type { Executor } from "../../src/core/executor.ts";
import type { CollectorView } from "../../src/next/collector.ts";

import { createSupabase } from "../../src/core/define.ts";
import { ok } from "../../src/core/result.ts";
import { StatsRecorder, setAmbientStats } from "../../src/core/stats.ts";
import { requestRecording } from "../../src/next/request-recording.ts";
import { schema } from "../fixtures/generated-camel.ts";

const work = vi.hoisted(() => ({ type: "request" as string | undefined }));

const headers = vi.hoisted(() =>
  vi.fn(() => Promise.resolve(new Headers({ "x-bsb-request-id": "r1" }))),
);

vi.mock(import("next/headers.js"), () => ({ headers }));

vi.mock(
  import("next/dist/server/app-render/work-unit-async-storage.external.js"),
  () =>
    ({
      workUnitAsyncStorage: {
        getStore: () =>
          work.type === undefined ? undefined : { type: work.type },
      },
    }) as never,
);

vi.mock(import("../../src/next/collector.ts"), () => ({
  requestIdOf: () => "r1",
}));

const collectorWith = (entries: unknown[]): CollectorView =>
  ({
    recorderFor: () =>
      ({ entry: (e: unknown) => entries.push(e) }) as unknown as StatsRecorder,
  }) as unknown as CollectorView;

beforeEach(() => {
  work.type = "request";
  headers.mockClear();
});

afterEach(() => {
  setAmbientStats(undefined);
});

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

const executor: Executor = {
  name: "fake",
  execute: async () => ok({ rows: [], count: 0 }),
  rpc: async () => ok(null),
};

describe("the ambient recorder in a cache scope", () => {
  it.each(["cache", "unstable-cache", "prerender", undefined])(
    "reads no headers for a connect() query in a %s work unit",
    async (type) => {
      const request = new StatsRecorder();

      requestRecording({
        recorderFor: () => request,
      } as unknown as CollectorView);
      work.type = type;

      await createSupabase(schema).connect(executor).customers.list();

      expect(headers).not.toHaveBeenCalled();
      expect(request.snapshot().calls).toBe(0);
    },
  );

  it("counts a connect() query in a request on the request's recorder", async () => {
    const request = new StatsRecorder();

    requestRecording({
      recorderFor: () => request,
    } as unknown as CollectorView);

    await createSupabase(schema).connect(executor).customers.list();

    expect(headers).toHaveBeenCalledWith();
    expect(request.snapshot().calls).toBe(1);
  });
});
