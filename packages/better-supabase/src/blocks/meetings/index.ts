export {
  createMeetings,
  type Meeting,
  type MeetingActionItem,
  type MeetingActionItemInput,
  type MeetingAgendaItem,
  type MeetingAgendaItemInput,
  type MeetingAgendaStatus,
  type MeetingAttendance,
  type MeetingAttendee,
  type MeetingAttendeeRole,
  type MeetingChange,
  type MeetingDecision,
  type MeetingDecisionInput,
  type MeetingDecisionStatus,
  type MeetingDecisionVotes,
  type MeetingDetail,
  type MeetingInput,
  type MeetingListOptions,
  type Meetings,
  type MeetingsOptions,
  type MeetingStatus,
} from "./meetings.ts";

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

export { meetingsBlock } from "./manifest.ts";

export { meetingsSqlOptions, type MeetingsSqlOptions } from "./options.ts";

export {
  meetingAgendaItemInputSchema,
  meetingDecisionInputSchema,
  meetingInputSchema,
} from "./schemas.ts";

export { meetingsEvents } from "./events.ts";

export type {
  MeetingActionItemEventData,
  MeetingCanceledEventData,
  MeetingDecisionEventData,
  MeetingEventData,
  MeetingsEvents,
} from "./events.ts";
