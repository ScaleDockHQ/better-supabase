import { describe, expect, it, vi } from "vitest";

import type {
  Contract,
  Employees,
} from "../../../src/blocks/employees/index.ts";

import {
  employeeContractsBinding,
  employeesBlock,
} from "../../../src/blocks/employees/index.ts";
import { AsyncResult } from "../../../src/core/result.ts";

const contract: Contract = {
  id: "c1",
  employeeId: "e1",
  startsOn: Temporal.PlainDate.from("2026-01-01"),
};

describe("employeeContractsBinding", () => {
  it("loads the employee's contracts and goes stale on employee changes", async () => {
    const contracts = vi.fn((_id: string) => AsyncResult.ok([contract]));

    // SAFETY: the binding calls only `contracts`.
    const client = { contracts } as unknown as Employees;

    const loaded = await employeeContractsBinding.load(
      client,
      { type: "employee", id: "e1" },
      undefined,
    );

    expect(loaded.ok && loaded.data.map((row) => row.id)).toEqual(["c1"]);
    expect(contracts).toHaveBeenCalledWith("e1");
    expect(employeeContractsBinding.events).toEqual([
      "employee.updated",
      "employee.deleted",
    ]);
    expect(employeesBlock.record).toBe(employeeContractsBinding);
  });

  it("removes a contract by id", async () => {
    const deleteContract = vi.fn((_id: string) => AsyncResult.ok(contract));

    // SAFETY: the write calls only `deleteContract`.
    const client = { deleteContract } as unknown as Employees;

    const removed = await employeeContractsBinding.writes.remove.run(
      client,
      { type: "employee", id: "e1" },
      { id: "c1" },
    );

    expect(removed.ok && removed.data.id).toBe("c1");
    expect(deleteContract).toHaveBeenCalledWith("c1");
  });
});
