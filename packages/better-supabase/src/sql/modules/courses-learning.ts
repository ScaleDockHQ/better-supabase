import type { BlockSqlContext } from "../context.ts";

import { fail, pageSize, userGrant } from "../shared.ts";
import { courseSql } from "./courses-sql.ts";

const notEnrolled = fail(
  "COURSE_NOT_ENROLLED",
  "you are not enrolled in this course",
  "P0002",
);

/**
 * The quiz of lesson `row`: the grading form's current version without its
 * answer key, or null.
 */
function quizJson(ctx: BlockSqlContext, row: string, form: string): string {
  if (!ctx.installed("forms")) {
    return "null::jsonb";
  }

  const forms = ctx.of("forms");
  const f = (column: string): string => forms.col("forms", column);
  const v = (column: string): string => forms.col("versions", column);

  return `(select jsonb_build_object('formId', f.${f("id")}, 'title', f.${f("title")}, 'status', f.${f("status")}, 'versionId', v.${v("id")}, 'definition', v.${v("definition")}, 'schema', v.${v("schema")})
    from ${forms.table("forms")} f left join ${forms.table("versions")} v on v.${v("id")} = f.${f("currentVersion")}
    where f.${f("id")} = ${row}.${form})`;
}

/** `submit_course_quiz`, which needs the forms block. */
function quizSubmit(ctx: BlockSqlContext, learner: string): string {
  if (!ctx.installed("forms")) {
    return "";
  }

  const q = courseSql(ctx);
  const { fn, l, p, e } = q;
  const save = ctx.of("forms").fn("form_submission_save");

  const written = (
    [
      ["enrollment", `v_row.${e("id")}`],
      ["lesson", `v_lesson.${l("id")}`],
      ["tenant", `v_lesson.${l("tenant")}`],
      ["course", `v_lesson.${l("course")}`],
      ["user", "auth.uid()"],
      ["completedAt", "case when v_passes then now() end"],
      ["attempts", "1"],
      ["submission", "(v_submission ->> 'id')::uuid"],
      ["score", "(v_submission ->> 'score')::numeric"],
      ["maxScore", "(v_submission ->> 'maxScore')::numeric"],
      ["passed", "(v_submission ->> 'passed')::boolean"],
    ] as const
  ).filter(([column]) => ctx.has("progress", column));

  const graded = (["submission", "score", "maxScore", "passed"] as const)
    .filter((column) => ctx.has("progress", column))
    .map((column) => `, ${p(column)} = excluded.${p(column)}`)
    .join("");

  return `
-- Submits answers to a quiz lesson's form as the enrolled caller. The forms
-- block grades the submission in SQL; a passed one, or one without a pass
-- mark, completes the lesson. A later failed attempt keeps it complete.
create or replace function ${fn("submit_course_quiz")}(lesson_id uuid, answers jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
${learner}
  v_submission jsonb;
  v_passes boolean;
  v_before timestamptz;
begin
  select * into v_lesson from ${q.lessons} x where x.${l("id")} = submit_course_quiz.lesson_id;
  if v_lesson.${l("id")} is null then
    ${q.lessonMissing}
  end if;
  select * into v_row from ${q.enrollments} x
  where x.${e("tenant")} = v_lesson.${l("tenant")} and x.${e("program")} = ${q.program(`v_lesson.${l("course")}`)}
    and x.${e("subjectType")} = 'user' and x.${e("subjectId")} = auth.uid()::text and x.${e("status")} <> 'cancelled';
  if v_row.${e("id")} is null then
    ${notEnrolled}
  end if;
  if v_lesson.${l("kind")} <> 'quiz' then
    ${q.invalid("this lesson has no quiz")}
  end if;
  v_submission := ${save}(v_lesson.${l("form")}, submit_course_quiz.answers, 'course_lesson', v_lesson.${l("id")}::text, auth.uid(), 'member', false, null);
  v_passes := coalesce((v_submission ->> 'passed')::boolean, true);
  select x.${p("completedAt")} into v_before from ${q.progress} x
  where x.${p("enrollment")} = v_row.${e("id")} and x.${p("lesson")} = v_lesson.${l("id")};
  insert into ${q.progress} (${written.map(([column]) => p(column)).join(", ")})
  values (${written.map(([, value]) => value).join(", ")})
  on conflict ${q.progressTarget} do update
  set ${p("attempts")} = ${q.progress}.${p("attempts")} + 1${graded},
    ${p("completedAt")} = coalesce(${q.progress}.${p("completedAt")}, excluded.${p("completedAt")})${ctx.has("progress", "updatedAt") ? `, ${p("updatedAt")} = now()` : ""};
  if v_passes then
    perform ${fn("course_lesson_done")}(v_row.${e("id")}, v_lesson.${l("id")}, v_before is null);
  end if;
  return jsonb_build_object('submission', v_submission, 'passed', v_passes, 'progress', ${fn("course_learner_json")}(v_row.${e("id")}));
end;
$$;
${userGrant(`${fn("submit_course_quiz")}(uuid, jsonb)`)}
`;
}

