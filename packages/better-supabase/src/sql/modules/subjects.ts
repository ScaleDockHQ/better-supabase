import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";
import type { RegisteredSubject } from "../subject-registry.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  SERVICE_CALLER,
  schemaPreamble,
  serviceGrant,
  userGrant,
} from "../shared.ts";
import {
  registeredIdMatches,
  registeredSubjects,
  urlExpression,
} from "../subject-registry.ts";

const NAMES: ModuleNames = { tables: {} };

/**
 * The permission check for `action` on row `s`, `true` when the action has no
 * key.
 */
function actionCheck(ctx: ModuleContext, subject: RegisteredSubject): string {
  const permissions = Object.entries(subject.config.permissions ?? {});

  if (permissions.length === 0) {
    return "true";
  }

  const scope = subject.config.scope;

  const held = (key: string): string => {
    const parts = [
      ...(subject.tenant === undefined
        ? []
        : [ctx.can("tenant", `s.${subject.tenant}`, sqlString(key))]),
      ...(scope === undefined
        ? []
        : [ctx.can(scope, `s.${subject.id}::text`, sqlString(key))]),
    ];

    return parts.length === 1 ? parts[0]! : `(${parts.join(" or ")})`;
  };

  return `(${SERVICE_CALLER} or case can_subject.action\n${permissions
    .map(
      ([action, key]) =>
        `          when ${sqlString(action)} then ${held(key)}`,
    )
    .join("\n")}\n          else true\n        end)`;
}

/**
 * `user` holds the key for `action` on row `s`, through `can_user`. An action
 * without a key is false: nothing but the row's policies would decide it, and
 * they answer for the caller only.
 */
function actionCheckFor(subject: RegisteredSubject, user: string): string {
  const permissions = Object.entries(subject.config.permissions ?? {});

  if (permissions.length === 0) {
    return "false";
  }

  const scope = subject.config.scope;

  const held = (key: string): string => {
    const userCan = (scopeName: string, id: string): string =>
      `coalesce(better_supabase.can_user(${user}, ${sqlString(scopeName)}, ${id}, ${sqlString(key)}), false)`;

    const parts = [
      ...(subject.tenant === undefined
        ? []
        : [userCan("tenant", `s.${subject.tenant}`)]),
      ...(scope === undefined ? [] : [userCan(scope, `s.${subject.id}::text`)]),
    ];

    return parts.length === 1 ? parts[0]! : `(${parts.join(" or ")})`;
  };

  return `case can_subject_for.action\n${permissions
    .map(
      ([action, key]) =>
        `          when ${sqlString(action)} then ${held(key)}`,
    )
    .join("\n")}\n          else false\n        end`;
}

/** The row `s` is `id` and, with `deletedAt`, not soft-deleted. */
function rowMatches(subject: RegisteredSubject, id: string): string {
  const match = registeredIdMatches(subject, id);

  return subject.config.deletedAt === undefined
    ? match
    : `${match} and s.${sqlIdent(subject.config.deletedAt)} is null`;
}

function cases(
  subjects: readonly RegisteredSubject[],
  branch: (subject: RegisteredSubject) => string | undefined,
): string {
  const whens = subjects.flatMap((subject) => {
    const body = branch(subject);

    return body === undefined
      ? []
      : [`    when ${sqlString(subject.type)} then\n      ${body}`];
  });

  return whens.length === 0 ? "    when '' then null;" : whens.join("\n");
}

/** The most refs one `subject_titles` call resolves. */
const MAX_TITLE_REFS = 500;

/** The `subject_titles` step that adds the refs of `subject`'s type. */
function titlesBranch(subject: RegisteredSubject): string {
  const ids = `select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = ${sqlString(subject.type)}`;
  const idType = subject.config.idType;

  const match =
    idType === undefined
      ? `s.${subject.id}::text = any(array(${ids}))`
      : `s.${subject.id} = any(array(${ids})::${idType}[])`;

  const live =
    subject.config.deletedAt === undefined
      ? ""
      : ` and s.${sqlIdent(subject.config.deletedAt)} is null`;

  const title =
    subject.config.title === undefined
      ? "null::text"
      : `s.${sqlIdent(subject.config.title)}::text`;

  const url =
    subject.config.url === undefined
      ? "null::text"
      : urlExpression(subject.config.url);

  return `  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', ${sqlString(subject.type)}, 'id', s.${subject.id}::text,
      'title', ${title}, 'url', ${url}))
    from ${subject.qualified} s
    where ${match}${live}), '[]'::jsonb);`;
}

/** The most sections one `record_summary` call counts. */
const MAX_SUMMARY_SECTIONS = 20;

