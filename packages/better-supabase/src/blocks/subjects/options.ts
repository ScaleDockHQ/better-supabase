import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** The roles a record team takes when `recordTeam.roles` is unset. */
export const DEFAULT_RECORD_TEAM_ROLES: readonly string[] = ["lead", "member"];

/** How long repeated reads of one record by one user count as one entry. */
export const DEFAULT_READ_COLLAPSE_SECONDS = 60;

/** `blocks.subjects.options.recordTeam`. */
export interface RecordTeamOptions {
  /**
   * The roles a `subject_members` row may hold. `add_subject_member` refuses
   * any other with `SUBJECT_MEMBER_INVALID`. Default `["lead", "member"]`.
   */
  readonly roles?: readonly string[];
}

/** `blocks.subjects.options.reads`, for types with `auditReads`. */
export interface SubjectReadsOptions {
  /**
   * Reads of one record by one user within this many seconds of the last logged
   * read write no new entry. `0` logs every read. Default 60.
   */
  readonly collapseSeconds?: number;
}

/** `blocks.subjects.options`. */
export type SubjectsSqlOptions = {
  readonly recordTeam?: RecordTeamOptions;
  readonly reads?: SubjectReadsOptions;
};

export const subjectsSqlOptions: BlockOptionsSchema<SubjectsSqlOptions> =
  blockOptions<SubjectsSqlOptions>({
    recordTeam: option.unknown<RecordTeamOptions>(),
    reads: option.unknown<SubjectReadsOptions>(),
  });