/** The courses module's learner functions. */
export function courseLearningFunctions(ctx: BlockSqlContext): string {
  const q = courseSql(ctx);
  const { fn, c, m, l, p, k, e, field } = q;

  const touched = ctx.has("progress", "updatedAt")
    ? `, ${p("updatedAt")} = now()`
    : "";

  const learner = `  v_lesson ${q.lessons};
  v_row ${q.enrollments};`;

  // A course the caller can see: published to readers, any to managers, and
  // its own to an enrolled learner.
  const visible = (
    course: string,
  ): string => `(${q.allowed(`${course}.${c("tenant")}`, q.manage)}
    or (${course}.${c("status")} = 'published' and ${q.allowed(`${course}.${c("tenant")}`, q.read)})
    or exists (select 1 from ${q.enrollments} y where y.${e("tenant")} = ${course}.${c("tenant")} and y.${e("program")} = ${q.program(`${course}.${c("id")}`)}
      and y.${e("subjectType")} = 'user' and y.${e("subjectId")} = auth.uid()::text and y.${e("status")} <> 'cancelled'))`;

  const entryJson = (row: string): string =>
    `jsonb_build_object('lessonId', ${row}.${p("lesson")}, 'startedAt', ${field("progress", row, "startedAt")}, 'completedAt', ${row}.${p("completedAt")}, 'attempts', ${row}.${p("attempts")}, 'submissionId', ${field("progress", row, "submission")}, 'score', ${field("progress", row, "score")}, 'maxScore', ${field("progress", row, "maxScore")}, 'passed', ${field("progress", row, "passed")})`;

  const certificateJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${k("id")}, 'courseId', ${row}.${k("course")}, 'userId', ${row}.${k("user")}, 'code', ${row}.${k("code")}, 'issuedAt', ${field("certificates", row, "issuedAt")}, 'revokedAt', ${row}.${k("revokedAt")})`;

  const enrollmentOf = (course: string, user: string): string =>
    `select * into v_row from ${q.enrollments} x
  where x.${e("tenant")} = ${course}.${c("tenant")} and x.${e("program")} = ${q.program(`${course}.${c("id")}`)}
    and x.${e("subjectType")} = 'user' and x.${e("subjectId")} = ${user}::text`;

  const learnerOf = (row: string): string =>
    `select ${row}.${e("id")} as id, ${row}.${e("tenant")} as tenant, v_course.${c("id")} as course, ${row}.${e("user")} as learner into v_enrollment`;

  return `-- A learner's progress in a course: the enrollment's counts, an entry per
