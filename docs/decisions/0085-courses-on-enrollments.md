# 0085: Courses run on enrollments, with quizzes graded by forms

- Status: accepted
- Date: 2026-10-22

## Context

A course needs who is enrolled, which lessons each learner finished, and
whether they completed it. The `enrollments` block (ADR 0077) already keeps
enrollments of a subject in a program of ordered steps, with counts, status
and events, and ADR 0077 names courses as a follow-up on its tables. Quizzes
need grading the learner can't tamper with, and the `forms` block now scores
a submission in Postgres against an answer key no client role reads.

## Decision

A `courses` block owns the content: `courses`, `course_modules` and
`course_lessons`, with modules and lessons ordered by fractional rank keys
(ADR 0021). It doesn't keep its own enrollments. A learner's enrollment is an
enrollment of the `user` subject in the program `course:<course id>`, created
and marked through `enrollment_ensure` and `enrollment_mark`, so the courses
block checks its own permissions (`courses.read`, `enroll`, `manage`). The
program's steps are the ids of the course's required lessons in module, then
lesson order; saving or deleting a lesson or module resyncs every live
enrollment, so the counts follow the outline.

Per-lesson detail the enrollments block has no place for (when a lesson was
started, quiz attempts, the last score) lives in `course_lesson_progress`,
keyed by enrollment and lesson. A quiz lesson names a form. `submit_course_quiz`
saves the answers through the forms block's `form_submission_save`, which
grades them in SQL; a passed attempt, or one on a form without a pass mark,
completes the lesson. When the enrollment completes, the block records
`course.completed` and, when the course gives one, issues a certificate with
a random 128-bit code that `verify_course_certificate` checks without signing
in.

The enrollments block refuses to complete or reset a step of a `course:`
program, as it already refuses to cancel module programs, so a lesson's
progress and its step can't drift apart.

## Consequences

- An admin page lists course enrollments with every other program, and the
  `enrollment.*` events fire for them too, next to the `course.*` events.
- Courses require `forms` and `enrollments`; a course without quizzes still
  installs `forms`.
- A lesson made optional leaves the steps; completing it still writes
  progress and `course_lesson.completed` but doesn't count toward completion.
- The courses section isn't attached to other subjects' record pages: a
  course is its own page, rendered by the `course-outline` and
  `lesson-player` recipes.
- Timed release of lessons (drip schedules) and prerequisites between
  courses are follow-ups; this block has no scheduling.
