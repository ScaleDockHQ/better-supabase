import { describe, expect, it, vi } from "vitest";

import type { AccessRequests } from "../../../src/blocks/access-requests/index.ts";

import { createDrive } from "../../../src/blocks/drive/index.ts";
import { AsyncResult } from "../../../src/core/result.ts";

function transport(results: Record<string, (args: unknown) => unknown>) {
  const calls: [string, unknown][] = [];

  return {
    calls,
    call(_schema: string, fn: string, args: unknown) {
      calls.push([fn, args]);
      const result = results[fn];

      if (!result) {
        return Promise.reject(new Error(`unexpected ${fn}`));
      }

      return Promise.resolve(result(args));
    },
  };
}

function recordAccess() {
  const requestRecord = vi.fn<AccessRequests["requestRecord"]>(() =>
    AsyncResult.ok({ id: "r1" } as never),
  );

  const records = vi.fn<AccessRequests["records"]>(() => AsyncResult.ok([]));

  return { requestRecord, records };
}

describe("drive access requests", () => {
  it("asks the access-requests block for a node, under the subject type", async () => {
    const port = recordAccess();

    const drive = createDrive({
      transport: transport({}),
      recordAccess: port,
      subjectType: "file",
    });

    const week = Temporal.Duration.from({ days: 7 });

    await drive
      .requestAccess({
        nodeId: "n1",
        input: { action: "comment", reason: "Review", duration: week },
      })
      .orThrow();
    await drive.requestAccess({ nodeId: "n1" }).orThrow();
    await drive.accessRequests({ nodeId: "n1", status: "pending" }).orThrow();

    expect(port.requestRecord.mock.calls).toEqual([
      [
        {
          subjectType: "file",
          subjectId: "n1",
          action: "comment",
          reason: "Review",
          duration: week,
        },
      ],
      [{ subjectType: "file", subjectId: "n1" }],
    ]);
    expect(port.records.mock.calls).toEqual([
      ["file", "n1", { status: "pending" }],
    ]);
  });

  it("defaults to drive_node and fails without the block", async () => {
    const port = recordAccess();
    await createDrive({ transport: transport({}), recordAccess: port })
      .accessRequests({ nodeId: "n1" })
      .orThrow();
    expect(port.records.mock.calls[0]![0]).toBe("drive_node");

    const drive = createDrive({ transport: transport({}) });
    const requested = await drive.requestAccess({ nodeId: "n1" });
    const listed = await drive.accessRequests({ nodeId: "n1" });

    for (const result of [requested, listed]) {
      expect(result.ok).toBe(false);
      expect(result.ok ? undefined : result.error.hint).toBe(
        "DRIVE_ACCESS_REQUESTS_CLIENT",
      );
    }
  });
});

describe("drive ownership transfer", () => {
  it("moves a member's items and counts them", async () => {
    const fake = transport({
      drive_transfer_ownership: () => ({ nodes: 3, drives: 1 }),
    });

    const drive = createDrive({ transport: fake });

    expect(
      await drive
        .transferOwnership({
          organizationId: "o",
          fromUserId: "u1",
          toUserId: "u2",
        })
        .orThrow(),
    ).toEqual({ nodes: 3, drives: 1 });
    expect(fake.calls).toEqual([
      [
        "drive_transfer_ownership",
        { tenant: "o", from_user: "u1", to_user: "u2" },
      ],
    ]);
  });

  it("rejects a reply without counts", async () => {
    const drive = createDrive({
      transport: transport({
        drive_transfer_ownership: () => ({ nodes: 1.5 }),
      }),
    });

    const result = await drive.transferOwnership({
      organizationId: "o",
      fromUserId: "u1",
      toUserId: "u2",
    });

    expect(result.ok).toBe(false);
  });
});