-- lesson they started and their certificate.
create or replace function ${fn("course_learner_json")}(enrollment_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'enrollmentId', x.${e("id")}, 'courseId', substr(x.${e("program")}, 8)::uuid, 'organizationId', x.${e("tenant")}, 'userId', x.${e("user")},
    'status', x.${e("status")}, 'completedLessons', x.${e("completedSteps")}, 'totalLessons', cardinality(x.${e("steps")}),
    'enrolledAt', x.${e("enrolledAt")}, 'completedAt', x.${e("completedAt")}, 'cancelledAt', x.${e("cancelledAt")}, 'updatedAt', x.${e("updatedAt")},
    'lessons', coalesce((
      select jsonb_agg(${entryJson("y")} order by ${ctx.has("progress", "startedAt") ? `y.${p("startedAt")}, ` : ""}y.${p("lesson")})
      from ${q.progress} y where y.${p("enrollment")} = x.${e("id")}
    ), '[]'::jsonb),
    'certificate', (select ${certificateJson("z")} from ${q.certificates} z where z.${k("enrollment")} = x.${e("id")})
  )
  from ${q.enrollments} x
  where x.${e("id")} = course_learner_json.enrollment_id
$$;
revoke execute on function ${fn("course_learner_json")}(uuid) from public, anon, authenticated;

