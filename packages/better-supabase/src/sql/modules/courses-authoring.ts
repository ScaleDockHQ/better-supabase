import type { BlockSqlContext } from "../context.ts";

import { RANK_KEY_PATTERN, rankAfter } from "../rank-sql.ts";
import { fail, userGrant, writeExtraColumns } from "../shared.ts";
import { COURSE_KEYS, courseSql } from "./courses-sql.ts";

function quizForm(ctx: BlockSqlContext, lesson: string): string {
  if (!ctx.installed("forms")) {
    return "";
  }

  const forms = ctx.of("forms");

  return `
  if ${lesson}.form is not null and not exists (select 1 from ${forms.table("forms")} f where f.${forms.col("forms", "id")} = ${lesson}.form and f.${forms.col("forms", "tenant")} = ${lesson}.tenant) then
    ${fail("COURSE_INVALID", "formId: pass a form of this organization", "22023")}
  end if;`;
}

/** The courses module's authoring functions and the helpers they sync with. */
export function courseAuthoringFunctions(ctx: BlockSqlContext): string {
  const q = courseSql(ctx);
  const { fn, c, m, l, e, field } = q;
  const idType = ctx.idType;
  const extras = ctx.extraColumns("courses", COURSE_KEYS);

  const courseRecord = (type: string, row: string, summary: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${row}.${c("tenant")}, 'id', ${row}.${c("id")}, 'key', ${row}.${c("key")}, 'status', ${row}.${c("status")})`,
      subject: `'courses/' || ${row}.${c("id")}::text`,
      tenant: `${row}.${c("tenant")}`,
      audit: {
        category: "data",
        targetType: "course",
        recordId: `${row}.${c("id")}::text`,
        targetLabel: `${row}.${c("title")}`,
        summary: `'${summary}'`,
      },
    });

  const certificateRecord = (
    type: string,
    row: string,
    summary: string,
    extra = "",
  ): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${row}.${q.k("tenant")}, 'id', ${row}.${q.k("id")}, 'courseId', ${row}.${q.k("course")}, 'userId', ${row}.${q.k("user")}, 'enrollmentId', ${row}.${q.k("enrollment")}${extra})`,
      subject: `'course-certificates/' || ${row}.${q.k("id")}::text`,
      tenant: `${row}.${q.k("tenant")}`,
      audit: {
        category: "data",
        targetType: "course_certificate",
        recordId: `${row}.${q.k("id")}::text`,
        targetLabel: `${row}.${q.k("code")}`,
        summary: `'${summary}'`,
      },
    });

  const moduleJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${m("id")}, 'courseId', ${row}.${m("course")}, 'title', ${row}.${m("title")}, 'rank', ${row}.${m("rank")}, 'createdAt', ${field("modules", row, "createdAt")}, 'updatedAt', ${field("modules", row, "updatedAt")})`;

  const lessonJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${l("id")}, 'courseId', ${row}.${l("course")}, 'moduleId', ${row}.${l("module")}, 'title', ${row}.${l("title")}, 'kind', ${row}.${l("kind")}, 'body', ${field("lessons", row, "body")}, 'mediaUrl', ${field("lessons", row, "mediaUrl")}, 'formId', ${row}.${l("form")}, 'required', ${row}.${l("required")}, 'minutes', ${field("lessons", row, "minutes")}, 'rank', ${row}.${l("rank")}, 'createdAt', ${field("lessons", row, "createdAt")}, 'updatedAt', ${field("lessons", row, "updatedAt")})`;

  /** `, <column> = now()` when `table` has its updatedAt column. */
  const touched = (table: string): string =>
    ctx.has(table, "updatedAt")
      ? `, ${ctx.col(table, "updatedAt")} = now()`
      : "";

  const expires = ctx.has("certificates", "expiresAt");

  const touchCourse = ctx.has("courses", "updatedAt")
    ? `\n  update ${q.courses} x set ${c("updatedAt")} = now() where x.${c("id")} = v_course.${c("id")};`
    : "";

  const courseInsert = (
    [
      ["tenant", "save_course.tenant"],
      ["key", "v_key"],
      ["title", "v_title"],
      ["summary", "v_summary"],
      ["status", ctx.cast("courses", "status", "v_status")],
      ["certificate", "v_certificate"],
      ["validForMonths", "v_valid_for"],
      ["createdBy", "auth.uid()"],
    ] as const
  ).filter(([column]) => ctx.has("courses", column));

  const lessonWrite = (
    [
      ["module", "v_new.module"],
      ["title", "v_new.title"],
      ["kind", ctx.cast("lessons", "kind", "v_new.kind")],
      ["body", "v_new.body"],
      ["mediaUrl", "v_new.media"],
      ["form", "v_new.form"],
      ["required", "v_new.required"],
      ["minutes", "v_new.minutes"],
    ] as const
  ).filter(([column]) => ctx.has("lessons", column));

  /** A lesson value from the input, else `old` when the table has `column`. */
  const kept = (column: string, value: string, old: string): string =>
    ctx.has("lessons", column)
      ? `case when save_course_lesson.lesson ? '${value}' then ${old} else v_old.${l(column)} end`
      : "null";

  const manageCourse = (
    row: string,
  ): string => `if not ${q.allowed(`${row}.${c("tenant")}`, q.manage)} then
    ${q.forbidden("not allowed to manage courses")}
  end if;`;

  const rankOf = (json: string, fallback: string): string =>
    `coalesce(nullif(${json} ->> 'rank', ''), ${fallback})`;

  return `-- A course as JSON, with its extra columns under fields.
create or replace function ${fn("course_json")}(course_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select ${q.courseJson("x")} from ${q.courses} x where x.${c("id")} = course_json.course_id
$$;
revoke execute on function ${fn("course_json")}(uuid) from public, anon, authenticated;

-- The course's required lessons in module rank, then lesson rank order: the
-- steps of its enrollment program.
create or replace function ${fn("course_steps")}(course_id uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(y.${l("id")}::text order by z.${m("rank")}, z.${m("id")}, y.${l("rank")}, y.${l("id")}), '{}')
  from ${q.lessons} y join ${q.modules} z on z.${m("id")} = y.${l("module")}
  where y.${l("course")} = course_steps.course_id and y.${l("required")}
$$;
revoke execute on function ${fn("course_steps")}(uuid) from public, anon, authenticated;

-- After an enrollment's progress changed from status was: records
-- course.completed when it just completed, and issues the certificate when
-- the course gives one.
create or replace function ${fn("course_finish")}(enrollment_id uuid, was text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_enrollment record;
  v_certificate ${q.certificates};
begin
  select x.${e("id")} as id, x.${e("tenant")} as tenant, x.${e("status")} as status, x.${e("user")} as learner, y.${c("id")} as course, ${field("courses", "y", "certificate", "true")} as certifies, ${field("courses", "y", "validForMonths")}::integer as valid_for
  into v_enrollment
  from ${q.enrollments} x join ${q.courses} y on ${q.program(`y.${c("id")}`)} = x.${e("program")}
  where x.${e("id")} = course_finish.enrollment_id;
  if v_enrollment.id is null or v_enrollment.status <> 'completed' then
    return;
  end if;
  if course_finish.was is distinct from 'completed' then
    ${q.learnerRecord("course.completed", "completed a course")}
  end if;
  if v_enrollment.certifies then
    insert into ${q.certificates} (${q.k("tenant")}, ${q.k("course")}, ${q.k("enrollment")}, ${q.k("user")}, ${q.k("code")}${expires ? `, ${q.k("expiresAt")}` : ""})
    values (v_enrollment.tenant, v_enrollment.course, v_enrollment.id, v_enrollment.learner, encode(extensions.gen_random_bytes(16), 'hex')${expires ? ", now() + make_interval(months => v_enrollment.valid_for)" : ""})
    on conflict ${q.certificateTarget} do nothing
    returning * into v_certificate;
    if v_certificate.${q.k("id")} is not null then
      ${certificateRecord("course_certificate.issued", "v_certificate", "issued a course certificate", `, 'expiresAt', ${field("certificates", "v_certificate", "expiresAt")}`)}
    end if;
  end if;
end;
$$;
revoke execute on function ${fn("course_finish")}(uuid, text) from public, anon, authenticated;

-- Gives every live enrollment in the course its current required lessons and
-- finishes the ones that complete with them.
create or replace function ${fn("course_sync")}(course_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_course ${q.courses};
  v_steps text[];
  v_row record;
begin
  select * into v_course from ${q.courses} x where x.${c("id")} = course_sync.course_id;
  if v_course.${c("id")} is null then
    return;
  end if;
  v_steps := ${fn("course_steps")}(v_course.${c("id")});
  for v_row in
    select x.${e("id")} as id, x.${e("subjectId")} as subject, x.${e("status")} as status from ${q.enrollments} x
    where x.${e("tenant")} = v_course.${c("tenant")} and x.${e("program")} = ${q.program(`v_course.${c("id")}`)}
      and x.${e("status")} <> 'cancelled' and x.${e("steps")} is distinct from v_steps
  loop
    perform ${fn("enrollment_ensure")}(v_course.${c("tenant")}, ${q.program(`v_course.${c("id")}`)}, null, v_steps, 'user', v_row.subject, auth.uid());
    perform ${fn("course_finish")}(v_row.id, v_row.status);
  end loop;
end;
$$;
revoke execute on function ${fn("course_sync")}(uuid) from public, anon, authenticated;

-- Creates or changes a course. course is { id?, key, title, summary, status,
-- certificate, validForMonths, fields }; keys left out keep their value.
-- validForMonths is how long a certificate stays valid; null never expires.
create or replace function ${fn("save_course")}(tenant ${idType}, course jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old ${q.courses};
  v_row ${q.courses};
  v_key text;
  v_title text;
  v_summary text;
  v_status text;
  v_certificate boolean;
  v_valid_for integer;
begin
  if not ${q.allowed("save_course.tenant", q.manage)} then
    ${q.forbidden("not allowed to manage courses")}
  end if;
  if save_course.course is null or jsonb_typeof(save_course.course) <> 'object' then
    ${q.invalid("course must be an object")}
  end if;
  v_id := nullif(save_course.course ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from ${q.courses} x where x.${c("id")} = v_id and x.${c("tenant")} = save_course.tenant for update;
    if v_old.${c("id")} is null then
      ${q.courseMissing}
    end if;
  end if;
  v_key := coalesce(save_course.course ->> 'key', v_old.${c("key")});
  v_title := trim(coalesce(save_course.course ->> 'title', v_old.${c("title")}));
  v_summary := case when save_course.course ? 'summary' then nullif(trim(save_course.course ->> 'summary'), '') else ${field("courses", "v_old", "summary")} end;
  v_status := coalesce(save_course.course ->> 'status', v_old.${c("status")}, 'draft');
  v_certificate := case when save_course.course ? 'certificate' then (save_course.course ->> 'certificate')::boolean else coalesce(${field("courses", "v_old", "certificate")}, true) end;
  v_valid_for := ${field("courses", "v_old", "validForMonths")};
  if save_course.course ? 'validForMonths' then
    if jsonb_typeof(save_course.course -> 'validForMonths') = 'null' then
      v_valid_for := null;
    elsif jsonb_typeof(save_course.course -> 'validForMonths') <> 'number'
      or (save_course.course ->> 'validForMonths')::numeric % 1 <> 0
      or (save_course.course ->> 'validForMonths')::numeric not between 1 and 240 then
      ${q.invalid("validForMonths must be a whole number of months from 1 to 240, or null")}
    else
      v_valid_for := (save_course.course ->> 'validForMonths')::integer;
    end if;
  end if;
  if v_key is null or v_key !~ '^[a-z][a-z0-9-]{0,62}$' then
    ${q.invalid('key: use lowercase letters, digits or "-", starting with a letter')}
  end if;
  if v_title is null or length(v_title) not between 1 and 200 then
    ${q.invalid("title must be 1 to 200 characters")}
  end if;
  if length(v_summary) > 2000 then
    ${q.invalid("summary must be at most 2000 characters")}
  end if;
  if v_status not in ('draft', 'published', 'archived') then
    ${q.invalid("status must be draft, published or archived")}
  end if;
  if v_old.${c("id")} is null then
    insert into ${q.courses} (${courseInsert.map(([column]) => c(column)).join(", ")})
    values (${courseInsert.map(([, value]) => value).join(", ")})
    on conflict (${c("tenant")}, ${c("key")}) do nothing
    returning * into v_row;
    if v_row.${c("id")} is null then
      ${fail("COURSE_EXISTS", "a course with this key already exists", "23505")}
    end if;
  else
    begin
      update ${q.courses} x
      set ${c("key")} = v_key, ${c("title")} = v_title,${ctx.has("courses", "summary") ? ` ${c("summary")} = v_summary,` : ""} ${c("status")} = ${ctx.cast("courses", "status", "v_status")}${ctx.has("courses", "certificate") ? `,\n        ${c("certificate")} = v_certificate` : ""}${ctx.has("courses", "validForMonths") ? `,\n        ${c("validForMonths")} = v_valid_for` : ""}${touched("courses")}
      where x.${c("id")} = v_old.${c("id")}
      returning * into v_row;
    exception when unique_violation then
      ${fail("COURSE_EXISTS", "a course with this key already exists", "23505")}
    end;
  end if;${writeExtraColumns(q.courses, extras, "(save_course.course -> 'fields')", `x.${c("id")} = v_row.${c("id")}`, "v_row")}
  ${courseRecord("course.saved", "v_row", "saved a course")}
  return ${fn("course_json")}(v_row.${c("id")});
end;
$$;
${userGrant(`${fn("save_course")}(${idType}, jsonb)`)}

-- Deletes a course with its modules, lessons, enrollments, progress and
-- certificates; false when it was already gone.
create or replace function ${fn("delete_course")}(course_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${q.courses};
begin
  select * into v_row from ${q.courses} x where x.${c("id")} = delete_course.course_id for update;
  if v_row.${c("id")} is null then
    return false;
  end if;
  ${manageCourse("v_row")}
  delete from ${q.enrollments} x where x.${e("tenant")} = v_row.${c("tenant")} and x.${e("program")} = ${q.program(`v_row.${c("id")}`)};
  delete from ${q.courses} x where x.${c("id")} = v_row.${c("id")};
  ${courseRecord("course.deleted", "v_row", "deleted a course")}
  return true;
end;
$$;
${userGrant(`${fn("delete_course")}(uuid)`)}

-- The organization's courses by title. Without courses.manage only the
-- published ones.
create or replace function ${fn("list_courses")}(tenant ${idType}, status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_manage boolean := ${q.allowed("list_courses.tenant", q.manage)};
begin
  if not (v_manage or ${q.allowed("list_courses.tenant", q.read)}) then
    ${q.forbidden("not allowed to read courses")}
  end if;
  if list_courses.status is not null and list_courses.status not in ('draft', 'published', 'archived') then
    ${q.invalid("status must be draft, published or archived")}
  end if;
  return coalesce((
    select jsonb_agg(${q.courseJson("x")} order by x.${c("title")}, x.${c("id")})
    from ${q.courses} x
    where x.${c("tenant")} = list_courses.tenant
      and (v_manage or x.${c("status")} = 'published')
      and (list_courses.status is null or x.${c("status")} = ${ctx.cast("courses", "status", "list_courses.status")})
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_courses")}(${idType}, text)`)}

