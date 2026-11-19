import type { Subject } from "../subjects.ts";

import { sqlString } from "../../core/template.ts";
import { qualifiedTable, subjectIdMatches } from "../subjects.ts";
import { BUCKET } from "./attachments-bucket.ts";

const isText = (value: unknown): value is string => typeof value === "string";

interface SubjectBucket {
  readonly type: string;
  readonly bucket: string;
  readonly mimeTypes: readonly string[];
}

/**
 * The subjects with their own bucket or MIME types (`on.<type>.bucket`,
 * `.allowedMimeTypes`).
 */
export function subjectBuckets(
  subjects: readonly (readonly [string, Subject])[],
  fallback: string,
): readonly SubjectBucket[] {
  return subjects.map(([type, subject]) => {
    const bucket = subject.extra["bucket"] ?? fallback;

    if (!isText(bucket) || !BUCKET.test(bucket)) {
      throw new TypeError(
        `blocks.attachments.on.${type}.bucket must be 1 to 100 lowercase letters, digits, dots, dashes or underscores`,
      );
    }

    const mimeTypes = subject.extra["allowedMimeTypes"] ?? [];

    if (!Array.isArray(mimeTypes) || !mimeTypes.every(isText)) {
      throw new TypeError(
        `blocks.attachments.on.${type}.allowedMimeTypes must be a list of MIME types`,
      );
    }

    return { type, bucket, mimeTypes };
  });
}

/**
 * The subjects with `on.<type>.upload: "subject"`: uploading and deleting a
 * file also needs the caller to be able to change the subject row under the
 * subject table's own policies.
 */
function subjectUploads(
  subjects: readonly (readonly [string, Subject])[],
): readonly (readonly [string, Subject])[] {
  return subjects.filter(([type, subject]) => {
    const upload = subject.extra["upload"] ?? "permission";

    if (upload !== "permission" && upload !== "subject") {
      throw new TypeError(
        `blocks.attachments.on.${type}.upload must be "permission" or "subject"`,
      );
    }

    return upload === "subject";
  });
}

/**
 * `attachment_subject_writable(subject_type, subject_id)`: whether the caller
 * can change the subject row, for the types with `upload: "subject"`. A `for
 * key share` lock applies the table's update policies (and needs its update
 * grant) without writing; other types pass.
 */
function subjectWritableSql(
  fn: string,
  subjects: readonly (readonly [string, Subject])[],
): string {
  const body =
    subjects.length === 0
      ? "  return true;"
      : `  case subject_type
${subjects
  .map(
    ([type, subject]) => `    when ${sqlString(type)} then
      perform 1 from ${qualifiedTable(subject.table)} s where ${subjectIdMatches(subject, "subject_id")} for key share of s;
      return found;`,
  )
  .join("\n")}
    else
      return true;
  end case;
exception
  when insufficient_privilege then
    return false;`;

  return `-- Whether the caller can change the subject row under its own update policies
-- (on.<type>.upload "subject"); other types pass.
create or replace function ${fn}(subject_type text, subject_id text)
returns boolean
language plpgsql
volatile
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
begin
${body}
end;
$$;`;
}

/**
 * The `upload: "subject"` parts of the attachments module: the function `sql`,
 * the policy condition `writable` (empty without such a subject), and
 * `claimable`, the upload check of a definer function, which can't run the
 * subject table's policies as the caller, so those types take
 * attachments.manage there.
 */
export function subjectUpload(
  fn: string,
  subjects: readonly (readonly [string, Subject])[],
  c: (logical: string) => string,
  mayUpload: (row: string) => string,
): {
  readonly sql: string;
  readonly writable: string;
  readonly claimable: (row: string) => string;
} {
  const checked = subjectUploads(subjects);

  if (checked.length === 0) {
    return { sql: "", writable: "", claimable: mayUpload };
  }

  const types = checked.map(([type]) => sqlString(type)).join(", ");

  return {
    sql: `${subjectWritableSql(fn, checked)}
revoke execute on function ${fn}(text, text) from public, anon;
grant execute on function ${fn}(text, text) to authenticated, service_role;
`,
    writable: ` and ${fn}(${c("subjectType")}, ${c("subjectId")})`,
    claimable: (row) =>
      `(${mayUpload(row)} and coalesce(${row}.${c("subjectType")} not in (${types}), true))`,
  };
}
