import type { EntitySchema } from "../entity-schema.ts";
import type { Section, SectionRowInput, SectionWrite } from "../sections.ts";
import type {
  RestoreResult,
  SnapshotResult,
  Version,
  VersionListOptions,
  Versions,
} from "./versions.ts";

import { entitySchema } from "../entity-schema.ts";
import { defineSection, sectionRowInput } from "../sections.ts";

/** What recording a version from a record page takes. */
export interface VersionInput {
  readonly label?: string;
}

/** The input schema of the versions section's `snapshot`. */
export const versionInput: EntitySchema<VersionInput> =
  entitySchema<VersionInput>({
    title: "VersionInput",
    fields: { label: { kind: "string", optional: true, minLength: 1 } },
  });

/** The writes of the versions section. */
export type VersionsWrites = {
  /** Records a version of the record from its configured columns. */
  readonly snapshot: SectionWrite<Versions, VersionInput, SnapshotResult>;
  /** Restores the record to one of its versions. */
  readonly restore: SectionWrite<Versions, SectionRowInput, RestoreResult>;
};

/** A record's versions, newest first, without content. */
export const versionsSection: Section<
  Versions,
  readonly Version[],
  VersionListOptions,
  never,
  VersionsWrites
> = defineSection({
  permissions: { read: "read", write: "create" },
  module: "versions",
  load: (client: Versions, subject, options?: VersionListOptions) =>
    client.list(subject, options),
  events: ["version.*"],
  writes: {
    snapshot: {
      input: versionInput,
      run: (client: Versions, subject, input: VersionInput) =>
        client.snapshot(
          subject,
          input.label === undefined ? {} : { label: input.label },
        ),
    },
    restore: {
      permission: "restore",
      input: sectionRowInput,
      run: (client: Versions, _subject, { id }: SectionRowInput) =>
        client.restore(id),
    },
  },
});
