import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";
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

const NAMES: BlockSqlNames = { tables: {} };

/**
 * The permission check for `action` on row `s`, `true` when the action has no
 * key.
 */
function actionCheck(ctx: BlockSqlContext, subject: RegisteredSubject): string {
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
  /** The rows counted, aliased `x`, with their record in `type` and `id`. */
  readonly from: string;
  readonly subjectType: string;
  readonly subjectId: string;
  /** The column whose newest value marks the section unread. */
  readonly latest: string;
  /** Extra conditions a counted row meets, such as not being deleted. */
  readonly live?: string;
  /**
   * When the caller last read the section, as a SQL expression; the `seen_at`
   * argument is the fallback.
   */
  readonly readAt?: string;
}

/**
 * The sections `record_summary` counts: each installed managed module whose
 * rows the caller reads through policies. Taggings have no read policy (tags
 * are read through `subject_tags`), so tags aren't counted. Comments are the
 * sent messages of the record's conversation, unread after the caller's read
 * marker on it.
 */
function summarySections(ctx: BlockSqlContext): readonly SummarySection[] {
  const of = (module: string): BlockSqlContext | undefined =>
    ctx.installed(module) && ctx.of(module).mode !== "custom"
      ? ctx.of(module)
      : undefined;

  const messaging = of("comments") === undefined ? undefined : of("messaging");
  const attachments = of("attachments");

  return [
    ...(messaging === undefined
      ? []
      : [
          {
            name: "comments",
            from: `${messaging.table("messages")} x
      join ${messaging.table("conversations")} c on c.${messaging.col("conversations", "id")} = x.${messaging.col("messages", "conversation")}
        and c.${messaging.col("conversations", "kind")} = 'subject'`,
            subjectType: `c.${messaging.col("conversations", "subjectType")}`,
            subjectId: `c.${messaging.col("conversations", "subjectId")}`,
            latest: `x.${messaging.col("messages", "sentAt")}`,
            live: `x.${messaging.col("messages", "sentAt")} is not null and x.${messaging.col("messages", "deletedAt")} is null`,
            readAt: `(select ${messaging.fn("conversation_read_at")}(c.${messaging.col("conversations", "id")}) from ${messaging.table("conversations")} c
        where c.${messaging.col("conversations", "kind")} = 'subject'
          and c.${messaging.col("conversations", "subjectType")} = record_summary.subject_type
          and c.${messaging.col("conversations", "subjectId")} = record_summary.subject_id)`,
          },
        ]),
    ...(attachments === undefined
      ? []
      : [
          {
            name: "attachments",
            from: `${attachments.table("attachments")} x`,
            subjectType: `x.${attachments.col("attachments", "subjectType")}`,
            subjectId: `x.${attachments.col("attachments", "subjectId")}`,
            latest: `x.${attachments.col("attachments", "uploadedAt")}`,
            live: `x.${attachments.col("attachments", "uploadedAt")} is not null and x.${attachments.col("attachments", "status")} <> 'infected'`,
          },
        ]),
  ];
}

/** The `record_summary` step that counts one section. */
function summaryBranch(section: SummarySection): string {
  const seen =
    section.readAt === undefined
      ? "record_summary.seen_at"
      : `coalesce(${section.readAt}, record_summary.seen_at)`;

  return `  if ${sqlString(section.name)} = any (record_summary.sections) then
    select count(*), max(${section.latest})
      into v_count, v_latest
      from ${section.from}
      where ${section.subjectType}::text = record_summary.subject_type
        and ${section.subjectId}::text = record_summary.subject_id${
          section.live === undefined ? "" : `\n        and ${section.live}`
        };
    v_seen := ${seen};
    v_counts := v_counts || jsonb_build_object(${sqlString(section.name)}, v_count);
    v_unread := v_unread || jsonb_build_object(${sqlString(section.name)},
      v_seen is not null and v_latest is not null and v_latest > v_seen);
  end if;`;
}

/** The most items one `my_work` call returns. */
const MAX_WORK_ITEMS = 200;

/**
 * The `my_work` branches, one per installed managed module whose rows wait on
 * the caller. Each selects `kind, subject_type, subject_id, ref, title, at`; a
 * null title falls back to `subject_title`.
 */
