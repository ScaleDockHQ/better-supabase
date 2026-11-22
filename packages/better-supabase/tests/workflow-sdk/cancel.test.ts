import { describe, expect, it, vi } from "vitest";

const cancel = vi.fn(async (_options: unknown) => undefined);
const getRun = vi.fn((_id: string) => ({ cancel }));

// SAFETY: a structural stand-in for the members the helper imports.
vi.mock(import("workflow/api"), () => ({ getRun }) as never);

vi.mock(
  import("workflow/runtime"),
  () => ({ getWorld: async () => ({}) }) as never,
);

const { cancelTenantRuns } = await import("../../src/workflow-sdk/cancel.ts");

const page = (ids: string[]) => ({
  data: ids.map((runId) => ({ runId })),
  cursor: null,
  hasMore: false,
});

function worldOf(runs: Record<string, unknown>): never {
  const list = vi.fn(async (params: { status: string }) =>
    page(params.status === "running" ? ["a", "b"] : ["c"]),
  );

  // SAFETY: a structural stand-in for the two World members the helper reads.
  return { runs, analytics: { runs: { list } } } as never;
}

describe("cancelTenantRuns", () => {
  it("uses cancelMany when the World has it", async () => {
    const cancelMany = vi.fn(async ({ runIds }: { runIds: string[] }) => ({
      results: runIds.map((runId) =>
        runId === "b"
          ? { runId, outcome: "failed", code: "x", retryable: true }
          : runId === "c"
            ? { runId, outcome: "already_cancelled" }
            : { runId, outcome: "cancelled" },
      ),
    }));

    const result = await cancelTenantRuns("t1", {
      world: worldOf({ cancelMany }),
      reason: "offboarded",
    });

    expect(result).toMatchObject({
      ok: true,
      data: { requested: 3, cancelled: 1, settled: 1, failed: ["b"] },
    });
    expect(cancelMany.mock.calls[0]?.[0]).toMatchObject({
      cancelReason: "offboarded",
    });
  });

  it("cancels one by one without cancelMany", async () => {
    cancel.mockRejectedValueOnce(new Error("no"));
    const result = await cancelTenantRuns("t1", { world: worldOf({}) });
    expect(result).toMatchObject({
      ok: true,
      data: { requested: 3, cancelled: 2, failed: ["c"] },
    });
  });

  it("returns an error without a tenant", async () => {
    expect((await cancelTenantRuns("")).ok).toBe(false);
  });

  it("pages the listing up to the limit and passes the workflow name", async () => {
    const list = vi.fn(
      async (params: { status: string; pagination: { cursor?: string } }) =>
        params.pagination.cursor === undefined
          ? {
              data: [{ runId: `${params.status}-1` }],
              cursor: "p2",
              hasMore: true,
            }
          : {
              data: [{ runId: `${params.status}-2` }],
              cursor: null,
              hasMore: true,
            },
    );

    const cancelMany = vi.fn(async ({ runIds }: { runIds: string[] }) => ({
      results: runIds.map((runId) => ({
        runId,
        outcome: runId.endsWith("2") ? "not_found" : "not_cancellable",
      })),
    }));

    const result = await cancelTenantRuns("t1", {
      // SAFETY: a structural stand-in for the two World members the helper reads.
      world: { runs: { cancelMany }, analytics: { runs: { list } } } as never,
      workflowName: "nightly",
      batch: 0,
      limit: 3,
    });

    expect(result).toMatchObject({
      ok: true,
      data: { requested: 3, cancelled: 0, settled: 3, failed: [] },
    });
    expect(cancelMany).toHaveBeenCalledTimes(3);
    expect(list.mock.calls[0]?.[0]).toMatchObject({ workflowName: "nightly" });
    expect(cancelMany.mock.calls[0]?.[0]).not.toHaveProperty("cancelReason");
  });

  it("needs a World with analytics", async () => {
    const result = await cancelTenantRuns("t1", { world: {} as never });

    expect(!result.ok && result.error.message).toMatch(
      /needs a World with analytics/u,
    );
  });

  it("passes the reason to each run without cancelMany", async () => {
    cancel.mockClear();
    await cancelTenantRuns("t1", { world: worldOf({}), reason: "gone" });

    expect(cancel).toHaveBeenCalledWith({ cancelReason: "gone" });
  });
});
