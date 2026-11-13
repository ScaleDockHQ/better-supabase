import type {
  RecordBinding,
  RecordBindingWrite,
  RecordRowInput,
} from "../record-bindings.ts";
import type { Contract, Employees } from "./employees.ts";

import { defineRecordBinding, recordRowInput } from "../record-bindings.ts";

/** The writes of the employee contracts binding. */
export type EmployeeContractsWrites = {
  /** Deletes one of the employee's contracts. */
  readonly remove: RecordBindingWrite<Employees, RecordRowInput, Contract>;
};

/**
 * An employee's contracts, newest first, on the employee's own page: the
 * subject is the employee (`{ type: "employee", id }`, or its renamed type).
 * Contracts sit behind `employees.contracts_read`, so a viewer without it sees
 * the binding hidden. Adding a contract takes dates and money, which a Server
 * Action can't carry, so `addContract` stays a call on the client.
 */
export const employeeContractsBinding: RecordBinding<
  Employees,
  readonly Contract[],
  never,
  never,
  EmployeeContractsWrites
> = defineRecordBinding({
  permissions: { read: "contractsRead", write: "contractsWrite" },
  module: "employees",
  load: (client: Employees, subject) => client.contracts(subject.id),
  events: ["employee.updated", "employee.deleted"],
  writes: {
    remove: {
      input: recordRowInput,
      run: (client: Employees, _subject, { id }: RecordRowInput) =>
        client.deleteContract(id),
    },
  },
});
