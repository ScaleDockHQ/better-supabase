import type { EntitySchema } from "../entity-schema.ts";
import type { LeaseInput, MaintenanceRequestInput } from "./leases.ts";

import { entitySchema, moneyField } from "../entity-schema.ts";

/** What `create` takes, with the bounds the SQL checks. */
export const leaseInputSchema: EntitySchema<LeaseInput> =
  entitySchema<LeaseInput>({
    title: "LeaseInput",
    fields: {
      unitId: { kind: "uuid", description: "The asset let." },
      party: {
        kind: "json",
        description: "The party renting the unit: `{ type, id }`.",
      },
      startsOn: { kind: "plainDate" },
      endsOn: { kind: "plainDate", optional: true },
      rent: moneyField,
      frequency: {
        kind: "enum",
        values: ["weekly", "monthly", "quarterly", "yearly"],
        optional: true,
      },
      deposit: { ...moneyField, optional: true },
      title: { kind: "string", optional: true, minLength: 1, maxLength: 200 },
      metadata: { kind: "json", optional: true },
      fields: {
        kind: "json",
        optional: true,
        description: "The extra columns to set.",
      },
    },
  });

/** What `fileMaintenance` takes. */
export const maintenanceRequestInputSchema: EntitySchema<MaintenanceRequestInput> =
  entitySchema<MaintenanceRequestInput>({
    title: "MaintenanceRequestInput",
    fields: {
      unitId: { kind: "uuid" },
      title: { kind: "string", minLength: 1, maxLength: 200 },
      description: { kind: "string", optional: true, maxLength: 5000 },
      priority: {
        kind: "enum",
        values: ["low", "normal", "high", "urgent"],
        optional: true,
      },
      leaseId: { kind: "uuid", optional: true },
    },
  });
