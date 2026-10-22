export {
  createActivities,
  type Engagement,
  type EngagementInput,
  type Activities,
  type ActivitiesOptions,
  type EngagementSubject,
} from "./activities.ts";

export {
  ENGAGEMENT_TRANSCRIBE_QUEUE,
  type EngagementActionItem,
  type EngagementNotes,
  type EngagementNotesInput,
  type EngagementRecording,
  type EngagementRecordingStatus,
  type NoteTaker,
  type NoteTakerInput,
  type Transcriber,
  type TranscriberInput,
  type Transcript,
  type TranscriptSegment,
  type TranscriptSegmentInput,
} from "./recordings.ts";

export {
  extendBlock,
  withBlockHooks,
  wrapTransport,
  type BlockHooks,
  type BlockTransportMiddleware,
} from "../../core/block-hooks.ts";

export {
  dbTransport,
  rpcTransport,
  sqlTransport,
  type BlockTransport,
  type RpcClient,
} from "../../core/block-transport.ts";

export { activitiesBlock } from "./manifest.ts";

export { activitiesEvents } from "./events.ts";

export type { ActivitiesEvents } from "./events.ts";

export { engagementChangeSchema, engagementInputSchema } from "./schemas.ts";
