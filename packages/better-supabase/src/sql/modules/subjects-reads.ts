import type { SubjectsEvents } from "../../blocks/subjects/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
} from "../context.ts";
import type { RegisteredSubject } from "../subject-registry.ts";

import { DEFAULT_READ_COLLAPSE_SECONDS } from "../../blocks/subjects/options.ts";
import { isRecord } from "../../core/guards.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import { fail, pageSize, SERVICE_CALLER, userGrant } from "../shared.ts";
import { auditedSubjects, registeredIdMatches } from "../subject-registry.ts";
import {
  representationActive,
  REPRESENTS,
} from "./contacts-representatives.ts";
import { OPERATIONS } from "./permissions-model.ts";
import { activeFor, leadRole, recordTeamRoles } from "./subjects-team.ts";

export const SUBJECT_READ_EVENTS: BlockSqlEvents<SubjectsEvents> = {
  "subject.accessed": {
    subject: "subjects",
    payload: [
      "organizationId",
      "subjectType",
      "subjectId",
      "purpose",
      "emergency",
      "block",
      "function",
    ],
  },
};

/** The most entries one `subject_access_log` call returns. */
const MAX_LOG_ENTRIES = 500;

/** The longest purpose `record_subject_read` keeps. */
const MAX_PURPOSE = 500;

/** A day: the longest `reads.collapseSeconds`. */
const MAX_COLLAPSE_SECONDS = 86_400;

/** `blocks.subjects.options.reads.collapseSeconds`, checked. */
function collapseSeconds(ctx: BlockSqlContext): number {
  const raw = ctx.option("reads");

  if (raw === undefined) {
    return DEFAULT_READ_COLLAPSE_SECONDS;
  }

  const seconds: unknown = isRecord(raw) ? raw["collapseSeconds"] : undefined;

  if (isRecord(raw) && seconds === undefined) {
    return DEFAULT_READ_COLLAPSE_SECONDS;
  }

  if (
    typeof seconds !== "number" ||
    !Number.isInteger(seconds) ||
    seconds < 0 ||
    seconds > MAX_COLLAPSE_SECONDS
  ) {
    throw new TypeError(
      `blocks.subjects.options.reads.collapseSeconds must be a whole number of seconds from 0 to ${String(MAX_COLLAPSE_SECONDS)}`,
    );
  }

  return seconds;
}

/**
 * The subjects whose reads are logged, or none when the `audit` module isn't
 * installed. A type with `auditReads` and no audit log is a config mistake.
 */
function readLoggedSubjects(
  ctx: BlockSqlContext,
  subjects: readonly RegisteredSubject[],
): readonly RegisteredSubject[] {
  const audited = auditedSubjects(subjects);

  if (audited.length === 0) {
    return [];
  }

  if (!ctx.installed("audit") || ctx.of("audit").mode === "custom") {
    throw new TypeError(
      `subjects.${audited[0]!.type}.auditReads needs the audit block in managed or adopt mode; add it to blocks`,
    );
  }

  return audited;
}

/** The `case` that puts the tenant of record `<fnName>.subject_id` in v_tenant. */
function tenantLookup(
  audited: readonly RegisteredSubject[],
  fnName: string,
): string {
  return `  case ${fnName}.subject_type
${audited
  .map((subject) => {
    const live =
      subject.config.deletedAt === undefined
        ? ""
        : ` and s.${sqlIdent(subject.config.deletedAt)} is null`;

    return `    when ${sqlString(subject.type)} then
      select s.${subject.tenant!} into v_tenant from ${subject.qualified} s
      where ${registeredIdMatches(subject, `${fnName}.subject_id`)}${live};`;
  })
  .join("\n")}
    else
      v_tenant := null;
  end case;`;
}

/**
 * The caller represents record `<fnName>.subject_type/subject_id` with `act`
 * authority, as a guest of the person they are; false without relations or
 * guests.
 */