interface SummarySection {
  readonly name: string;
  readonly table: string;
  readonly subjectType: string;
  readonly subjectId: string;
  /** The column whose newest value marks the section unread. */
  readonly latest: string;
  /** Extra conditions a counted row meets, such as not being deleted. */
  readonly live?: string;
}

/**
 * The sections `record_summary` counts: each installed managed module whose
 * rows the caller reads through policies. Taggings have no read policy (tags
 * are read through `subject_tags`), so tags aren't counted.
 */
function summarySections(ctx: ModuleContext): readonly SummarySection[] {
  const of = (module: string): ModuleContext | undefined =>
    ctx.installed(module) && ctx.of(module).mode !== "custom"
      ? ctx.of(module)
      : undefined;

  const comments = of("comments");
  const attachments = of("attachments");

  return [
    ...(comments === undefined
      ? []
      : [
          {
            name: "comments",
            table: comments.table("comments"),
            subjectType: comments.col("comments", "subjectType"),
            subjectId: comments.col("comments", "subjectId"),
            latest: comments.col("comments", "createdAt"),
            live: `x.${comments.col("comments", "deletedAt")} is null`,
          },
        ]),
    ...(attachments === undefined
      ? []
      : [
          {
            name: "attachments",
            table: attachments.table("attachments"),
            subjectType: attachments.col("attachments", "subjectType"),
            subjectId: attachments.col("attachments", "subjectId"),
            latest: attachments.col("attachments", "uploadedAt"),
            live: `x.${attachments.col("attachments", "uploadedAt")} is not null and x.${attachments.col("attachments", "status")} <> 'infected'`,
          },
        ]),
  ];
}

