import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/**
 * `score_model.created`, `score_model.updated`, `score_model.archived`,
 * `score_model.restored` and `score_model.purged`.
 */
export interface ScoreModelEventData {
  readonly organizationId: string;
  /** The model. */
  readonly id: string;
  /** `lead`, `health`, or the app's own key. */
  readonly key: string;
  readonly subjectType: string;
  readonly version: number;
}

/** `score.changed`: a subject's score or band under a model changed. */
export interface ScoreChangedEventData {
  readonly organizationId: string;
  readonly modelId: string;
  readonly modelKey: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly score: number;
  /** `null` for the subject's first score under the model. */
  readonly previousScore: number | null;
  readonly band: string | null;
  readonly previousBand: string | null;
}

/** The events of the `scores` block: type to data. */
export type ScoresEvents = {
  readonly "score_model.created": ScoreModelEventData;
  readonly "score_model.updated": ScoreModelEventData;
  readonly "score_model.archived": ScoreModelEventData;
  readonly "score_model.restored": ScoreModelEventData;
  readonly "score_model.purged": ScoreModelEventData;
  readonly "score.changed": ScoreChangedEventData;
};

/** The `scores` block's event types, for its manifest and `onBlockEvent`. */
export const scoresEvents: Events<ScoresEvents> = defineEvents({
  "score_model.created": event<ScoreModelEventData>(),
  "score_model.updated": event<ScoreModelEventData>(),
  "score_model.archived": event<ScoreModelEventData>(),
  "score_model.restored": event<ScoreModelEventData>(),
  "score_model.purged": event<ScoreModelEventData>(),
  "score.changed": event<ScoreChangedEventData>(),
});
