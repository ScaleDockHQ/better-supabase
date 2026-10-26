import type { SubjectPermission } from "../config/types/subjects.ts";

/** A `config.subjects.<type>.permissions` entry as its parts. */
export function subjectPermissionOf(
  value: string | SubjectPermission | undefined,
): SubjectPermission | undefined {
  return typeof value === "string" ? { key: value } : value;
}

/**
 * The tenant permission key of a `config.subjects.<type>.permissions` entry, or
 * `undefined` when the action is granted only per row or to an owner.
 */
export function subjectPermissionKey(
  value: string | SubjectPermission | undefined,
): string | undefined {
  return subjectPermissionOf(value)?.key;
}
