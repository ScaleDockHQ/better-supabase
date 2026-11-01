import type { EntitySchema } from "../entity-schema.ts";
import type { RecordBinding, RecordBindingWrite } from "../record-bindings.ts";
import type { Drive, DriveNode, DriveRevision } from "./drive.ts";

import { entitySchema } from "../entity-schema.ts";
import { defineRecordBinding } from "../record-bindings.ts";

/** What restoring a file revision from a record page takes. */
export interface DriveRevisionInput {
  readonly revisionId: string;
}

/** The input schema of the drive binding's `restore`. */
const driveRevisionInput: EntitySchema<DriveRevisionInput> =
  entitySchema<DriveRevisionInput>({
    title: "DriveRevisionInput",
    fields: { revisionId: { kind: "uuid" } },
  });

/** The writes of the drive binding. */
export type DriveWrites = {
  /** Makes an earlier revision the file's current one. */
  readonly restore: RecordBindingWrite<Drive, DriveRevisionInput, DriveNode>;
};

/** A drive file's revisions, newest first. The record is a `drive_node`. */
export const driveBinding: RecordBinding<
  Drive,
  readonly DriveRevision[],
  never,
  never,
  DriveWrites
> = defineRecordBinding({
  permissions: { read: "read", write: "manage" },
  module: "drive",
  load: (client: Drive, subject) => client.revisions(subject.id),
  timeline: (revisions) =>
    revisions.map((revision) => ({
      id: revision.id,
      kind: "revision",
      at: revision.createdAt,
      ...(revision.createdBy === undefined
        ? {}
        : { actor: revision.createdBy }),
      row: revision,
    })),
  events: ["drive_node.*"],
  writes: {
    restore: {
      input: driveRevisionInput,
      run: (client: Drive, subject, { revisionId }: DriveRevisionInput) =>
        client.restoreRevision({ id: subject.id, revisionId }),
    },
  },
});
