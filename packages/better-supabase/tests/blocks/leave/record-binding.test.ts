import { describe, expect, it } from "vitest";

import {
  createLeave,
  leaveBinding,
  leaveBlock,
} from "../../../src/blocks/leave/index.ts";

function transport(calls: [string, Record<string, unknown>][]) {
  return {
    call(_schema: string, fn: string, args: Record<string, unknown>) {
      calls.push([fn, args]);

      return Promise.resolve([]);
    },
  };
}

describe("leaveBinding", () => {
  it("reads an employee's requests by employee id", async () => {
    const calls: [string, Record<string, unknown>][] = [];

    const client = createLeave({
      tenant: "org-1",
      transport: transport(calls),
    });

    const loaded = await leaveBinding.load(
      client,
      { type: "employee", id: "s1" },
      undefined,
    );

    expect(loaded.ok && loaded.data).toEqual([]);

    expect(calls).toEqual([
      [
        "list_leave_requests",
        {
          tenant: "org-1",
          user_id: null,
          status: null,
          starts: null,
          ends: null,
          everyone: false,
          page_size: null,
          employee_id: "s1",
        },
      ],
    ]);
    expect(leaveBlock.record).toBe(leaveBinding);
    expect(leaveBinding.events).toEqual(["leave_request.*"]);
  });

  it("fails without an organization", async () => {
    const client = createLeave({ transport: transport([]) });

    const loaded = await leaveBinding.load(
      client,
      { type: "employee", id: "s1" },
      undefined,
    );

    expect(loaded.ok).toBe(false);
  });
});
