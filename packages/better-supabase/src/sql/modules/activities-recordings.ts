import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";

import { sqlIdent } from "../../core/template.ts";
import {
  fail,
  lockTable,
  pageSize,
  serviceGrant,
  userGrant,
} from "../shared.ts";

/** The queue `attach_engagement_recording` enqueues a transcription job on. */
const TRANSCRIBE_QUEUE = "engagements.transcribe";

/** The most segments one transcript keeps. */
const MAX_SEGMENTS = 20_000;

/** The tables `options.recordings` adds, for the module's names. */
export const RECORDING_TABLES = {
  recordings: {
    name: "engagement_recordings",
    app: {},
    optional: [
      "language",
      "durationSeconds",
      "error",
      "model",
      "createdBy",
      "transcribedAt",
    ],
    typed: ["status"],
    columns: {
      id: "id",
      tenant: "tenant_id",
      engagement: "engagement_id",
      file: "file_id",
      filename: "filename",
      mediaType: "media_type",
      status: "status",
      language: "language",
      durationSeconds: "duration_seconds",
      error: "error",
      model: "model",
      createdBy: "created_by",
      createdAt: "created_at",
      transcribedAt: "transcribed_at",
    },
  },
  segments: {
    name: "engagement_transcript_segments",
    app: {},
    optional: ["speaker", "speakerUser", "confidence"],
    columns: {
      recording: "recording_id",
      tenant: "tenant_id",
      position: "position",
      speaker: "speaker",
      speakerUser: "speaker_user_id",
      startsMs: "starts_ms",
      endsMs: "ends_ms",
      text: "text",
      confidence: "confidence",
    },
  },
  notes: {
    name: "engagement_notes",
    app: {},
    optional: ["model", "createdBy", "createdAt", "updatedAt"],
    typed: ["source"],
    columns: {
      engagement: "engagement_id",
      tenant: "tenant_id",
      summary: "summary",
      actionItems: "action_items",
      model: "model",
      source: "source",
      createdBy: "created_by",
      createdAt: "created_at",
      updatedAt: "updated_at",
    },
  },
} as const;

/** Whether `blocks.activities.options.recordings` is on. */
export const recordingsOn = (ctx: BlockSqlContext): boolean =>
  ctx.flag("recordings", false);

/**
 * Recordings and transcripts of calls and meetings, stored as ai-files files,
 * and notes an AI or a member writes about an engagement.
 */
