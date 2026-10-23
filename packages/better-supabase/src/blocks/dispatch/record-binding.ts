import type {
  RecordBinding,
  RecordRowInput,
  RecordBindingWrite,
} from "../record-bindings.ts";
import type { Dispatch, WorkOrder } from "./dispatch.ts";
import type { WorkOrderSectionInput } from "./schemas.ts";

import { defineRecordBinding, recordRowInput } from "../record-bindings.ts";
import { workOrderSectionInputSchema } from "./schemas.ts";

/** The writes of the dispatch binding. */
export type DispatchWrites = {
  /** Opens a work order for the record, such as a repair for a customer. */
  readonly create: RecordBindingWrite<
    Dispatch,
    WorkOrderSectionInput,
    WorkOrder
  >;
  /** Cancels one of the record's work orders. */
  readonly cancel: RecordBindingWrite<Dispatch, RecordRowInput, WorkOrder>;
};

/** The work orders opened for a record: a customer's or a site's jobs. */
export const dispatchBinding: RecordBinding<
  Dispatch,
  readonly WorkOrder[],
  undefined,
  never,
  DispatchWrites
> = defineRecordBinding({
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
      input: recordRowInput,
      run: (client: Dispatch, _subject, { id }: RecordRowInput) =>
        client.setStatus(id, "cancelled"),
    },
  },
});
