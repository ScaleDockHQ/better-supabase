import type { DefaultAutomation } from "../../core/automation.ts";

/**
 * Starts an employee in preboarding for each hired application, through the
 * employees block's `employees.from_application` action. Ships when employees
 * is installed.
 */
export const APPLICATION_TO_EMPLOYEE: DefaultAutomation = {
  key: "hiring.application_to_employee",
  name: "Preboard each hired candidate",
  description:
    "Creates an employee in preboarding from the hired application's candidate and job, linked created_from the application.",
  trigger: "application.hired",
  subjectType: "application",
  actions: [{ kind: "employees.from_application" }],
  requires: ["employees"],
};

/** The automations the hiring block ships. */
export const HIRING_AUTOMATIONS: readonly DefaultAutomation[] = [
  APPLICATION_TO_EMPLOYEE,
];
