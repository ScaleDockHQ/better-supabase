import type {
  MedicationWrites,
  ObservationWrites,
  PowerSyncDatabaseLike,
  ProgressNoteWrites,
  UploadConnector,
  UploadConnectorOptions,
} from "better-supabase/powersync";

import {
  activityLinksRoute,
  careUploadOutcome,
  createUploadConnector,
  medicationAdministrationRoute,
  observationRoute,
  progressNoteRoute,
} from "better-supabase/powersync";

/**
 * The upload connector of a care app on Expo. A nurse's progress notes, vital
 * signs and medication rounds are written offline into the device database.
 * Each upload replays through the block functions (`activities`,
 * `observations`, `medications`), never row by row, so the server's checks
 * apply. `careUploadOutcome` turns a clinical conflict, such as a dose someone
 * else recorded first, into `conflict`, so it lands in `connector.rejected` for
 * the nurse to resolve instead of retrying forever.
 */
export function careConnector(options: {
  readonly endpoint: string;
  readonly supabase: UploadConnectorOptions["supabase"];
  readonly powersync: PowerSyncDatabaseLike;
  readonly activities: ProgressNoteWrites;
  readonly observations: ObservationWrites;
  readonly medications: MedicationWrites;
}): UploadConnector {
  return createUploadConnector({
    endpoint: options.endpoint,
    supabase: options.supabase,
    classify: careUploadOutcome,
    tables: {
      activities: progressNoteRoute(options.activities, options.powersync),
      activity_subjects: activityLinksRoute(),
      observations: observationRoute(options.observations, options.powersync),
      medication_administrations: medicationAdministrationRoute(
        options.medications,
      ),
    },
  });
}