/** The `record_summary` step that counts one section. */
function summaryBranch(section: SummarySection): string {
  return `  if ${sqlString(section.name)} = any (record_summary.sections) then
    select count(*), max(x.${section.latest})
      into v_count, v_latest
      from ${section.table} x
      where x.${section.subjectType}::text = record_summary.subject_type
        and x.${section.subjectId}::text = record_summary.subject_id${
          section.live === undefined ? "" : `\n        and ${section.live}`
        };
    v_counts := v_counts || jsonb_build_object(${sqlString(section.name)}, v_count);
    v_unread := v_unread || jsonb_build_object(${sqlString(section.name)},
      record_summary.seen_at is not null and v_latest is not null and v_latest > record_summary.seen_at);
  end if;`;
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const subjects = registeredSubjects(ctx.subjects, ctx.naming);
  const fn = (name: string): string => ctx.fn(name);

  return `${schemaPreamble(ctx)}
-- The app's subject registry (config.subjects, ADR 0020). Each function runs
-- as the caller, so the subject table's own policies decide what is visible.
create or replace function ${fn("subject_types")}()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select ${sqlString(`{${subjects.map((subject) => subject.type).join(",")}}`)}::text[]
$$;
${userGrant(`${fn("subject_types")}()`)}

create or replace function ${fn("subject_title")}(subject_type text, subject_id text)
returns text
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  case subject_title.subject_type
${cases(subjects, (subject) =>
  subject.config.title === undefined
    ? undefined
    : `return (select s.${sqlIdent(subject.config.title)}::text from ${subject.qualified} s where ${rowMatches(subject, "subject_title.subject_id")});`,
)}
    else
      return null;
  end case;
  return null;
end;
$$;
${userGrant(`${fn("subject_title")}(text, text)`)}

create or replace function ${fn("subject_url")}(subject_type text, subject_id text)
returns text
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  case subject_url.subject_type
${cases(subjects, (subject) =>
  subject.config.url === undefined
    ? undefined
    : `return (select ${urlExpression(subject.config.url)} from ${subject.qualified} s where ${rowMatches(subject, "subject_url.subject_id")});`,
)}
    else
      return null;
  end case;
  return null;
end;
$$;
${userGrant(`${fn("subject_url")}(text, text)`)}

-- Titles and paths for many subjects in one call: refs is a JSON array of
-- { "type", "id" }, the result one of { type, id, title, url }. A row the
-- caller can't see, an unknown type or a soft-deleted row returns nothing.
create or replace function ${fn("subject_titles")}(refs jsonb)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  found jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(subject_titles.refs) is distinct from 'array' then
    raise exception 'refs must be a JSON array of { type, id }'
      using errcode = '22023', hint = 'SUBJECT_REFS_INVALID';
  end if;
  if jsonb_array_length(subject_titles.refs) > ${MAX_TITLE_REFS} then
    raise exception 'subject_titles takes at most ${MAX_TITLE_REFS} refs'
      using errcode = '22023', hint = 'SUBJECT_REFS_TOO_MANY';
  end if;
${subjects.map((subject) => titlesBranch(subject)).join("\n")}
  return found;
exception
  when invalid_text_representation then
    raise exception 'a subject id does not match its type''s id column'
      using errcode = '22023', hint = 'SUBJECT_ID_INVALID';
end;
$$;
${userGrant(`${fn("subject_titles")}(jsonb)`)}

-- True when the caller can see the subject row and, for an action with a
-- key in config.subjects.<type>.permissions, holds that key in the
-- subject's tenant (or on the record, through the subject's scope).
create or replace function ${fn("can_subject")}(subject_type text, subject_id text, action text)
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  case can_subject.subject_type
${cases(
  subjects,
  (subject) =>
    `return exists (
        select 1 from ${subject.qualified} s
        where ${rowMatches(subject, "can_subject.subject_id")}
          and ${actionCheck(ctx, subject)}
      );`,
)}
    else
      return false;
  end case;
  return false;
end;
$$;
${userGrant(`${fn("can_subject")}(text, text, text)`)}

-- A record page's header and tab badges in one call: the subject's title and
-- path, how many rows each named section has and whether any is newer than
-- seen_at. Runs as the caller, so each count is what the caller can read;
-- null when the caller can't read the subject. An unknown section is left out.
create or replace function ${fn("record_summary")}(subject_type text, subject_id text, sections text[], seen_at timestamptz default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_counts jsonb := '{}'::jsonb;
  v_unread jsonb := '{}'::jsonb;
  v_count bigint;
  v_latest timestamptz;
begin
  if coalesce(cardinality(record_summary.sections), 0) > ${MAX_SUMMARY_SECTIONS} then
    raise exception 'record_summary takes at most ${MAX_SUMMARY_SECTIONS} sections'
      using errcode = '22023', hint = 'RECORD_SECTIONS_TOO_MANY';
  end if;
  if not ${fn("can_subject")}(record_summary.subject_type, record_summary.subject_id, 'read') then
    return null;
  end if;
${summarySections(ctx)
  .map((section) => summaryBranch(section))
  .join("\n")}
  return jsonb_build_object(
    'type', record_summary.subject_type,
    'id', record_summary.subject_id,
    'title', ${fn("subject_title")}(record_summary.subject_type, record_summary.subject_id),
    'url', ${fn("subject_url")}(record_summary.subject_type, record_summary.subject_id),
    'counts', v_counts,
    'unread', v_unread);
end;
$$;
${userGrant(`${fn("record_summary")}(text, text, text[], timestamptz)`)}

-- can_subject for another user, for server code that decides who receives
-- an event. It reads the row past its policies and asks can_user for the
-- action's key in config.subjects.<type>.permissions, so an action without
-- a key is false and a share-link grant never counts. A provider that
-- can't answer for others (no idsWithFor) gives false.
create or replace function ${fn("can_subject_for")}(member uuid, subject_type text, subject_id text, action text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  case can_subject_for.subject_type
${cases(
  subjects,
  (subject) =>
    `return exists (
        select 1 from ${subject.qualified} s
        where ${rowMatches(subject, "can_subject_for.subject_id")}
          and ${actionCheckFor(subject, "can_subject_for.member")}
      );`,
)}
    else
      return false;
  end case;
  return false;
exception
  when feature_not_supported then
    return false;
end;
$$;
${serviceGrant(`${fn("can_subject_for")}(uuid, text, text, text)`)}
`;
}

function contract(): readonly ModuleContractFunction[] {
  return [
    { name: "subject_types", args: [], returns: "text[]" },
    { name: "subject_title", args: ["text", "text"], returns: "text" },
    { name: "subject_url", args: ["text", "text"], returns: "text" },
    { name: "subject_titles", args: ["jsonb"], returns: "jsonb" },
    { name: "can_subject", args: ["text", "text", "text"], returns: "boolean" },
    {
      name: "record_summary",
      args: ["text", "text", "text[]", "timestamptz"],
      returns: "jsonb",
    },
    {
      name: "can_subject_for",
      args: ["uuid", "text", "text", "text"],
      returns: "boolean",
    },
  ];
}

export const SUBJECTS: ModuleDefinition = {
  name: "subjects",
  scopes: ["tenant"],
  title: "Subjects",
  description:
    "The app-wide subject registry from config.subjects: subject_title, subject_url, subject_titles, can_subject, can_subject_for and record_summary for every registered type.",
  requires: ["access"],
  integrates: ["comments", "attachments"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