export function recordingsSql(
  ctx: BlockSqlContext,
  helpers: {
    /** Whether the caller can edit the engagement row `alias`. */
    readonly editable: (alias: string) => string;
    /** The `ctx.record` statement for an event on engagement `id`. */
    readonly record: (
      event: string,
      id: string,
      type: string,
      tenant: string,
      extra?: string,
      key?: string,
    ) => string;
    /** Reads the subjects of engagement `id` into `v_subjects` and `v_first`. */
    readonly loadSubjects: (id: string) => string;
    /** The permission key that edits any engagement, as a SQL literal. */
    readonly manage: string;
    /** An engagement row `alias` as the module's reads return it. */
    readonly row: (alias: string) => string;
  },
): string {
  if (!ctx.installed("ai-files") || ctx.of("ai-files").mode !== "managed") {
    throw new TypeError(
      "blocks.activities.options.recordings needs the ai-files block in managed mode",
    );
  }

  const files = ctx.of("ai-files");
  const f = (column: string): string => files.col("files", column);
  const fileTable = files.table("files");
  const fn = (name: string): string => ctx.fn(name);
  const t = (table: string): string => ctx.table(table);
  const e = (column: string): string => ctx.col("engagements", column);
  const r = (column: string): string => ctx.col("recordings", column);
  const s = (column: string): string => ctx.col("segments", column);
  const n = (column: string): string => ctx.col("notes", column);
  const { editable, record, loadSubjects, manage, row } = helpers;

  /** Column `column` of row `alias` in `table`, or null when the app lacks it. */
  const field = (table: string, alias: string, column: string): string =>
    ctx.has(table, column) ? `${alias}.${ctx.col(table, column)}` : "null";

  const optional = (
    table: string,
    column: string,
    definition: (name: string) => string,
  ): string =>
    ctx.has(table, column) ? `\n  ${definition(ctx.col(table, column))},` : "";

  /** `,\n <column> = <value>` when `table` has `column`. */
  const set = (table: string, column: string, value: string): string =>
    ctx.has(table, column) ? `,\n    ${ctx.col(table, column)} = ${value}` : "";

  // Over the app's table the render drops the inline keys the upserts rely on.
  const key = (table: string, suffix: string, columns: string): string =>
    ctx.owns(table)
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName(table).name}_${suffix}`)} on ${t(table)} (${columns});`;

  const attached = (
    [
      ["tenant", "v_tenant"],
      ["engagement", "attach_engagement_recording.engagement"],
      ["file", `fx.${f("id")}`],
      ["filename", `fx.${f("filename")}`],
      ["mediaType", `fx.${f("mediaType")}`],
      ["language", "nullif(trim(attach_engagement_recording.language), '')"],
      ["createdBy", "auth.uid()"],
    ] as const
  ).filter(([column]) => ctx.has("recordings", column));

  const segmented = (
    [
      ["recording", "v_recording"],
      ["tenant", "v_tenant"],
      ["position", "i.ordinality::integer"],
      ["speaker", "nullif(i.value ->> 'speaker', '')"],
      ["speakerUser", "nullif(i.value ->> 'speakerUserId', '')::uuid"],
      ["startsMs", "round((i.value ->> 'startMs')::numeric)::integer"],
      ["endsMs", "round((i.value ->> 'endMs')::numeric)::integer"],
      ["text", "i.value ->> 'text'"],
      ["confidence", "(i.value ->> 'confidence')::real"],
    ] as const
  ).filter(([column]) => ctx.has("segments", column));

  const noted = (
    [
      ["engagement", "save_engagement_notes.engagement"],
      ["tenant", "v_tenant"],
      ["summary", "v_summary"],
      ["actionItems", "v_items"],
      ["model", "nullif(save_engagement_notes.notes ->> 'model', '')"],
      [
        "source",
        ctx.cast(
          "notes",
          "source",
          "case when save_engagement_notes.notes ->> 'source' = 'member' then 'member' else 'ai' end",
        ),
      ],
      ["createdBy", "auth.uid()"],
    ] as const
  ).filter(([column]) => ctx.has("notes", column));

  const recordingJson = (alias: string): string =>
    `jsonb_build_object('id', ${alias}.${r("id")}, 'organizationId', ${alias}.${r("tenant")}, 'engagementId', ${alias}.${r("engagement")}, 'fileId', ${alias}.${r("file")}, 'filename', ${alias}.${r("filename")}, 'mediaType', ${alias}.${r("mediaType")}, 'status', ${alias}.${r("status")}, 'language', ${field("recordings", alias, "language")}, 'durationSeconds', ${field("recordings", alias, "durationSeconds")}, 'error', ${field("recordings", alias, "error")}, 'model', ${field("recordings", alias, "model")}, 'segmentCount', (select count(*)::integer from ${t("segments")} sc where sc.${s("recording")} = ${alias}.${r("id")}), 'createdBy', ${field("recordings", alias, "createdBy")}, 'createdAt', ${alias}.${r("createdAt")}, 'transcribedAt', ${field("recordings", alias, "transcribedAt")})`;

  const oneRecording = (id: string): string =>
    `(select ${recordingJson("rx")} from ${t("recordings")} rx where rx.${r("id")} = ${id})`;

  const segmentJson = (alias: string): string =>
    `jsonb_build_object('position', ${alias}.${s("position")}, 'speaker', ${field("segments", alias, "speaker")}, 'speakerUserId', ${field("segments", alias, "speakerUser")}, 'startMs', ${alias}.${s("startsMs")}, 'endMs', ${alias}.${s("endsMs")}, 'text', ${alias}.${s("text")}, 'confidence', ${field("segments", alias, "confidence")})`;

  const notesJson = (alias: string): string =>
    `jsonb_build_object('engagementId', ${alias}.${n("engagement")}, 'organizationId', ${alias}.${n("tenant")}, 'summary', ${alias}.${n("summary")}, 'actionItems', ${alias}.${n("actionItems")}, 'model', ${field("notes", alias, "model")}, 'source', ${alias}.${n("source")}, 'createdBy', ${field("notes", alias, "createdBy")}, 'createdAt', ${field("notes", alias, "createdAt")}, 'updatedAt', ${field("notes", alias, "updatedAt")})`;

  const engagementVisible = (column: string): string =>
    `exists (select 1 from ${t("engagements")} ex where ex.${e("id")} = ${column})`;

  const recordingPayload = (recording: string): string =>
    `'recordingId', ${recording}`;

  const enqueue = ctx.installed("queue")
    ? `
  ${ctx.enqueue(TRANSCRIBE_QUEUE, "jsonb_build_object('recordingId', v_recording)", "'engagements.transcribe:' || v_recording::text")}`
    : "";

  const tables = ctx.manages
    ? `
-- Recordings of calls and meetings: an ai-files file on an engagement,
-- waiting for its transcript until a transcriber saves one.
create table if not exists ${t("recordings")} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${ctx.idType} not null,
  ${r("engagement")} uuid not null references ${t("engagements")} (${e("id")}) on delete cascade,
  ${r("file")} uuid not null references ${fileTable} (${f("id")}) on delete cascade,
  ${r("filename")} text not null,
  ${r("mediaType")} text not null,
  ${r("status")} text not null default 'pending' check (${r("status")} in ('pending', 'transcribed', 'failed')),${optional("recordings", "language", (x) => `${x} text`)}${optional("recordings", "durationSeconds", (x) => `${x} integer check (${x} >= 0)`)}${optional("recordings", "error", (x) => `${x} text`)}${optional("recordings", "model", (x) => `${x} text`)}${optional("recordings", "createdBy", (x) => `${x} uuid`)}
  ${r("createdAt")} timestamptz not null default now(),${optional("recordings", "transcribedAt", (x) => `${x} timestamptz`)}
  unique (${r("engagement")}, ${r("file")})
);${key("recordings", "file_key", `${r("engagement")}, ${r("file")}`)}
create index if not exists ${ctx.naming.rename("engagement_recordings_file_idx")} on ${t("recordings")} (${r("file")});
create index if not exists ${ctx.naming.rename("engagement_recordings_pending_idx")} on ${t("recordings")} (${r("createdAt")}) where ${r("status")} = 'pending';
${lockTable(t("recordings"), { read: true })}
drop policy if exists ${ctx.tableName("recordings").name}_read on ${t("recordings")};
create policy ${ctx.tableName("recordings").name}_read on ${t("recordings")} for select to authenticated
using (${engagementVisible(r("engagement"))});

-- A transcript, one row per speaker turn, offsets in milliseconds from the
-- start of the recording.
create table if not exists ${t("segments")} (
  ${s("recording")} uuid not null references ${t("recordings")} (${r("id")}) on delete cascade,
  ${s("tenant")} ${ctx.idType} not null,
  ${s("position")} integer not null check (${s("position")} >= 1),${optional("segments", "speaker", (x) => `${x} text`)}${optional("segments", "speakerUser", (x) => `${x} uuid`)}
  ${s("startsMs")} integer not null check (${s("startsMs")} >= 0),
  ${s("endsMs")} integer not null,
  ${s("text")} text not null,${optional("segments", "confidence", (x) => `${x} real check (${x} between 0 and 1)`)}
  primary key (${s("recording")}, ${s("position")}),
  check (${s("endsMs")} >= ${s("startsMs")})
);
${lockTable(t("segments"), { read: true })}
drop policy if exists ${ctx.tableName("segments").name}_read on ${t("segments")};
create policy ${ctx.tableName("segments").name}_read on ${t("segments")} for select to authenticated
using (exists (select 1 from ${t("recordings")} rx where rx.${r("id")} = ${s("recording")}));

-- Notes on an engagement: a summary and action items, written by an AI
-- note taker or a member. One row per engagement; saving replaces it.
create table if not exists ${t("notes")} (
  ${n("engagement")} uuid primary key references ${t("engagements")} (${e("id")}) on delete cascade,
  ${n("tenant")} ${ctx.idType} not null,
  ${n("summary")} text not null check (length(${n("summary")}) between 1 and 20000),
  ${n("actionItems")} jsonb not null default '[]' check (jsonb_typeof(${n("actionItems")}) = 'array'),${optional("notes", "model", (x) => `${x} text`)}
  ${n("source")} text not null default 'ai' check (${n("source")} in ('ai', 'member'))${[
    "createdBy",
    "createdAt",
    "updatedAt",
  ]
    .filter((column) => ctx.has("notes", column))
    .map(
      (column) =>
        `,\n  ${n(column)} ${column === "createdBy" ? "uuid" : "timestamptz not null default now()"}`,
    )
    .join("")}
);${key("notes", "engagement_key", n("engagement"))}
${lockTable(t("notes"), { read: true })}
drop policy if exists ${ctx.tableName("notes").name}_read on ${t("notes")};
create policy ${ctx.tableName("notes").name}_read on ${t("notes")} for select to authenticated
using (${engagementVisible(n("engagement"))});
`
    : "";

  return `${tables}
-- Attaches a ready ai-files file of the engagement's tenant as a recording.
-- The author, the owner and engagements.manage may attach; the file must be
-- the caller's own unless they manage engagements. With the jobs block a
-- transcription job goes on the ${TRANSCRIBE_QUEUE} queue.
create or replace function ${fn("attach_engagement_recording")}(engagement uuid, file uuid, language text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_type text;
  v_recording uuid;
  v_subjects jsonb;
  v_first jsonb;
begin
  select x.${e("tenant")}, x.${e("type")} into v_tenant, v_type
  from ${t("engagements")} x where x.${e("id")} = attach_engagement_recording.engagement and ${editable("x")};
  if v_tenant is null then
    ${fail("ENGAGEMENT_NOT_FOUND", "no such engagement you can edit", "P0002")}
  end if;
  if not exists (
    select 1 from ${fileTable} fx
    where fx.${f("id")} = attach_engagement_recording.file
      and fx.${f("tenant")}::text = v_tenant::text
      and fx.${f("status")} = 'ready'
      and (auth.role() = 'service_role' or fx.${f("owner")} = auth.uid() or ${ctx.scope.can("v_tenant", manage)})
  ) then
    ${fail("AI_FILE_NOT_FOUND", "no such ready file in this organization", "P0002")}
  end if;
  insert into ${t("recordings")} (${attached.map(([column]) => r(column)).join(", ")})
  select ${attached.map(([, value]) => value).join(", ")}
  from ${fileTable} fx where fx.${f("id")} = attach_engagement_recording.file
  on conflict (${r("engagement")}, ${r("file")}) do nothing
  returning ${r("id")} into v_recording;
  if v_recording is null then
    ${fail("ENGAGEMENT_RECORDING_EXISTS", "the file is already a recording of this engagement", "23505")}
  end if;
  ${loadSubjects("attach_engagement_recording.engagement")}
  ${record("engagement.recorded", "attach_engagement_recording.engagement", "v_type", "v_tenant", recordingPayload("v_recording"))}${enqueue}
  return ${oneRecording("v_recording")};
end;
$$;
${userGrant(`${fn("attach_engagement_recording")}(uuid, uuid, text)`)}

-- An engagement's recordings, oldest first, as the caller may read them.
create or replace function ${fn("engagement_recordings")}(engagement uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${recordingJson("rx")} order by rx.${r("createdAt")}, rx.${r("id")}), '[]'::jsonb)
  from ${t("recordings")} rx
  where rx.${r("engagement")} = engagement_recordings.engagement
$$;
${userGrant(`${fn("engagement_recordings")}(uuid)`)}

-- One recording, for the transcription job; null when the caller can't read it.
create or replace function ${fn("get_engagement_recording")}(recording uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${recordingJson("rx")}
  from ${t("recordings")} rx
  where rx.${r("id")} = get_engagement_recording.recording
$$;
${userGrant(`${fn("get_engagement_recording")}(uuid)`)}

-- A transcript in order, after position after (0 for the start).
create or replace function ${fn("engagement_transcript")}(recording uuid, after integer, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.position), '[]'::jsonb)
  from (
    select ${segmentJson("sx")} as value, sx.${s("position")} as position
    from ${t("segments")} sx
    where sx.${s("recording")} = engagement_transcript.recording
      and sx.${s("position")} > coalesce(engagement_transcript.after, 0)
    order by sx.${s("position")}
    limit ${pageSize("engagement_transcript.page_size", 500, 5000)}
  ) p
$$;
${userGrant(`${fn("engagement_transcript")}(uuid, integer, integer)`)}

-- Replaces a recording's transcript: segments is [{ speaker, speakerUserId,
-- startMs, endMs, text, confidence }] in order, attrs { language,
-- durationSeconds, model }. The service role (a transcription job) and
-- whoever may edit the engagement may save one.
create or replace function ${fn("save_engagement_transcript")}(recording uuid, segments jsonb, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_recording uuid := save_engagement_transcript.recording;
  v_engagement uuid;
  v_tenant ${ctx.idType};
  v_type text;
  v_item jsonb;
  v_position integer;
  v_subjects jsonb;
  v_first jsonb;
begin
  select rx.${r("engagement")}, rx.${r("tenant")}, x.${e("type")} into v_engagement, v_tenant, v_type
  from ${t("recordings")} rx
  join ${t("engagements")} x on x.${e("id")} = rx.${r("engagement")}
  where rx.${r("id")} = v_recording and ${editable("x")}
  for update of rx;
  if v_engagement is null then
    ${fail("ENGAGEMENT_RECORDING_NOT_FOUND", "no such recording you can edit", "P0002")}
  end if;
  if jsonb_typeof(save_engagement_transcript.segments) is distinct from 'array'
    or jsonb_array_length(save_engagement_transcript.segments) > ${MAX_SEGMENTS} then
    ${fail("ENGAGEMENT_TRANSCRIPT_INVALID", `segments must be a list of at most ${MAX_SEGMENTS} { startMs, endMs, text }`, "22023")}
  end if;
  for v_item, v_position in select value, ordinality from jsonb_array_elements(save_engagement_transcript.segments) with ordinality loop
    if jsonb_typeof(v_item) is distinct from 'object'
      or jsonb_typeof(v_item -> 'text') is distinct from 'string'
      or jsonb_typeof(v_item -> 'startMs') is distinct from 'number'
      or jsonb_typeof(v_item -> 'endMs') is distinct from 'number'
      or (v_item ->> 'startMs')::numeric < 0
      or (v_item ->> 'endMs')::numeric < (v_item ->> 'startMs')::numeric
      or jsonb_typeof(coalesce(v_item -> 'confidence', 'null')) not in ('number', 'null') then
      raise exception 'segment % needs startMs <= endMs and a text', v_position using errcode = '22023', hint = 'ENGAGEMENT_TRANSCRIPT_INVALID';
    end if;
  end loop;
  delete from ${t("segments")} sx where sx.${s("recording")} = v_recording;
  insert into ${t("segments")} (${segmented.map(([column]) => s(column)).join(", ")})
  select ${segmented.map(([, value]) => value).join(", ")}
  from jsonb_array_elements(save_engagement_transcript.segments) with ordinality i;
  update ${t("recordings")} rx set
    ${r("status")} = 'transcribed'${set("recordings", "error", "null")}${set("recordings", "language", `coalesce(nullif(save_engagement_transcript.attrs ->> 'language', ''), ${field("recordings", "rx", "language")})`)}${set("recordings", "durationSeconds", `coalesce((save_engagement_transcript.attrs ->> 'durationSeconds')::integer, ${field("recordings", "rx", "durationSeconds")})`)}${set("recordings", "model", `coalesce(nullif(save_engagement_transcript.attrs ->> 'model', ''), ${field("recordings", "rx", "model")})`)}${set("recordings", "transcribedAt", "now()")}
  where rx.${r("id")} = v_recording;
  ${loadSubjects("v_engagement")}
  ${record("engagement.transcribed", "v_engagement", "v_type", "v_tenant", recordingPayload("v_recording"), "'engagement.transcribed:' || v_recording::text || ':' || md5(save_engagement_transcript.segments::text)")}
  return ${oneRecording("v_recording")};
end;
$$;
${userGrant(`${fn("save_engagement_transcript")}(uuid, jsonb, jsonb)`)}

-- Marks a recording failed with the transcriber's error. Service only.
create or replace function ${fn("fail_engagement_recording")}(recording uuid, error text)
returns boolean
language sql
security definer
set search_path = ''
as $$
  with failed as (
    update ${t("recordings")} rx set ${r("status")} = 'failed'${ctx.has("recordings", "error") ? `, ${r("error")} = left(fail_engagement_recording.error, 2000)` : ""}
    where rx.${r("id")} = fail_engagement_recording.recording and rx.${r("status")} <> 'transcribed'
    returning 1
  )
  select exists (select 1 from failed)
$$;
${serviceGrant(`${fn("fail_engagement_recording")}(uuid, text)`)}

-- Recordings that wait for a transcript, oldest first, for a drain without
-- the jobs block. Service only.
create or replace function ${fn("pending_engagement_recordings")}(batch integer)
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(p.id order by p.at), '{}')
  from (
    select rx.${r("id")} as id, rx.${r("createdAt")} as at
    from ${t("recordings")} rx
    where rx.${r("status")} = 'pending'
    order by rx.${r("createdAt")}
    limit ${pageSize("pending_engagement_recordings.batch", 20, 200)}
  ) p
$$;
${serviceGrant(`${fn("pending_engagement_recordings")}(integer)`)}

-- Saves an engagement's notes: notes { summary, actionItems: [{ text,
-- ownerId, dueAt }], model, source }. Replaces earlier notes.
create or replace function ${fn("save_engagement_notes")}(engagement uuid, notes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_type text;
  v_summary text := nullif(trim(save_engagement_notes.notes ->> 'summary'), '');
  v_items jsonb := coalesce(save_engagement_notes.notes -> 'actionItems', '[]'::jsonb);
  v_subjects jsonb;
  v_first jsonb;
begin
  select x.${e("tenant")}, x.${e("type")} into v_tenant, v_type
  from ${t("engagements")} x where x.${e("id")} = save_engagement_notes.engagement and ${editable("x")};
  if v_tenant is null then
    ${fail("ENGAGEMENT_NOT_FOUND", "no such engagement you can edit", "P0002")}
  end if;
  if v_summary is null or length(v_summary) > 20000 then
    ${fail("ENGAGEMENT_NOTES_INVALID", "notes need a summary of at most 20000 characters", "22023")}
  end if;
  if jsonb_typeof(v_items) <> 'array' or exists (
    select 1 from jsonb_array_elements(v_items) i
    where jsonb_typeof(i.value) <> 'object' or jsonb_typeof(i.value -> 'text') is distinct from 'string'
  ) then
    ${fail("ENGAGEMENT_NOTES_INVALID", "actionItems must be a list of { text }", "22023")}
  end if;
  insert into ${t("notes")} (${noted.map(([column]) => n(column)).join(", ")})
  values (${noted.map(([, value]) => value).join(", ")})
  on conflict (${n("engagement")}) do update set
    ${n("summary")} = excluded.${n("summary")}, ${n("actionItems")} = excluded.${n("actionItems")},
    ${[
      ...(ctx.has("notes", "model")
        ? [`${n("model")} = excluded.${n("model")}`]
        : []),
      `${n("source")} = excluded.${n("source")}`,
      ...(ctx.has("notes", "updatedAt") ? [`${n("updatedAt")} = now()`] : []),
    ].join(", ")};
  ${loadSubjects("save_engagement_notes.engagement")}
  ${record("engagement.summarized", "save_engagement_notes.engagement", "v_type", "v_tenant", "", "'engagement.summarized:' || save_engagement_notes.engagement::text || ':' || md5(save_engagement_notes.notes::text)")}
  return (select ${notesJson("nx")} from ${t("notes")} nx where nx.${n("engagement")} = save_engagement_notes.engagement);
end;
$$;
${userGrant(`${fn("save_engagement_notes")}(uuid, jsonb)`)}

-- An engagement with the transcripts of its recordings in order, for a note
-- taker: { engagement, segments: [{ recordingId, position, ... }] }. Null
-- when the caller can't read it.
create or replace function ${fn("engagement_with_transcripts")}(engagement uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'engagement', ${row("x")},
    'segments', coalesce((
      select jsonb_agg(${segmentJson("sx")} || jsonb_build_object('recordingId', rx.${r("id")}) order by rx.${r("createdAt")}, rx.${r("id")}, sx.${s("position")})
      from ${t("recordings")} rx
      join ${t("segments")} sx on sx.${s("recording")} = rx.${r("id")}
      where rx.${r("engagement")} = x.${e("id")}
    ), '[]'::jsonb)
  )
  from ${t("engagements")} x
  where x.${e("id")} = engagement_with_transcripts.engagement
$$;
${userGrant(`${fn("engagement_with_transcripts")}(uuid)`)}

-- An engagement's notes, or null.
create or replace function ${fn("engagement_notes")}(engagement uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${notesJson("nx")} from ${t("notes")} nx where nx.${n("engagement")} = engagement_notes.engagement
$$;
${userGrant(`${fn("engagement_notes")}(uuid)`)}
`;
}

/** The functions `options.recordings` adds. */
export function recordingsContract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "attach_engagement_recording",
      args: ["uuid", "uuid", "text"],
      returns: "jsonb",
    },
    { name: "engagement_recordings", args: ["uuid"], returns: "jsonb" },
    { name: "get_engagement_recording", args: ["uuid"], returns: "jsonb" },
    {
      name: "engagement_transcript",
      args: ["uuid", "integer", "integer"],
      returns: "jsonb",
    },
    {
      name: "save_engagement_transcript",
      args: ["uuid", "jsonb", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "fail_engagement_recording",
      args: ["uuid", "text"],
      returns: "boolean",
    },
    {
      name: "pending_engagement_recordings",
      args: ["integer"],
      returns: "uuid[]",
    },
    {
      name: "save_engagement_notes",
      args: ["uuid", "jsonb"],
      returns: "jsonb",
    },
    { name: "engagement_notes", args: ["uuid"], returns: "jsonb" },
    { name: "engagement_with_transcripts", args: ["uuid"], returns: "jsonb" },
  ];
}