-- Creates or changes a module of a course. module is { id?, title, rank? };
-- a new module without a rank goes last.
create or replace function ${fn("save_course_module")}(course_id uuid, module jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_course ${q.courses};
  v_old ${q.modules};
  v_row ${q.modules};
  v_id uuid;
  v_title text;
  v_last text;
  v_rank text;
begin
  select * into v_course from ${q.courses} x where x.${c("id")} = save_course_module.course_id;
  if v_course.${c("id")} is null then
    ${q.courseMissing}
  end if;
  ${manageCourse("v_course")}
  if save_course_module.module is null or jsonb_typeof(save_course_module.module) <> 'object' then
    ${q.invalid("module must be an object")}
  end if;
  v_id := nullif(save_course_module.module ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from ${q.modules} x where x.${m("id")} = v_id and x.${m("course")} = v_course.${c("id")} for update;
    if v_old.${m("id")} is null then
      ${fail("COURSE_MODULE_NOT_FOUND", "course module not found", "P0002")}
    end if;
  end if;
  v_title := trim(coalesce(save_course_module.module ->> 'title', v_old.${m("title")}));
  if v_title is null or length(v_title) not between 1 and 200 then
    ${q.invalid("title must be 1 to 200 characters")}
  end if;
  select max(x.${m("rank")}) into v_last from ${q.modules} x where x.${m("course")} = v_course.${c("id")};
  v_rank := ${rankOf("save_course_module.module", `coalesce(v_old.${m("rank")}, ${rankAfter("v_last")})`)};
  if v_rank !~ ${RANK_KEY_PATTERN} then
    ${q.invalid("rank must be a rank key")}
  end if;
  if v_old.${m("id")} is null then
    insert into ${q.modules} (${m("tenant")}, ${m("course")}, ${m("title")}, ${m("rank")})
    values (v_course.${c("tenant")}, v_course.${c("id")}, v_title, v_rank)
    returning * into v_row;
  else
    update ${q.modules} x set ${m("title")} = v_title, ${m("rank")} = v_rank${touched("modules")}
    where x.${m("id")} = v_old.${m("id")}
    returning * into v_row;
  end if;${touchCourse}
  perform ${fn("course_sync")}(v_course.${c("id")});
  return ${moduleJson("v_row")};
end;
$$;
${userGrant(`${fn("save_course_module")}(uuid, jsonb)`)}

-- Deletes a module with its lessons; false when it was already gone.
create or replace function ${fn("delete_course_module")}(module_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${q.modules};
  v_course ${q.courses};
begin
  select * into v_row from ${q.modules} x where x.${m("id")} = delete_course_module.module_id for update;
  if v_row.${m("id")} is null then
    return false;
  end if;
  select * into v_course from ${q.courses} x where x.${c("id")} = v_row.${m("course")};
  ${manageCourse("v_course")}
  delete from ${q.modules} x where x.${m("id")} = v_row.${m("id")};
  perform ${fn("course_sync")}(v_course.${c("id")});
  return true;
end;
$$;
${userGrant(`${fn("delete_course_module")}(uuid)`)}

-- Creates or changes a lesson. lesson is { id?, moduleId, title, kind, body,
-- mediaUrl, formId, required, minutes, rank? }; keys left out keep their
-- value, and a lesson without a rank goes last in its module. A quiz lesson
-- names the form that grades it.
create or replace function ${fn("save_course_lesson")}(course_id uuid, lesson jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_course ${q.courses};
  v_old ${q.lessons};
  v_row ${q.lessons};
  v_new record;
  v_id uuid;
  v_last text;
begin
  select * into v_course from ${q.courses} x where x.${c("id")} = save_course_lesson.course_id;
  if v_course.${c("id")} is null then
    ${q.courseMissing}
  end if;
  ${manageCourse("v_course")}
  if save_course_lesson.lesson is null or jsonb_typeof(save_course_lesson.lesson) <> 'object' then
    ${q.invalid("lesson must be an object")}
  end if;
  v_id := nullif(save_course_lesson.lesson ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from ${q.lessons} x where x.${l("id")} = v_id and x.${l("course")} = v_course.${c("id")} for update;
    if v_old.${l("id")} is null then
      ${q.lessonMissing}
    end if;
  end if;
  select
    v_course.${c("tenant")} as tenant,
    coalesce(nullif(save_course_lesson.lesson ->> 'moduleId', '')::uuid, v_old.${l("module")}) as module,
    trim(coalesce(save_course_lesson.lesson ->> 'title', v_old.${l("title")})) as title,
    coalesce(save_course_lesson.lesson ->> 'kind', v_old.${l("kind")}, 'content') as kind,
    ${kept("body", "body", "nullif(save_course_lesson.lesson -> 'body', 'null'::jsonb)")} as body,
    ${kept("mediaUrl", "mediaUrl", "nullif(save_course_lesson.lesson ->> 'mediaUrl', '')")} as media,
    case when save_course_lesson.lesson ? 'formId' then nullif(save_course_lesson.lesson ->> 'formId', '')::uuid else v_old.${l("form")} end as form,
    case when save_course_lesson.lesson ? 'required' then (save_course_lesson.lesson ->> 'required')::boolean else coalesce(v_old.${l("required")}, true) end as required,
    ${kept("minutes", "minutes", "(save_course_lesson.lesson ->> 'minutes')::integer")} as minutes
  into v_new;
  if v_new.module is null or not exists (select 1 from ${q.modules} x where x.${m("id")} = v_new.module and x.${m("course")} = v_course.${c("id")}) then
    ${q.invalid("moduleId: pass a module of this course")}
  end if;
  if v_new.title is null or length(v_new.title) not between 1 and 200 then
    ${q.invalid("title must be 1 to 200 characters")}
  end if;
  if v_new.kind not in ('content', 'video', 'quiz') then
    ${q.invalid("kind must be content, video or quiz")}
  end if;
  if (v_new.kind = 'quiz') <> (v_new.form is not null) then
    ${q.invalid("a quiz lesson needs a formId, and only a quiz lesson takes one")}
  end if;${
    ctx.installed("forms")
      ? ""
      : `
  if v_new.form is not null then
    ${fail("COURSE_QUIZ_UNAVAILABLE", "quiz lessons need the forms block", "55000")}
  end if;`
  }${quizForm(ctx, "v_new")}
  if v_new.body is not null and octet_length(v_new.body::text) > 1000000 then
    ${q.invalid("body must be at most 1 MB")}
  end if;
  if v_new.media is not null and (v_new.media !~ '^https?://' or length(v_new.media) > 2000) then
    ${q.invalid("mediaUrl must be an http or https URL of at most 2000 characters")}
  end if;
  if v_new.minutes is not null and v_new.minutes not between 1 and 10000 then
    ${q.invalid("minutes must be from 1 to 10000")}
  end if;
  select max(x.${l("rank")}) into v_last from ${q.lessons} x where x.${l("module")} = v_new.module and x.${l("id")} is distinct from v_old.${l("id")};
  v_last := ${rankOf("save_course_lesson.lesson", `case when v_old.${l("module")} = v_new.module then v_old.${l("rank")} else ${rankAfter("v_last")} end`)};
  if v_last !~ ${RANK_KEY_PATTERN} then
    ${q.invalid("rank must be a rank key")}
  end if;
  if v_old.${l("id")} is null then
    insert into ${q.lessons} (${l("tenant")}, ${l("course")}, ${lessonWrite.map(([column]) => l(column)).join(", ")}, ${l("rank")})
    values (v_new.tenant, v_course.${c("id")}, ${lessonWrite.map(([, value]) => value).join(", ")}, v_last)
    returning * into v_row;
  else
    update ${q.lessons} x
    set ${lessonWrite.map(([column, value]) => `${l(column)} = ${value}`).join(", ")},
      ${l("rank")} = v_last${touched("lessons")}
    where x.${l("id")} = v_old.${l("id")}
    returning * into v_row;
  end if;${touchCourse}
  perform ${fn("course_sync")}(v_course.${c("id")});
  return ${lessonJson("v_row")};
end;
$$;
${userGrant(`${fn("save_course_lesson")}(uuid, jsonb)`)}

-- Deletes a lesson with its progress; false when it was already gone.
create or replace function ${fn("delete_course_lesson")}(lesson_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${q.lessons};
  v_course ${q.courses};
begin
  select * into v_row from ${q.lessons} x where x.${l("id")} = delete_course_lesson.lesson_id for update;
  if v_row.${l("id")} is null then
    return false;
  end if;
  select * into v_course from ${q.courses} x where x.${c("id")} = v_row.${l("course")};
  ${manageCourse("v_course")}
  delete from ${q.lessons} x where x.${l("id")} = v_row.${l("id")};
  perform ${fn("course_sync")}(v_course.${c("id")});
  return true;
end;
$$;
${userGrant(`${fn("delete_course_lesson")}(uuid)`)}

-- Revokes a certificate; false when it already was.
create or replace function ${fn("revoke_course_certificate")}(certificate_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${q.certificates};
begin
  select * into v_row from ${q.certificates} x where x.${q.k("id")} = revoke_course_certificate.certificate_id for update;
  if v_row.${q.k("id")} is null then
    ${fail("COURSE_CERTIFICATE_NOT_FOUND", "course certificate not found", "P0002")}
  end if;
  if not ${q.allowed(`v_row.${q.k("tenant")}`, q.manage)} then
    ${q.forbidden("not allowed to manage courses")}
  end if;
  if v_row.${q.k("revokedAt")} is not null then
    return false;
  end if;
  update ${q.certificates} x set ${q.k("revokedAt")} = now() where x.${q.k("id")} = v_row.${q.k("id")} returning * into v_row;
  ${certificateRecord("course_certificate.revoked", "v_row", "revoked a course certificate")}
  return true;
end;
$$;
${userGrant(`${fn("revoke_course_certificate")}(uuid)`)}
`;
}
