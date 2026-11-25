import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BlockContext } from "../create-blocks.ts";
import type { CompositeOptions } from "../define-block.ts";
import type { Employee, EmployeeInput } from "../employees/index.ts";
import type { Enrollment, EnrollmentDates } from "../enrollments/index.ts";
import type { PeopleParts } from "./manifest.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult as Async, ok } from "../../core/result.ts";

/** What `people.onboard` returns. */
export interface Onboarded {
  readonly employee: Employee;
  readonly enrollment: Enrollment;
}

/** What `people.offboard` returns. */
export interface Offboarded {
  readonly employee: Employee;
  /** How many enrollments and shift assignments the call ended. */
  readonly enrollments: number;
  readonly assignments: number;
}

/** The helpers `people` adds over its parts. */
export interface People {
  /**
   * Creates the employee, then enrolls them in the onboarding `program`
   * (`enrollments.enroll` on `{ type: "employee", id }`). A failed enrollment
   * returns its error and leaves the employee created, so retry it with
   * `enrollments.enroll`, not `onboard`.
   */
  onboard(input: {
    organizationId: string;
    employee: EmployeeInput;
    program: string;
    dates?: EnrollmentDates | undefined;
  }): AsyncResult<Onboarded>;
  /**
   * Offboards the employee, cancels their active enrollments and releases their
   * assigned or requested shifts of the next `windowDays` days (30 by default),
   * in one database call and one transaction (`employees.offboardWithWork`, ADR
   * 1235). With `enrollmentIds` or `assignmentIds` it offboards the employee
   * and then cancels and unassigns exactly those (the open ones the app lists),
   * step by step; each step is idempotent, so a retry finishes the rest.
   */
  offboard(input: {
    employeeId: string;
    endDate?: Temporal.PlainDate | undefined;
    reason?: string | undefined;
    enrollmentIds?: readonly string[] | undefined;
    assignmentIds?: readonly string[] | undefined;
    windowDays?: number | undefined;
  }): AsyncResult<Offboarded>;
}

/** What the `people` creator receives. */
export type PeopleOptions = BlockContext &
  CompositeOptions<PeopleParts> & {
    /** `before` and `after` hooks per method (ADR 0015). */
    readonly hooks?: NoInfer<BlockHooks<People>>;
    /** Receives the errors `after` hooks throw. Default: `console`. */
    readonly logger?: Logger;
  };

/** Creates the `people` helpers over the clients of its parts. */
export function createPeople(options: PeopleOptions): People {
  const { employees, enrollments, shifts } = options.parts;

  const client: People = {
    onboard: ({ organizationId, employee, program, dates }) =>
      Async.from(async () => {
        const created = await employees.create({
          organizationId,
          input: employee,
        });

        if (!created.ok) {
          return created;
        }

        const enrollment = await enrollments.enroll({
          program,
          subject: { type: "employee", id: created.data.id },
          ...(dates === undefined ? {} : { dates }),
        });

        return enrollment.ok
          ? ok({ employee: created.data, enrollment: enrollment.data })
          : enrollment;
      }),
    offboard: ({
      employeeId,
      endDate,
      reason,
      enrollmentIds,
      assignmentIds,
      windowDays,
    }) =>
      Async.from(async () => {
        if (enrollmentIds === undefined && assignmentIds === undefined) {
          return employees.offboardWithWork({
            employeeId,
            ...(endDate === undefined ? {} : { endDate }),
            ...(reason === undefined ? {} : { reason }),
            ...(windowDays === undefined ? {} : { windowDays }),
          });
        }

        const employee = await employees.offboard({
          employeeId,
          ...(endDate === undefined ? {} : { endDate }),
          ...(reason === undefined ? {} : { reason }),
        });

        if (!employee.ok) {
          return employee;
        }

        for (const enrollmentId of enrollmentIds ?? []) {
          const cancelled = await enrollments.cancel(enrollmentId);

          if (!cancelled.ok) {
            return cancelled;
          }
        }

        for (const assignmentId of assignmentIds ?? []) {
          const removed = await shifts.unassign({
            assignmentId,
            ...(reason === undefined ? {} : { reason }),
          });

          if (!removed.ok) {
            return removed;
          }
        }

        return ok({
          employee: employee.data,
          enrollments: enrollmentIds?.length ?? 0,
          assignments: assignmentIds?.length ?? 0,
        });
      }),
  };

  return withBlockHooks(client, options.hooks, {
    block: "people",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
