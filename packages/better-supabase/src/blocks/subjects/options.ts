import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** The roles a record team takes when `recordTeam.roles` is unset. */
export const DEFAULT_RECORD_TEAM_ROLES: readonly string[] = ["lead", "member"];

/** `blocks.subjects.options.recordTeam`. */
export interface RecordTeamOptions {
  /**
   * The roles a `subject_members` row may hold. `add_subject_member` refuses
   * any other with `SUBJECT_MEMBER_INVALID`. Default `["lead", "member"]`.
   */
  readonly roles?: readonly string[];
}

/** `blocks.subjects.options`. */
export type SubjectsSqlOptions = { readonly recordTeam?: RecordTeamOptions };

export const subjectsSqlOptions: BlockOptionsSchema<SubjectsSqlOptions> =
  blockOptions<SubjectsSqlOptions>({
    recordTeam: option.unknown<RecordTeamOptions>(),
  });
