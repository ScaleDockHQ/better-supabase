import type { AiFile } from "../ai-files/types.ts";

import {
  enumOrThrow,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

/** The queue a recording's transcription job goes on, with the jobs block. */
export const ENGAGEMENT_TRANSCRIBE_QUEUE = "engagements.transcribe";

/** `pending` until a transcript is saved; `failed` when the transcriber gave up. */
export type EngagementRecordingStatus = "pending" | "transcribed" | "failed";

/** A call or meeting recording: an ai-files file on an engagement. */
export interface EngagementRecording {
  readonly id: string;
  readonly organizationId: string;
  readonly engagementId: string;
  readonly fileId: string;
  readonly filename: string;
  readonly mediaType: string;
  readonly status: EngagementRecordingStatus;
  /** A BCP 47 tag such as `en` or `nl-NL`, given or detected. */
  readonly language?: string;
  readonly durationSeconds?: number;
  /** Why the transcriber failed. */
  readonly error?: string;
  /** The transcriber's model. */
  readonly model?: string;
  readonly segmentCount: number;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly transcribedAt?: Temporal.Instant;
}

/** One speaker turn of a transcript. */
export interface TranscriptSegment {
  /** 1 for the first turn. */
  readonly position: number;
  /** The speaker's label, such as `Speaker 1` or a name. */
  readonly speaker?: string;
  /** The member who spoke, when known. */
  readonly speakerUserId?: string;
  /** Milliseconds from the start of the recording. */
  readonly startMs: number;
  readonly endMs: number;
  readonly text: string;
  /** Between 0 and 1. */
  readonly confidence?: number;
}

export type TranscriptSegmentInput = Omit<TranscriptSegment, "position">;

/** What a transcriber returns and `saveTranscript` stores. */
export interface Transcript {
  /** In order; `startMs` at most `endMs`. */
  readonly segments: readonly TranscriptSegmentInput[];
  readonly language?: string;
  readonly durationSeconds?: number;
}

/** What `Transcriber.transcribe` gets for one recording. */
export interface TranscriberInput {
  readonly file: Pick<AiFile, "id" | "filename" | "mediaType">;
  /** A signed URL to the audio or video, for providers that fetch it. */
  readonly url: string;
  /** The bytes, for providers that take an upload. */
  read(): Promise<Uint8Array>;
  /** The language given when the recording was attached. */
  readonly language?: string;
}

/**
 * Turns a recording into speaker turns. Wrap any speech-to-text API or SDK in
 * the app; the block imports none.
 */
export interface Transcriber {
  /** The transcriber contract version. Omitted means 1. */
  readonly apiVersion?: 1;
  readonly model: string;
  transcribe(
    input: TranscriberInput,
    options?: { readonly signal?: AbortSignal },
  ): Promise<Transcript>;
}

/** A follow-up a note names. */
export interface EngagementActionItem {
  readonly text: string;
  readonly ownerId?: string;
  readonly dueAt?: Temporal.Instant;
}

/** What `saveNotes` stores and a note taker returns. */
export interface EngagementNotesInput {
  readonly summary: string;
  readonly actionItems?: readonly EngagementActionItem[];
}

/** The notes on an engagement: a summary and its action items. */
export interface EngagementNotes {
  readonly engagementId: string;
  readonly organizationId: string;
  readonly summary: string;
  readonly actionItems: readonly EngagementActionItem[];
  /** The note taker's model, for notes an AI wrote. */
  readonly model?: string;
  /** `ai` from `summarize`, `member` when a member wrote them. */
  readonly source: "ai" | "member";
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** What `NoteTaker.summarize` gets: the engagement and its transcripts. */
export interface NoteTakerInput<E> {
  readonly engagement: E;
  readonly transcript: readonly (TranscriptSegment & {
    readonly recordingId: string;
  })[];
}

/**
 * Writes a summary and action items for an engagement from its transcripts.
 * Wrap any model in the app; the block imports no AI SDK (ADR 0010).
 */
export interface NoteTaker {
  /** The note taker contract version. Omitted means 1. */
  readonly apiVersion?: 1;
  readonly model: string;
  summarize<E>(
    input: NoteTakerInput<E>,
    options?: { readonly signal?: AbortSignal },
  ): Promise<EngagementNotesInput>;
}

const STATUSES: readonly EngagementRecordingStatus[] = [
  "pending",
  "transcribed",
  "failed",
];

const numberOf = (value: unknown): number | undefined =>
  typeof value === "number" ? value : undefined;

const defined = <T extends object>(value: {
  readonly [K in keyof T]-?: T[K] | undefined;
}): T =>
  // SAFETY: the same object without its undefined keys, which T marks optional.
  Object.fromEntries(
    Object.entries(value).filter(([, item]) => item !== undefined),
  ) as T;

export function recordingOf(value: unknown): EngagementRecording {
  const row = recordOf(value, "engagement recording");

  return defined<EngagementRecording>({
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    engagementId: textOf(row["engagementId"]),
    fileId: textOf(row["fileId"]),
    filename: textOf(row["filename"]),
    mediaType: textOf(row["mediaType"]),
    status: enumOrThrow(row["status"], STATUSES, "recording status"),
    language: optionalText(row["language"]),
    durationSeconds: numberOf(row["durationSeconds"]),
    error: optionalText(row["error"]),
    model: optionalText(row["model"]),
    segmentCount: numberOf(row["segmentCount"]) ?? 0,
    createdBy: optionalText(row["createdBy"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    transcribedAt: optionalInstant(row["transcribedAt"]),
  });
}

export function segmentOf(row: Record<string, unknown>): TranscriptSegment {
  return defined<TranscriptSegment>({
    position: numberOf(row["position"]) ?? 0,
    speaker: optionalText(row["speaker"]),
    speakerUserId: optionalText(row["speakerUserId"]),
    startMs: numberOf(row["startMs"]) ?? 0,
    endMs: numberOf(row["endMs"]) ?? 0,
    text: textOf(row["text"]),
    confidence: numberOf(row["confidence"]),
  });
}

function actionItemOf(row: Record<string, unknown>): EngagementActionItem {
  return defined<EngagementActionItem>({
    text: textOf(row["text"]),
    ownerId: optionalText(row["ownerId"]),
    dueAt: optionalInstant(row["dueAt"]),
  });
}

export function notesOf(value: unknown): EngagementNotes {
  const row = recordOf(value, "engagement notes");

  return defined<EngagementNotes>({
    engagementId: textOf(row["engagementId"]),
    organizationId: textOf(row["organizationId"]),
    summary: textOf(row["summary"]),
    actionItems: recordsOf(row["actionItems"], "action items").map(
      actionItemOf,
    ),
    model: optionalText(row["model"]),
    source: row["source"] === "member" ? "member" : "ai",
    createdBy: optionalText(row["createdBy"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
  });
}

/** The jsonb `save_activity_notes` takes. */
export function notesArg(
  input: EngagementNotesInput,
  source: "ai" | "member",
  model: string | undefined,
): Record<string, unknown> {
  return {
    summary: input.summary,
    actionItems: (input.actionItems ?? []).map((item) =>
      defined<Record<string, unknown>>({
        text: item.text,
        ownerId: item.ownerId,
        dueAt: item.dueAt === undefined ? undefined : String(item.dueAt),
      }),
    ),
    source,
    ...(model === undefined ? {} : { model }),
  };
}

/** The segments `save_activity_transcript` takes. */
export function segmentsArg(
  segments: readonly TranscriptSegmentInput[],
): Record<string, unknown>[] {
  return segments.map((segment) =>
    defined<Record<string, unknown>>({
      speaker: segment.speaker,
      speakerUserId: segment.speakerUserId,
      startMs: segment.startMs,
      endMs: segment.endMs,
      text: segment.text,
      confidence: segment.confidence,
    }),
  );
}

/** The transcript rows of `activity_with_transcripts`, with their recording. */
export function transcriptOf(
  value: unknown,
): NoteTakerInput<unknown>["transcript"] {
  return recordsOf(value, "transcript").map((row) => ({
    ...segmentOf(row),
    recordingId: textOf(row["recordingId"]),
  }));
}
