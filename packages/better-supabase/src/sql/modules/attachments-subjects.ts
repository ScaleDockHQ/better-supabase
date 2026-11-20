import type { Subject } from "../subjects.ts";

import { sqlString } from "../../core/template.ts";
import { qualifiedTable, subjectIdMatches } from "../subjects.ts";
import { BUCKET } from "./attachments-bucket.ts";
import { versionPaths } from "./attachments-versions.ts";

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
 * can change the subject row, for the types with `upload: "subject"`. It needs
 * an update grant on the table and select on its id, then takes a `for key
 * share` lock, which applies the table's update policies without writing. Other
 * types pass.
 */
function subjectWritableSql(
  fn: string,
  subjects: readonly (readonly [string, Subject])[],
): string {
  const whens = subjects
    .map(([type, subject]) => {
      const table = sqlString(qualifiedTable(subject.table));

      return `    when ${sqlString(type)} then
      if not (has_any_column_privilege(${table}, 'UPDATE') and has_column_privilege(${table}, ${sqlString(subject.id ?? "id")}, 'SELECT')) then
        return false;
      end if;
      perform 1 from ${qualifiedTable(subject.table)} s where ${subjectIdMatches(subject, "subject_id")} for key share of s;
      return found;`;
    })
    .join("\n");

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
  case subject_type
${whens}
    else
      return true;
  end case;
end;
$$;`;
}

interface SubjectUploadArgs {
  readonly fn: (name: string) => string;
  readonly subjects: readonly (readonly [string, Subject])[];
  readonly t: string;
  readonly c: (logical: string) => string;
  readonly versions: string;
  readonly vc: (logical: string) => string;
  readonly mayUpload: (row: string) => string;
}

/**
 * The `upload: "subject"` parts of the attachments module: the functions'
 * `sql`, the policy condition `writable` (empty without such a subject), and
 * the checks of definer functions, which can't run the subject table's policies
 * as the caller: `claimable` (claiming, replacing and restoring) and
 * `ownDelete` (the uploader deleting the object) take attachments.manage for
 * those types instead. `objectDelete` lets the uploader delete the object while
 * they can still change the subject, as the caller.
 */
export function subjectUpload(args: SubjectUploadArgs): {
  readonly sql: string;
  readonly writable: string;
  readonly claimable: (row: string) => string;
  readonly ownDelete: (row: string) => string;
  readonly objectDelete: string;
} {
  const { fn, c, mayUpload } = args;
  const checked = subjectUploads(args.subjects);

  const mine = (row: string): string =>
    `${row}.${c("uploadedBy")} = auth.uid()`;

  if (checked.length === 0) {
    return {
      sql: "",
      writable: "",
      claimable: mayUpload,
      ownDelete: mine,
      objectDelete: "",
    };
  }

  const writable = fn("attachment_subject_writable");
  const object = fn("attachment_object_subject_writable");
  const types = checked.map(([type]) => sqlString(type)).join(", ");
  const { atCurrent } = versionPaths(c);

  const elsewhere = (row: string): string =>
    `coalesce(${row}.${c("subjectType")} not in (${types}), true)`;

  const subjectOf = (row: string): string =>
    `${mine(row)} and ${row}.${c("subjectType")} in (${types}) and ${writable}(${row}.${c("subjectType")}, ${row}.${c("subjectId")})`;

  return {
    sql: `${subjectWritableSql(writable, checked)}
revoke execute on function ${writable}(text, text) from public, anon;
grant execute on function ${writable}(text, text) to authenticated, service_role;

-- Whether the caller uploaded the object at path, for a record type with
-- upload "subject", and can still change its subject row. It reads the
-- records the caller sees, as the caller. plpgsql, so the versions table
-- binds late.
create or replace function ${object}(bucket text, path text)
returns boolean
language plpgsql
volatile
security invoker
set search_path = ''
as $$
begin
  return exists (
    select 1 from ${args.t} a
    where a.${c("bucket")} = $1 and ${atCurrent("a", "$2")}
      and ${subjectOf("a")}
  ) or exists (
    select 1 from ${args.versions} v
    join ${args.t} a on a.${c("id")} = v.${args.vc("attachment")}
    where v.${args.vc("bucket")} = $1 and v.${args.vc("path")} = $2
      and ${subjectOf("a")}
  );
end;
$$;
revoke execute on function ${object}(text, text) from public, anon;
grant execute on function ${object}(text, text) to authenticated, service_role;
`,
    writable: ` and ${writable}(${c("subjectType")}, ${c("subjectId")})`,
    claimable: (row) => `(${mayUpload(row)} and ${elsewhere(row)})`,
    ownDelete: (row) => `(${mine(row)} and ${elsewhere(row)})`,
    objectDelete: ` or ${object}(bucket_id, name)`,
  };
}
