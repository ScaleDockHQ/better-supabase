---
"better-supabase": minor
---

New `courses` block (`better-supabase/blocks/courses`) for courses with modules, lessons, scored quizzes, learner progress and certificates. It runs on the `enrollments` block: a learner's enrollment in a course is an enrollment in the program `course:<id>`, with a step per required lesson, so the enrollments block keeps one record of who is enrolled in what.

- `save`, `saveModule` and `saveLesson` build the outline; modules and lessons order by fractional rank keys (ADR 0021), and a new one goes last. A lesson is `content`, `video` or `quiz`; a quiz lesson names a `forms` form.
- `enroll`, `unenroll`, `start`, `complete`, `reset` and `submitQuiz` track progress per lesson in `course_lesson_progress`. Postgres grades a quiz through the forms block's scoring, so the browser never sees the answer key and can't change the score; a passed quiz completes its lesson.
- Completing every required lesson completes the course and, when the course gives one, issues a certificate with a random code. `verifyCertificate(code)` checks it without signing in; `revokeCertificate` withdraws it.
- `outline`, `lesson`, `progress` and `learners` read the course; members read published courses, `courses.enroll` enrolls others, `courses.manage` builds them.
- The block emits `course.*`, `course_lesson.completed` and `course_certificate.*` events, and every write is audited. Its five tables rename through `blocks.courses.entities`.
- The enrollments block refuses to complete or reset the steps of a `course:` program, so progress only changes through the courses block.

Install it with `courses: {}` next to `forms` and `enrollments`, then run `better-supabase sql sync` and `db diff`. The `course-outline` and `lesson-player` recipes render it with ReUI.
