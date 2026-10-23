import type { RecordRef } from "../schema/types.ts";
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
  subject: RecordRef,
  options: RecordTagOptions = {},
): string {
  const scope =
    options.tenant === undefined || options.tenant === null
      ? ""
      : `@${options.tenant}`;

  return `bsb:record${scope}:${subject.type}:${subject.id}`;
}

/** The cache tag of one binding of a record, such as its comments. */
export function bindingTag(
  subject: RecordRef,
  binding: string,
  options: RecordTagOptions = {},
): string {
  return `${recordTag(subject, options)}#${binding}`;
}

/**
 * Drops the cached binding and the record's header, whose counts change with
 * it: `updateTag` in a Server Action, else `revalidateTag`.
 */
export function invalidateBinding(
  subject: RecordRef,
  binding: string,
  options: RecordTagOptions & { readonly revalidate?: RevalidateProfile } = {},
): void {
  invalidateAll(
    [bindingTag(subject, binding, options), recordTag(subject, options)],
    options.revalidate,
  );
}