-- Marks lesson done in the enrollment after its progress entry completed:
-- the step when the lesson is required, course_lesson.completed when it just
-- completed (fresh), then course_finish.
create or replace function ${fn("course_lesson_done")}(enrollment_id uuid, lesson_id uuid, fresh boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${q.enrollments};
  v_lesson ${q.lessons};
  v_was text;
begin
  select * into v_row from ${q.enrollments} x where x.${e("id")} = course_lesson_done.enrollment_id;
  select * into v_lesson from ${q.lessons} x where x.${l("id")} = course_lesson_done.lesson_id;
  perform ${fn("enrollment_ensure")}(v_row.${e("tenant")}, v_row.${e("program")}, null, ${fn("course_steps")}(v_lesson.${l("course")}), 'user', v_row.${e("subjectId")}, auth.uid());
  select x.${e("status")} into v_was from ${q.enrollments} x where x.${e("id")} = v_row.${e("id")};
  if v_lesson.${l("required")} then
    perform ${fn("enrollment_mark")}(v_row.${e("id")}, v_lesson.${l("id")}::text, true, auth.uid());
  end if;
  if course_lesson_done.fresh then
    ${
      ctx.emit({
        type: "course_lesson.completed",
        payload: `jsonb_build_object('organizationId', v_row.${e("tenant")}, 'id', v_lesson.${l("id")}, 'courseId', v_lesson.${l("course")}, 'userId', v_row.${e("user")}, 'enrollmentId', v_row.${e("id")})`,
        subject: `'course-lessons/' || v_lesson.${l("id")}::text`,
        tenant: `v_row.${e("tenant")}`,
      }) || "null;"
    }
  end if;
  perform ${fn("course_finish")}(v_row.${e("id")}, v_was);
end;
$$;
revoke execute on function ${fn("course_lesson_done")}(uuid, uuid, boolean) from public, anon, authenticated;

-- A course with its modules and their lessons in rank order, without lesson
-- content, and the caller's progress in it (null when not enrolled).
create or replace function ${fn("course_outline")}(course_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_course ${q.courses};
  v_row ${q.enrollments};
begin
  select * into v_course from ${q.courses} x where x.${c("id")} = course_outline.course_id;
  if v_course.${c("id")} is null or not ${visible("v_course")} then
    ${q.courseMissing}
  end if;
  ${enrollmentOf("v_course", "auth.uid()")};
  return ${q.courseJson("v_course")} || jsonb_build_object(
    'modules', coalesce((
      select jsonb_agg(jsonb_build_object('id', z.${m("id")}, 'title', z.${m("title")}, 'rank', z.${m("rank")}, 'lessons', coalesce((
        select jsonb_agg(jsonb_build_object('id', y.${l("id")}, 'moduleId', y.${l("module")}, 'title', y.${l("title")}, 'kind', y.${l("kind")}, 'required', y.${l("required")},
          'minutes', ${field("lessons", "y", "minutes")}, 'rank', y.${l("rank")}, 'completedAt', (
            select w.${p("completedAt")} from ${q.progress} w where w.${p("enrollment")} = v_row.${e("id")} and w.${p("lesson")} = y.${l("id")}
          )) order by y.${l("rank")}, y.${l("id")})
        from ${q.lessons} y where y.${l("module")} = z.${m("id")}
      ), '[]'::jsonb)) order by z.${m("rank")}, z.${m("id")})
      from ${q.modules} z where z.${m("course")} = v_course.${c("id")}
    ), '[]'::jsonb),
    'progress', case when v_row.${e("id")} is null then null else ${fn("course_learner_json")}(v_row.${e("id")}) end
  );
end;
$$;
${userGrant(`${fn("course_outline")}(uuid)`)}

-- A lesson with its content and quiz for the course's managers and its
-- enrolled learners, with the caller's progress entry.
create or replace function ${fn("course_lesson")}(lesson_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_lesson ${q.lessons};
  v_course ${q.courses};
  v_row ${q.enrollments};
  v_entry ${q.progress};
begin
  select * into v_lesson from ${q.lessons} x where x.${l("id")} = course_lesson.lesson_id;
  if v_lesson.${l("id")} is null then
    ${q.lessonMissing}
  end if;
  select * into v_course from ${q.courses} x where x.${c("id")} = v_lesson.${l("course")};
  ${enrollmentOf("v_course", "auth.uid()")} and x.${e("status")} <> 'cancelled';
  if v_row.${e("id")} is null and not ${q.allowed(`v_course.${c("tenant")}`, q.manage)} then
    if ${visible("v_course")} then
      ${notEnrolled}
    end if;
    ${q.lessonMissing}
  end if;
  select * into v_entry from ${q.progress} x where x.${p("enrollment")} = v_row.${e("id")} and x.${p("lesson")} = v_lesson.${l("id")};
  return jsonb_build_object('id', v_lesson.${l("id")}, 'courseId', v_lesson.${l("course")}, 'moduleId', v_lesson.${l("module")}, 'title', v_lesson.${l("title")},
    'kind', v_lesson.${l("kind")}, 'body', ${field("lessons", "v_lesson", "body")}, 'mediaUrl', ${field("lessons", "v_lesson", "mediaUrl")}, 'formId', v_lesson.${l("form")},
    'required', v_lesson.${l("required")}, 'minutes', ${field("lessons", "v_lesson", "minutes")}, 'rank', v_lesson.${l("rank")},
    'createdAt', ${field("lessons", "v_lesson", "createdAt")}, 'updatedAt', ${field("lessons", "v_lesson", "updatedAt")},
    'quiz', case when v_lesson.${l("form")} is null then null else ${quizJson(ctx, "v_lesson", l("form"))} end,
    'progress', case when v_entry.${p("lesson")} is null then null else ${entryJson("v_entry")} end);
end;
$$;
${userGrant(`${fn("course_lesson")}(uuid)`)}

-- Enrolls a user in a published course: the caller with courses.read, or
-- another user with courses.enroll. Enrolling again returns the enrollment;
-- enrolling a cancelled one starts it again with its completed lessons.
create or replace function ${fn("enroll_in_course")}(course_id uuid, user_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_course ${q.courses};
  v_row ${q.enrollments};
  v_user uuid := coalesce(enroll_in_course.user_id, auth.uid());
  v_enrollment record;
  v_id uuid;
begin
  select * into v_course from ${q.courses} x where x.${c("id")} = enroll_in_course.course_id;
  if v_course.${c("id")} is null or not ${visible("v_course")} then
    ${q.courseMissing}
  end if;
  if v_user is null then
    ${q.forbidden("sign in to enroll")}
  end if;
  if v_user is distinct from auth.uid() and not ${q.allowed(`v_course.${c("tenant")}`, q.enroll)} then
    ${q.forbidden("not allowed to enroll others in courses")}
  end if;
  if v_user = auth.uid() and not (${q.allowed(`v_course.${c("tenant")}`, q.read)} or ${q.allowed(`v_course.${c("tenant")}`, q.enroll)}) then
    ${q.forbidden("not allowed to enroll in courses")}
  end if;
  if v_course.${c("status")} <> 'published' then
    ${fail("COURSE_NOT_PUBLISHED", "only a published course takes enrollments", "55000")}
  end if;
  ${enrollmentOf("v_course", "v_user")}
  for update;
  if v_row.${e("id")} is not null and v_row.${e("status")} <> 'cancelled' then
    return ${fn("course_learner_json")}(v_row.${e("id")});
  end if;
  if v_row.${e("id")} is not null then
    -- Clearing the steps makes enrollment_ensure take the current ones and
    -- recount the lessons completed before.
    update ${q.enrollments} x
    set ${e("status")} = 'active', ${e("cancelledAt")} = null, ${e("enrolledBy")} = auth.uid(), ${e("enrolledAt")} = now(), ${e("steps")} = '{}'
    where x.${e("id")} = v_row.${e("id")};
  end if;
  v_id := ${fn("enrollment_ensure")}(v_course.${c("tenant")}, ${q.program(`v_course.${c("id")}`)}, null, ${fn("course_steps")}(v_course.${c("id")}), 'user', v_user::text, auth.uid());
  select * into v_row from ${q.enrollments} x where x.${e("id")} = v_id;
  ${learnerOf("v_row")};
  ${q.learnerRecord("course.enrolled", "enrolled in a course")}
  perform ${fn("course_finish")}(v_id, 'active');
  return ${fn("course_learner_json")}(v_id);
end;
$$;
${userGrant(`${fn("enroll_in_course")}(uuid, uuid)`)}

-- Cancels a user's active enrollment in a course: the caller's own, or
-- another user's with courses.enroll. Their progress stays.
create or replace function ${fn("unenroll_from_course")}(course_id uuid, user_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_course ${q.courses};
  v_row ${q.enrollments};
  v_user uuid := coalesce(unenroll_from_course.user_id, auth.uid());
  v_enrollment record;
begin
  select * into v_course from ${q.courses} x where x.${c("id")} = unenroll_from_course.course_id;
  if v_course.${c("id")} is null or not ${visible("v_course")} then
    ${q.courseMissing}
  end if;
  if v_user is distinct from auth.uid() and not ${q.allowed(`v_course.${c("tenant")}`, q.enroll)} then
    ${q.forbidden("not allowed to unenroll others from courses")}
  end if;
  ${enrollmentOf("v_course", "v_user")}
  for update;
  if v_row.${e("id")} is null then
    ${fail("COURSE_NOT_ENROLLED", "this user is not enrolled in this course", "P0002")}
  end if;
  if v_row.${e("status")} = 'completed' then
    ${q.invalid("a completed enrollment can't be cancelled")}
  end if;
  if v_row.${e("status")} = 'active' then
    update ${q.enrollments} x
    set ${e("status")} = 'cancelled', ${e("cancelledAt")} = now(), ${e("updatedAt")} = now()
    where x.${e("id")} = v_row.${e("id")}
    returning * into v_row;
    ${learnerOf("v_row")};
    ${q.learnerRecord("course.unenrolled", "unenrolled from a course")}
  end if;
  return ${fn("course_learner_json")}(v_row.${e("id")});
end;
$$;
${userGrant(`${fn("unenroll_from_course")}(uuid, uuid)`)}

-- Records that the enrolled caller opened a lesson; returns its progress
-- entry.
create or replace function ${fn("start_course_lesson")}(lesson_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
${learner}
  v_entry ${q.progress};
begin
  select * into v_lesson from ${q.lessons} x where x.${l("id")} = start_course_lesson.lesson_id;
  if v_lesson.${l("id")} is null then
    ${q.lessonMissing}
  end if;
  select * into v_row from ${q.enrollments} x
  where x.${e("tenant")} = v_lesson.${l("tenant")} and x.${e("program")} = ${q.program(`v_lesson.${l("course")}`)}
    and x.${e("subjectType")} = 'user' and x.${e("subjectId")} = auth.uid()::text and x.${e("status")} <> 'cancelled';
  if v_row.${e("id")} is null then
    ${notEnrolled}
  end if;
  insert into ${q.progress} (${p("enrollment")}, ${p("lesson")}, ${p("tenant")}, ${p("course")}, ${p("user")})
  values (v_row.${e("id")}, v_lesson.${l("id")}, v_lesson.${l("tenant")}, v_lesson.${l("course")}, auth.uid())
  on conflict do nothing;
  select * into v_entry from ${q.progress} x where x.${p("enrollment")} = v_row.${e("id")} and x.${p("lesson")} = v_lesson.${l("id")};
  return ${entryJson("v_entry")};
end;
$$;
${userGrant(`${fn("start_course_lesson")}(uuid)`)}

-- Marks a content or video lesson done, or not done, for the enrolled
-- caller; returns their progress. A quiz lesson completes by passing it.
create or replace function ${fn("complete_course_lesson")}(lesson_id uuid, done boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
${learner}
  v_before timestamptz;
begin
  select * into v_lesson from ${q.lessons} x where x.${l("id")} = complete_course_lesson.lesson_id;
  if v_lesson.${l("id")} is null then
    ${q.lessonMissing}
  end if;
  select * into v_row from ${q.enrollments} x
  where x.${e("tenant")} = v_lesson.${l("tenant")} and x.${e("program")} = ${q.program(`v_lesson.${l("course")}`)}
    and x.${e("subjectType")} = 'user' and x.${e("subjectId")} = auth.uid()::text and x.${e("status")} <> 'cancelled'
  for update;
  if v_row.${e("id")} is null then
    ${notEnrolled}
  end if;
  if v_lesson.${l("kind")} = 'quiz' then
    ${q.invalid("a quiz lesson completes when you pass its quiz")}
  end if;
  select x.${p("completedAt")} into v_before from ${q.progress} x
  where x.${p("enrollment")} = v_row.${e("id")} and x.${p("lesson")} = v_lesson.${l("id")};
  if complete_course_lesson.done then
    insert into ${q.progress} (${p("enrollment")}, ${p("lesson")}, ${p("tenant")}, ${p("course")}, ${p("user")}, ${p("completedAt")})
    values (v_row.${e("id")}, v_lesson.${l("id")}, v_lesson.${l("tenant")}, v_lesson.${l("course")}, auth.uid(), now())
    on conflict ${q.progressTarget} do update
    set ${p("completedAt")} = coalesce(${q.progress}.${p("completedAt")}, now())${touched};
    perform ${fn("course_lesson_done")}(v_row.${e("id")}, v_lesson.${l("id")}, v_before is null);
  else
    update ${q.progress} x set ${p("completedAt")} = null${touched}
    where x.${p("enrollment")} = v_row.${e("id")} and x.${p("lesson")} = v_lesson.${l("id")};
    if v_lesson.${l("required")} then
      perform ${fn("enrollment_ensure")}(v_row.${e("tenant")}, v_row.${e("program")}, null, ${fn("course_steps")}(v_lesson.${l("course")}), 'user', v_row.${e("subjectId")}, auth.uid());
      perform ${fn("enrollment_mark")}(v_row.${e("id")}, v_lesson.${l("id")}::text, false, auth.uid());
    end if;
  end if;
  return ${fn("course_learner_json")}(v_row.${e("id")});
end;
$$;
${userGrant(`${fn("complete_course_lesson")}(uuid, boolean)`)}
${quizSubmit(ctx, learner)}
-- A user's progress in a course, or null when not enrolled: the caller's
-- own, or another user's with courses.enroll or courses.manage.
create or replace function ${fn("course_progress")}(course_id uuid, user_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_course ${q.courses};
  v_row ${q.enrollments};
  v_user uuid := coalesce(course_progress.user_id, auth.uid());
begin
  select * into v_course from ${q.courses} x where x.${c("id")} = course_progress.course_id;
  if v_course.${c("id")} is null or not ${visible("v_course")} then
    ${q.courseMissing}
  end if;
  if v_user is distinct from auth.uid() and not (${q.allowed(`v_course.${c("tenant")}`, q.enroll)} or ${q.allowed(`v_course.${c("tenant")}`, q.manage)}) then
    ${q.forbidden("not allowed to read other learners' progress")}
  end if;
  ${enrollmentOf("v_course", "v_user")};
  return case when v_row.${e("id")} is null then null else ${fn("course_learner_json")}(v_row.${e("id")}) end;
end;
$$;
${userGrant(`${fn("course_progress")}(uuid, uuid)`)}

-- The course's learners, most recently changed first: courses.enroll or
-- courses.manage.
create or replace function ${fn("list_course_learners")}(course_id uuid, status text default null, page_size integer default null, before timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_course ${q.courses};
begin
  select * into v_course from ${q.courses} x where x.${c("id")} = list_course_learners.course_id;
  if v_course.${c("id")} is null then
    ${q.courseMissing}
  end if;
  if not (${q.allowed(`v_course.${c("tenant")}`, q.enroll)} or ${q.allowed(`v_course.${c("tenant")}`, q.manage)}) then
    ${q.forbidden("not allowed to read the course's learners")}
  end if;
  if list_course_learners.status is not null and list_course_learners.status not in ('active', 'completed', 'cancelled') then
    ${q.invalid("status must be active, completed or cancelled")}
  end if;
  return coalesce((
    select jsonb_agg(${fn("course_learner_json")}(y.${e("id")}) order by y.${e("updatedAt")} desc, y.${e("id")})
    from (
      select x.${e("id")}, x.${e("updatedAt")} from ${q.enrollments} x
      where x.${e("tenant")} = v_course.${c("tenant")} and x.${e("program")} = ${q.program(`v_course.${c("id")}`)}
        and (list_course_learners.status is null or x.${e("status")} = ${q.enrolled.cast("enrollments", "status", "list_course_learners.status")})
        and (list_course_learners.before is null or x.${e("updatedAt")} < list_course_learners.before)
      order by x.${e("updatedAt")} desc, x.${e("id")}
      limit ${pageSize("list_course_learners.page_size", 50, 200)}
    ) y
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_course_learners")}(uuid, text, integer, timestamptz)`)}

-- Checks a certificate by the code its link carries. Anyone with the code
-- learns the course, when it was issued and whether it was revoked; null for
-- an unknown code.
create or replace function ${fn("verify_course_certificate")}(code text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', z.${k("id")}, 'courseId', z.${k("course")}, 'courseTitle', y.${c("title")}, 'organizationId', z.${k("tenant")},
    'issuedAt', ${field("certificates", "z", "issuedAt")}, 'revokedAt', z.${k("revokedAt")}, 'valid', z.${k("revokedAt")} is null)
  from ${q.certificates} z join ${q.courses} y on y.${c("id")} = z.${k("course")}
  where z.${k("code")} = lower(verify_course_certificate.code)
$$;
revoke execute on function ${fn("verify_course_certificate")}(text) from public;
grant execute on function ${fn("verify_course_certificate")}(text) to anon, authenticated, service_role;
`;
}
