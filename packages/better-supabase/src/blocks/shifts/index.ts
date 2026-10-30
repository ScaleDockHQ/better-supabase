export {
  createShifts,
  type MyShift,
  type RosterShift,
  type Shift,
  type ShiftAssignment,
  type ShiftAssignmentStatus,
  type ShiftAssignmentWarning,
  type ShiftAvailability,
  type ShiftAvailabilityInput,
  type ShiftAvailabilityKind,
  type ShiftHours,
  type ShiftInput,
  type Shifts,
  type ShiftsOptions,
  type ShiftStatus,
  type ShiftSwap,
  type ShiftSwapStatus,
  type ShiftTemplate,
  type ShiftTemplateInput,
} from "./shifts.ts";

export {
  extendBlock,
  withBlockHooks,
  wrapTransport,
} from "../../core/block-hooks.ts";

export type {
  BlockHooks,
  BlockTransportMiddleware,
} from "../../core/block-hooks.ts";

export {
  dbTransport,
  rpcTransport,
  sqlTransport,
} from "../../core/block-transport.ts";

export type { BlockTransport, RpcClient } from "../../core/block-transport.ts";

export { shiftsBlock } from "./manifest.ts";

export {
  shiftAvailabilityInputSchema,
  shiftInputSchema,
  shiftTemplateInputSchema,
} from "./schemas.ts";

export { shiftsEvents } from "./events.ts";

export type {
  ShiftAssignmentCreatedEventData,
  ShiftAssignmentReleasedEventData,
  ShiftCanceledEventData,
  ShiftCreatedEventData,
  ShiftPublishedEventData,
  ShiftsEvents,
  ShiftSwapDecidedEventData,
  ShiftSwapRequestedEventData,
} from "./events.ts";
