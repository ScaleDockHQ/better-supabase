import type { BlockSqlContext } from "../context.ts";

import { fail, SERVICE_CALLER, userGrant } from "../shared.ts";

/** What `archiveFunctions` takes from the forms module's builders. */
export interface FormArchiveParts {
  readonly submissions: string;
  readonly s: (column: string) => string;
  readonly fn: (name: string) => string;
  readonly review: string;
  readonly submissionJson: (row: string) => string;
  readonly submissionRecord: (
    type: string,
    row: string,
    extra: string,
    audit: boolean,
  ) => string;
  readonly submissionNotFound: string;
}

/**
 * `archive_form_submission` and `restore_form_submission`, when the submissions
 * table has the `archivedAt` column. A reviewer archives a submitted, accepted
 * or rejected submission; a draft is the respondent's work in progress and is
 * purged, not archived.
 */
export function archiveFunctions(
  ctx: BlockSqlContext,
  parts: FormArchiveParts,
): string {
  const { submissions, s, fn, review, submissionJson, submissionRecord } =
    parts;

  if (!ctx.has("submissions", "archivedAt")) {
    return "";
  }

  return ["archive", "restore"]
    .map((verb) => {
      const name = `${verb}_form_submission`;
      const past = verb === "archive" ? "archived" : "restored";

      return `
-- ${verb === "archive" ? "Archives a submission: it leaves list_form_submissions and form_nps and keeps its answers, score and review." : "Restores an archived submission to the lists."}
create or replace function ${fn(name)}(submission_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${submissions}%rowtype;
begin
  select * into v_row from ${submissions} x where x.${s("id")} = ${name}.submission_id for update;
  if not found then
    ${parts.submissionNotFound}
  end if;
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", `v_row.${s("tenant")}`, review)}) then
    ${fail("FORM_FORBIDDEN", `not allowed to ${verb} submissions`)}
  end if;
  if v_row.${s("archivedAt")} ${verb === "archive" ? "is not null" : "is null"} then
    return ${submissionJson("v_row")};
  end if;${
    verb === "archive"
      ? `
  if v_row.${s("status")} = 'draft' then
    ${fail("FORM_SUBMISSION_DRAFT", "a draft isn't submitted yet", "55000")}
  end if;`
      : ""
  }
  update ${submissions} x set
    ${s("archivedAt")} = ${verb === "archive" ? "now()" : "null"},
    ${s("updatedAt")} = now()
  where x.${s("id")} = v_row.${s("id")}
  returning * into v_row;
  ${submissionRecord(`form_submission.${past}`, "v_row", "", true)}
  return ${submissionJson("v_row")};
end;
$$;
${userGrant(`${fn(name)}(uuid)`)}
`;
    })
    .join("");
}
