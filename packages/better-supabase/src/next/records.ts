import type { SubjectRef } from "../schema/types.ts";
import type { RevalidateProfile } from "./types.ts";

import { invalidateAll } from "./cache.ts";

export interface RecordTagOptions {
  /** The tenant the read is scoped to, so other tenants' writes keep it. */
  readonly tenant?: string | null | undefined;
}

/**
 * The cache tag of a record's header and tab badges (`record_summary`):
 * `bsb:record@<tenant>:<type>:<id>`, or `bsb:record:<type>:<id>` without a
 * tenant.
 */
export function recordTag(
  subject: SubjectRef,
  options: RecordTagOptions = {},
): string {
  const scope =
    options.tenant === undefined || options.tenant === null
      ? ""
      : `@${options.tenant}`;

  return `bsb:record${scope}:${subject.type}:${subject.id}`;
}

/** The cache tag of one section of a record, such as its comments. */
export function sectionTag(
  subject: SubjectRef,
  section: string,
  options: RecordTagOptions = {},
): string {
  return `${recordTag(subject, options)}#${section}`;
}

/**
 * Drops the cached section and the record's header, whose counts change with
 * it: `updateTag` in a Server Action, else `revalidateTag`.
 */
export function invalidateSection(
  subject: SubjectRef,
  section: string,
  options: RecordTagOptions & { readonly revalidate?: RevalidateProfile } = {},
): void {
  invalidateAll(
    [sectionTag(subject, section, options), recordTag(subject, options)],
    options.revalidate,
  );
}
