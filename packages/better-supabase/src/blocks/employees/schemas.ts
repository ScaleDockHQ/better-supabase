import type { EntitySchema } from "../entity-schema.ts";
import type { EmployeeChange, EmployeeInput } from "./employees.ts";

import { entitySchema } from "../entity-schema.ts";

/** What `create` takes, with the bounds the SQL checks. */
export const employeeInputSchema: EntitySchema<EmployeeInput> =
  entitySchema<EmployeeInput>({
    title: "EmployeeInput",
    fields: {
      name: { kind: "string", minLength: 1, maxLength: 200 },
      firstName: { kind: "string", optional: true, maxLength: 200 },
      lastName: { kind: "string", optional: true, maxLength: 200 },
      email: { kind: "string", optional: true, maxLength: 320 },
      userId: { kind: "uuid", optional: true },
      jobTitle: { kind: "string", optional: true, maxLength: 200 },
      teamId: { kind: "uuid", optional: true },
      managerId: { kind: "uuid", optional: true },
      employmentType: { kind: "string", optional: true },
      status: {
        kind: "enum",
        values: ["preboarding", "active", "on_leave"],
        optional: true,
      },
      startDate: { kind: "plainDate", optional: true },
      endDate: { kind: "plainDate", optional: true },
      origin: {
        kind: "json",
        optional: true,
        description: "A `{ type, id }` reference.",
      },
      fields: {
        kind: "json",
        optional: true,
        description: "The extra columns to set.",
      },
    },
  });

/**
 * One edit `update` takes. `field` is a built-in field or an extra column, so
 * any name passes; the SQL rejects an unknown one.
 */
export const employeeChangeSchema: EntitySchema<EmployeeChange> =
  entitySchema<EmployeeChange>({
    title: "EmployeeChange",
    fields: {
      employeeId: { kind: "uuid" },
      field: { kind: "string", minLength: 1 },
      value: { kind: "unknown", description: "`null` clears the field." },
    },
  });