function workBranches(ctx: BlockSqlContext): readonly string[] {
  const of = (module: string): BlockSqlContext | undefined =>
    ctx.installed(module) && ctx.of(module).mode !== "custom"
      ? ctx.of(module)
      : undefined;

  const tenant = (column: string): string =>
    `(my_work.tenant is null or ${column} = my_work.tenant)`;

  const work = of("tasks");
  const approvals = of("approvals");
  const reminders = of("reminders");
  const messaging = of("comments") === undefined ? undefined : of("messaging");
  const sla = of("sla");
  const branches: string[] = [];

  const workType =
    work === undefined
      ? undefined
      : sqlString(
          work.resolved.entities["work_item"]?.to.singular ?? "work_item",
        );

  if (work !== undefined && workType !== undefined) {
    const w = (column: string): string => `i.${work.col("items", column)}`;

    branches.push(`select 'assigned'::text, ${workType}::text, ${w("id")}::text, ${w("id")}::text, ${w("title")}::text,
      coalesce(${w("dueAt")}, a.${work.col("assignees", "createdAt")})
    from ${work.table("assignees")} a
    join ${work.table("items")} i on ${w("id")} = a.${work.col("assignees", "item")}
    where a.${work.col("assignees", "user")} = v_me
      and ${w("state")} not in ('completed', 'canceled')
      and ${w("archivedAt")} is null
      and ${tenant(w("tenant"))}`);
  }

  if (approvals !== undefined) {
    const r = (column: string): string =>
      `r.${approvals.col("requests", column)}`;

    branches.push(`select 'approval'::text, ${r("subjectType")}::text, ${r("subjectId")}::text, ${r("id")}::text, null::text,
      ${r("createdAt")}
    from ${approvals.table("requests")} r
    where ${r("status")} = 'pending'
      and (${r("expiresAt")} is null or ${r("expiresAt")} > now())
      and ${tenant(r("tenant"))}
      and ${approvals.fn("approval_eligible")}(${r("id")})`);
  }

  if (reminders !== undefined) {
    branches.push(`select 'reminder'::text, d.subject_type, d.subject_id, d.reminder::text, null::text, d.at
    from ${ctx.fn("my_reminders_due")}(my_work.tenant) d
    where ${ctx.fn("can_subject")}(d.subject_type, d.subject_id, 'read')`);
  }

  if (messaging !== undefined) {
    const m = (column: string): string =>
      `m.${messaging.col("messages", column)}`;

    const c = (column: string): string =>
      `c.${messaging.col("conversations", column)}`;

    branches.push(`select 'mention'::text, ${c("subjectType")}::text, ${c("subjectId")}::text, ${m("id")}::text, null::text,
      ${m("sentAt")}
    from ${messaging.table("messages")} m
    join ${messaging.table("conversations")} c on ${c("id")} = ${m("conversation")} and ${c("kind")} = 'subject'
    where v_me = any (${m("mentions")})
      and ${m("deletedAt")} is null
      and ${m("sentAt")} > now() - interval '30 days'
      and ${tenant(m("tenant"))}`);
  }

  if (sla !== undefined && work !== undefined && workType !== undefined) {
    const k = (column: string): string => `k.${sla.col("clocks", column)}`;

    branches.push(`select 'sla'::text, ${k("subjectType")}::text, ${k("subjectId")}::text, ${k("id")}::text, null::text,
      ${k("dueAt")}
    from ${sla.table("clocks")} k
    where ${k("subjectType")} = ${workType}
      and ${k("warnedAt")} is not null
      and ${k("metAt")} is null
      and ${tenant(k("tenant"))}
      and exists (
        select 1 from ${work.table("assignees")} a
        where a.${work.col("assignees", "item")}::text = ${k("subjectId")}::text
          and a.${work.col("assignees", "user")} = v_me)`);
  }

  return branches;
}

