import type { Action } from "../../core/automation.ts";
import type { Result } from "../../core/result.ts";
import type {
  ConversionClients,
  ConversionContext,
} from "../automations/conversion.ts";
import type { Employee, EmployeeInput } from "./employees.ts";

import { ok } from "../../core/result.ts";
import { defineConversionAction } from "../automations/conversion.ts";

/** `blocks.employees` and `blocks.relations` for one organization. */
export interface EmployeeFromApplicationClients extends ConversionClients {
  readonly employees: {
    fromApplication(
      applicationId: string,
      overrides?: Partial<EmployeeInput>,
    ): PromiseLike<Result<Employee>>;
  };
}

export interface EmployeeFromApplicationOptions {
  /** The clients for one organization, over a service connection. */
  readonly clients: (
    tenant: string,
  ) =>
    | EmployeeFromApplicationClients
    | PromiseLike<EmployeeFromApplicationClients>;
  /** Overrides what the employee takes from the candidate and the job. */
  readonly map?: (
    context: ConversionContext<EmployeeFromApplicationClients>,
  ) => Partial<EmployeeInput>;
}

/**
 * The `employees.from_application` action, which the hiring block's default
 * automation runs on `application.hired`: an employee in preboarding through
 * `employees.fromApplication`, which records the `created_from` link itself.
 */
export function employeeFromApplicationAction(
  options: EmployeeFromApplicationOptions,
): Action {
  return defineConversionAction<
    EmployeeFromApplicationClients,
    undefined,
    Partial<EmployeeInput>
  >({
    kind: "employees.from_application",
    title: "Preboard the hired candidate",
    targetType: "employee",
    clients: options.clients,
    map: (_, context) => options.map?.(context) ?? {},
    create: async (overrides, { clients, source }) => {
      const created = await clients.employees.fromApplication(
        source.id,
        overrides,
      );

      return created.ok ? ok({ id: created.data.id }) : created;
    },
    linksItself: true,
  });
}
