export const SUBJECT_TYPE_PATTERN: RegExp = /^[a-z][a-z0-9_-]{0,62}$/;

export const SUBJECT_TYPE_SQL_PATTERN = "^[a-z][a-z0-9_-]{0,62}$";

export function subjectTypeIdent(type: string): string {
  return type.replaceAll("-", "_");
}
