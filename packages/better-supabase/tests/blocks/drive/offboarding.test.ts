import { describe, expect, it, vi } from "vitest";

import type { DriveAccess } from "../../../src/blocks/drive/index.ts";

import { driveOffboardingSink } from "../../../src/blocks/drive/index.ts";
import { dbError } from "../../../src/core/errors.ts";
import { AsyncResult } from "../../../src/core/result.ts";

const event = (type: string, data: unknown) => ({
  specversion: "1.0" as const,
  id: crypto.randomUUID(),
  source: "test",
  type: `dev.better-supabase.${type}`,
  data,
});

describe("driveOffboardingSink", () => {
  function stub(fails = false) {
    const transferOwnership = vi.fn<DriveAccess["transferOwnership"]>(() =>
      fails
        ? AsyncResult.err(dbError("forbidden", "no"))
        : AsyncResult.ok({ nodes: 1, drives: 0 }),
    );

    return { transferOwnership };
  }

  it("hands an offboarded or removed member's items to the chosen member", async () => {
    const drive = stub();

    const sink = driveOffboardingSink(drive, {
      transferTo: (e) =>
        e.type.endsWith("member_removed")
          ? Promise.resolve("owner")
          : "manager",
    });

    await sink.send([
      event("employee.offboarded", { organizationId: "o", userId: "u1" }),
      event("organization.member_removed", {
        organizationId: "o",
        userId: "u2",
      }),
      event("employee.offboarded", { organizationId: "o", userId: null }),
      event("employee.updated", { organizationId: "o", userId: "u3" }),
      event("employee.offboarded", "not a record"),
    ]);

    expect(drive.transferOwnership.mock.calls).toEqual([
      [{ organizationId: "o", fromUserId: "u1", toUserId: "manager" }],
      [{ organizationId: "o", fromUserId: "u2", toUserId: "owner" }],
    ]);
  });

  it("skips when nobody takes over, and throws when the move fails", async () => {
    const skipped = stub();
    await driveOffboardingSink(skipped, {
      transferTo: (e) =>
        (e.data as { userId: string }).userId === "u1" ? undefined : "u2",
      typePrefix: "app",
    }).send([
      {
        ...event("x", {}),
        type: "app.employee.offboarded",
        data: { organizationId: "o", userId: "u1" },
      },
      {
        ...event("x", {}),
        type: "app.employee.offboarded",
        data: { organizationId: "o", userId: "u2" },
      },
    ]);
    expect(skipped.transferOwnership).not.toHaveBeenCalled();

    await expect(
      driveOffboardingSink(stub(true), { transferTo: () => "u9" }).send([
        event("employee.offboarded", { organizationId: "o", userId: "u1" }),
      ]),
    ).rejects.toThrow("driveOffboardingSink: moving u1's items failed: no");
  });
});
