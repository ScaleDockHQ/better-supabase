import type { EntitySchema } from "../entity-schema.ts";
import type { WorkOrderInput, WorkOrderPartInput } from "./dispatch.ts";

import { entitySchema } from "../entity-schema.ts";
import { WORK_ORDER_PRIORITIES } from "./statuses.ts";

/** What `create` takes, with the bounds the SQL checks. */
export const workOrderInputSchema: EntitySchema<WorkOrderInput> =
  entitySchema<WorkOrderInput>({
    title: "WorkOrderInput",
    fields: {
      title: { kind: "string", minLength: 1, maxLength: 200 },
      description: { kind: "string", optional: true, maxLength: 10_000 },
      priority: { kind: "enum", values: WORK_ORDER_PRIORITIES, optional: true },
      locationId: { kind: "uuid", optional: true },
      assetId: { kind: "uuid", optional: true },
      bookingId: { kind: "uuid", optional: true },
      subject: {
        kind: "json",
        optional: true,
        description: "The record the job is for: `{ type, id }`.",
      },
      address: { kind: "string", optional: true, minLength: 1, maxLength: 500 },
      technicianId: { kind: "uuid", optional: true },
      startsAt: { kind: "instant", optional: true },
      endsAt: { kind: "instant", optional: true },
      fields: {
        kind: "json",
        optional: true,
        description: "The extra columns, keyed by database name.",
      },
    },
  });

/** What the section's `create` write takes: the record is the subject. */
export type WorkOrderSectionInput = Omit<WorkOrderInput, "subject" | "fields">;

export const workOrderSectionInputSchema: EntitySchema<WorkOrderSectionInput> =
  entitySchema<WorkOrderSectionInput>({
    title: "WorkOrderSectionInput",
    fields: {
      title: { kind: "string", minLength: 1, maxLength: 200 },
      description: { kind: "string", optional: true, maxLength: 10_000 },
      priority: { kind: "enum", values: WORK_ORDER_PRIORITIES, optional: true },
      locationId: { kind: "uuid", optional: true },
      assetId: { kind: "uuid", optional: true },
      bookingId: { kind: "uuid", optional: true },
      address: { kind: "string", optional: true, minLength: 1, maxLength: 500 },
      technicianId: { kind: "uuid", optional: true },
      startsAt: { kind: "instant", optional: true },
      endsAt: { kind: "instant", optional: true },
    },
  });

/** What `recordPart` takes. */
export const workOrderPartInputSchema: EntitySchema<WorkOrderPartInput> =
  entitySchema<WorkOrderPartInput>({
    title: "WorkOrderPartInput",
    fields: {
      name: { kind: "string", minLength: 1, maxLength: 200 },
      quantity: {
        kind: "unknown",
        description: "A decimal above zero with at most three places.",
      },
      unit: { kind: "string", optional: true, minLength: 1, maxLength: 20 },
      assetId: { kind: "uuid", optional: true },
      variantId: { kind: "uuid", optional: true },
      locationId: { kind: "uuid", optional: true },
    },
  });