/** `my_work` and the reminders it reads through a definer helper. */
function myWork(ctx: BlockSqlContext): string {
  const fn = (name: string): string => ctx.fn(name);
  const branches = workBranches(ctx);

  const reminders =
    ctx.installed("reminders") && ctx.of("reminders").mode !== "custom"
      ? ctx.of("reminders")
      : undefined;

  const helper =
    reminders === undefined
      ? ""
      : `
-- The caller's own reminders sent in the last week, for my_work. Reminders
-- have no read policy, so this reads them past it, keeping only the caller's.
create or replace function ${fn("my_reminders_due")}(tenant ${ctx.idType} default null)
returns table (reminder uuid, subject_type text, subject_id text, at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select r.${reminders.col("reminders", "id")}, r.${reminders.col("reminders", "subjectType")}::text,
    r.${reminders.col("reminders", "subjectId")}::text, max(d.${reminders.col("deliveries", "occurrenceAt")})
  from ${reminders.table("reminders")} r
  join ${reminders.table("deliveries")} d on d.${reminders.col("deliveries", "reminder")} = r.${reminders.col("reminders", "id")}
  where r.${reminders.col("reminders", "user")} = (select auth.uid())
    and (my_reminders_due.tenant is null or r.${reminders.col("reminders", "tenant")} = my_reminders_due.tenant)
    and d.${reminders.col("deliveries", "sentAt")} > now() - interval '7 days'
  group by 1, 2, 3
$$;
${userGrant(`${fn("my_reminders_due")}(${ctx.idType})`)}
`;

  const body =
    branches.length === 0
      ? "  return '[]'::jsonb;"
      : `  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'kind', w.kind,
      'subject', jsonb_build_object('type', w.subject_type, 'id', w.subject_id),
      'ref', w.ref,
      'title', coalesce(w.title, ${fn("subject_title")}(w.subject_type, w.subject_id)),
      'url', ${fn("subject_url")}(w.subject_type, w.subject_id),
      'at', w.at
    ) order by w.at desc nulls last, w.kind, w.ref), '[]'::jsonb)
    from (
      select * from (
    ${branches.join("\n    union all\n    ")}
      ) u (kind, subject_type, subject_id, ref, title, at)
      order by u.at desc nulls last, u.kind, u.ref
      limit least(greatest(coalesce(my_work.page_size, 50), 1), ${MAX_WORK_ITEMS})
    ) w
  );`;

  return `${helper}
-- What waits on the caller across the installed blocks, newest first: open
-- work items assigned to them, approvals they can decide, their reminders
-- sent this week, mentions from the last 30 days and SLA clocks warned on
-- their work items. Runs as the caller, so each row is one they can read.
create or replace function ${fn("my_work")}(tenant ${ctx.idType} default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    return '[]'::jsonb;
  end if;
${body}
end;
$$;
${userGrant(`${fn("my_work")}(${ctx.idType}, integer)`)}
`;
}

function build(ctx: BlockSqlContext): string {
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
-- key in config.records.<type>.permissions, holds that key in the
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
  v_seen timestamptz;
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
-- action's key in config.records.<type>.permissions, so an action without
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
${myWork(ctx)}${presenceSql(ctx)}`;
}

/** The prefix of a subject's presence topic, `presence:<type>:<id>`. */
const PRESENCE_TOPIC_PREFIX = "presence";

/**
 * Realtime presence on `presence:<type>:<id>`: who has a record open. A caller
 * who can read the subject joins, tracks and sees the others there.
 */
function presenceSql(ctx: BlockSqlContext): string {
  const fn = (name: string): string => ctx.fn(name);
  const receive = ctx.trigger("subject_presence_receive");
  const send = ctx.trigger("subject_presence_send");
  const prefix = sqlString(`${PRESENCE_TOPIC_PREFIX}:`);

  const check = `realtime.messages.extension = 'presence'
        and (select realtime.topic()) like ${prefix} || '%'
        and ${fn("subject_presence_allowed")}((select realtime.topic()))`;

  return `
-- Whether the caller may join presence topic \`topic\`
-- (presence:<type>:<id>): they can read that subject.
create or replace function ${fn("subject_presence_allowed")}(topic text)
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_parts text[] := regexp_match(subject_presence_allowed.topic, '^${PRESENCE_TOPIC_PREFIX}:([a-z][a-z0-9_]{0,62}):([^:]{1,200})$');
begin
  if v_parts is null then
    return false;
  end if;
  return coalesce(${fn("can_subject")}(v_parts[1], v_parts[2], 'read'), false);
exception
  when invalid_text_representation then
    return false;
end;
$$;
${userGrant(`${fn("subject_presence_allowed")}(text)`)}

do $$
begin
  if to_regclass('realtime.messages') is not null then
    drop policy if exists ${receive} on realtime.messages;
    create policy ${receive} on realtime.messages for select to authenticated
      using (
        ${check}
      );
    drop policy if exists ${send} on realtime.messages;
    create policy ${send} on realtime.messages for insert to authenticated
      with check (
        ${check}
      );
  end if;
end;
$$;
`;
}

function contract(): readonly BlockSqlContractFunction[] {
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
    { name: "my_work", args: ["{id}", "integer"], returns: "jsonb" },
    { name: "subject_presence_allowed", args: ["text"], returns: "boolean" },
  ];
}

export const SUBJECTS: BlockSqlDefinition = {
  name: "subjects",
  scopes: ["tenant"],
  title: "Subjects",
  description:
    "The app-wide subject registry from config.records: subject_title, subject_url, subject_titles, can_subject, can_subject_for and record_summary for every registered type, my_work across the installed blocks, and Realtime presence on presence:<type>:<id> for readers of the subject.",
  requires: ["permissions"],
  integrates: [
    "comments",
    "messaging",
    "attachments",
    "tasks",
    "approvals",
    "reminders",
    "sla",
  ],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