function representsWithAct(ctx: BlockSqlContext, fnName: string): string {
  if (!ctx.installed("relations") || ctx.of("relations").mode === "custom") {
    return "false";
  }

  const relations = ctx.of("relations");

  const r = (column: string): string =>
    `r.${relations.col("relations", column)}`;

  const person = sqlString(ctx.naming.rename("person"));
  const guest = ctx.scope.guestParty("v_tenant", person, r("sourceId"));

  if (guest === "false") {
    return "false";
  }

  return `exists (
      select 1 from ${relations.table("relations")} r
      where ${r("kind")} = ${sqlString(REPRESENTS)} and ${r("sourceType")} = ${person}
        and ${r("tenant")}::text = v_tenant::text
        and ${r("targetType")} = ${fnName}.subject_type and ${r("targetId")} = ${fnName}.subject_id
        and ${r("data")} ->> 'authority' = 'act'
        and ${representationActive(r("data"))}
        and ${guest})`;
}

/**
 * Read logging (`subjects.<type>.auditReads`, ADR 0134): `record_subject_read`,
 * which the blocks' read functions call through `ctx.read`, and
 * `subject_access_log`, which lists who read a record. Empty when no type opts
 * in.
 */
export function subjectReadsSql(
  ctx: BlockSqlContext,
  subjects: readonly RegisteredSubject[],
): string {
  const audited = readLoggedSubjects(ctx, subjects);

  if (audited.length === 0) {
    return "";
  }

  const fn = (name: string): string => ctx.fn(name);
  const audit = ctx.of("audit");
  const l = (column: string): string => `l.${audit.col("log", column)}`;
  const m = (column: string): string => `m.${ctx.col("members", column)}`;
  const collapse = collapseSeconds(ctx);
  const types = sqlString(`{${audited.map((each) => each.type).join(",")}}`);
  const lead = sqlString(leadRole(recordTeamRoles(ctx)));
  const viewAudit = audit.permission("view", OPERATIONS["audit.view"]);

  const onRecord = (fnName: string): string =>
    `${m("subjectType")} = ${fnName}.subject_type
        and ${m("subjectId")} = ${fnName}.subject_id
        and ${m("tenant")} = v_tenant`;

  const events = audit.has("log", "table")
    ? `${l("table")} is null\n        and `
    : "";

  const ofRecord = `${events}${l("record")} = record_subject_read.subject_id
        and ${l("eventType")} = 'subject.accessed'
        and ${l("tenant")} = v_tenant
        and ${l("metadata")} ->> 'subjectType' = record_subject_read.subject_type`;

  const collapsed =
    collapse === 0
      ? ""
      : `
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('better_supabase.record_subject_read'),
    pg_catalog.hashtext(auth.uid()::text || ':' || record_subject_read.subject_type || ':' || record_subject_read.subject_id));
  if exists (
    select 1 from ${audit.table("log")} l
    where ${ofRecord}
      and ${l("actor")} = auth.uid()
      and ${l("occurredAt")} > now() - make_interval(secs => ${String(collapse)})
      and coalesce((${l("metadata")} ->> 'emergency')::boolean, false) = v_emergency
      and ${l("metadata")} ->> 'purpose' is not distinct from v_purpose
  ) then
    return;
  end if;`;

  const entry = ctx.audit({
    type: "subject.accessed",
    payload: `jsonb_build_object('organizationId', v_tenant, 'subjectType', record_subject_read.subject_type, 'subjectId', record_subject_read.subject_id, 'purpose', v_purpose, 'emergency', v_emergency, 'block', record_subject_read.block_name, 'function', record_subject_read.function_name)`,
    subject: `'subjects/' || record_subject_read.subject_type || '/' || record_subject_read.subject_id`,
    tenant: "v_tenant",
    audit: {
      category: "read",
      targetType: "subject",
      recordId: "record_subject_read.subject_id",
      summary: `'Read ' || record_subject_read.subject_type || ' ' || record_subject_read.subject_id`,
    },
  });

  const allowed = [
    SERVICE_CALLER,
    ctx.can("tenant", "v_tenant", viewAudit),
    `exists (
      select 1 from ${ctx.table("members")} m
      where ${onRecord("subject_access_log")}
        and ${m("role")} = ${lead}
        and ${activeFor(ctx, "auth.uid()", "table")})`,
    ctx.scope.guestParty(
      "v_tenant",
      "subject_access_log.subject_type",
      "subject_access_log.subject_id",
    ),
    representsWithAct(ctx, "subject_access_log"),
  ].filter((clause) => clause !== "false");

  const entryJson = `jsonb_build_object(
      'id', ${l("id")}::text,
      'actorId', ${l("actor")},
      'actorName', (select coalesce(u.raw_user_meta_data ->> 'full_name', u.raw_user_meta_data ->> 'name', u.email::text) from auth.users u where u.id = ${l("actor")}),
      'at', ${l("occurredAt")},
      'purpose', ${l("metadata")} ->> 'purpose',
      'emergency', coalesce((${l("metadata")} ->> 'emergency')::boolean, false),
      'block', ${l("metadata")} ->> 'block',
      'function', ${l("metadata")} ->> 'function')`;

  return `
-- Logs that the caller read a record whose type has auditReads (category
-- read, event subject.accessed), with the NEN 7513 fields. Another type, a
-- missing record, a record the caller can't read or a call without a user
-- logs nothing. A read within ${String(collapse)} seconds of the caller's last
-- logged read of the record (reads.collapseSeconds) writes no new entry,
-- unless it gives another purpose or only one of the two was under emergency
-- access.
create or replace function ${fn("record_subject_read")}(subject_type text, subject_id text, purpose text default null, block_name text default null, function_name text default null)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_emergency boolean;
  v_purpose text := nullif(btrim(record_subject_read.purpose), '');
begin
  if auth.uid() is null or not (record_subject_read.subject_type = any (${types}::text[])) then
    return;
  end if;
  if length(v_purpose) > ${String(MAX_PURPOSE)} then
    ${fail("SUBJECT_READ_INVALID", `purpose takes at most ${String(MAX_PURPOSE)} characters`, "22023")}
  end if;
  begin
${tenantLookup(audited, "record_subject_read")}
  exception
    when invalid_text_representation then
      return;
  end;
  if v_tenant is null
    or not coalesce(${fn("can_subject")}(record_subject_read.subject_type, record_subject_read.subject_id, 'read'), false) then
    return;
  end if;
  v_emergency := exists (
    select 1 from ${ctx.table("members")} m
    where ${onRecord("record_subject_read")}
      and ${m("emergency")}
      and ${activeFor(ctx, "auth.uid()", "table")}
  );${collapsed}
  ${entry}
end;
$$;
${userGrant(`${fn("record_subject_read")}(text, text, text, text, text)`)}

-- Who read a record and when, newest first: the subject.accessed entries of
-- the audit log since \`since\`. The holders of ${OPERATIONS["audit.view"]} in
-- its tenant, the record team's leads today, the record's own guest party
-- and a representative with act authority may ask.
create or replace function ${fn("subject_access_log")}(subject_type text, subject_id text, since timestamptz default null, max_rows integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  if not (subject_access_log.subject_type = any (${types}::text[])) then
    ${fail("SUBJECT_READ_INVALID", "this subject type does not log reads", "22023")}
  end if;
  begin
${tenantLookup(audited, "subject_access_log")}
  exception
    when invalid_text_representation then
      v_tenant := null;
  end;
  if v_tenant is null then
    ${fail("SUBJECT_READ_NOT_FOUND", "subject not found", "P0002")}
  end if;
  if not (${allowed.join("\n    or ")}) then
    ${fail("SUBJECT_READ_FORBIDDEN", "you may not see who read this record")}
  end if;
  return (
    select coalesce(jsonb_agg(e.entry order by e.at desc), '[]'::jsonb)
    from (
      select ${entryJson} as entry, ${l("occurredAt")} as at
      from ${audit.table("log")} l
      where ${ofRecord.replaceAll("record_subject_read.", "subject_access_log.")}
        and (subject_access_log.since is null or ${l("occurredAt")} >= subject_access_log.since)
      order by ${l("occurredAt")} desc
      limit ${pageSize("subject_access_log.max_rows", 100, MAX_LOG_ENTRIES)}
    ) e
  );
end;
$$;
${userGrant(`${fn("subject_access_log")}(text, text, timestamptz, integer)`)}
`;
}

/** The read logging functions, when some type has `auditReads`. */
export function subjectReadsContract(
  ctx: BlockSqlContext,
  subjects: readonly RegisteredSubject[],
): readonly BlockSqlContractFunction[] {
  return auditedSubjects(subjects).length === 0 || !ctx.installed("audit")
    ? []
    : [
        {
          name: "record_subject_read",
          args: ["text", "text", "text", "text", "text"],
          returns: "void",
        },
        {
          name: "subject_access_log",
          args: ["text", "text", "timestamptz", "integer"],
          returns: "jsonb",
        },
      ];
}
