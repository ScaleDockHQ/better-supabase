import type { Section, SectionRowInput, SectionWrite } from "../sections.ts";
import type { Dispatch, WorkOrder } from "./dispatch.ts";
import type { WorkOrderSectionInput } from "./schemas.ts";

import { defineSection, sectionRowInput } from "../sections.ts";
import { workOrderSectionInputSchema } from "./schemas.ts";

/** The writes of the dispatch section. */
export type DispatchWrites = {
  /** Opens a work order for the record, such as a repair for a customer. */
  readonly create: SectionWrite<Dispatch, WorkOrderSectionInput, WorkOrder>;
  /** Cancels one of the record's work orders. */
  readonly cancel: SectionWrite<Dispatch, SectionRowInput, WorkOrder>;
};

/** The work orders opened for a record: a customer's or a site's jobs. */
export const dispatchSection: Section<
  Dispatch,
  readonly WorkOrder[],
  undefined,
  never,
  DispatchWrites
> = defineSection({
  permissions: { read: "read", write: "manage" },
  module: "dispatch",
  load: (client: Dispatch, subject) => client.list({ subject }),
  events: ["work_order.*"],
  writes: {
    create: {
      input: workOrderSectionInputSchema,
      run: (client: Dispatch, subject, input: WorkOrderSectionInput) =>
        client.create({ ...input, subject }),
    },
    cancel: {
      input: sectionRowInput,
      run: (client: Dispatch, _subject, { id }: SectionRowInput) =>
        client.setStatus(id, "cancelled"),
    },
  },
});
