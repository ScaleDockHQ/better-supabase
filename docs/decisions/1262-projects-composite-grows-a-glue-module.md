# 1262: The projects composite grows a glue module

- Status: accepted
- Date: 2026-11-26

## Context

`projects` installed tasks, time, billing and meetings, and had no page read.
Comments, files, tags, the timeline, relations and saved views already cover a
project once it is a subject. ADR 0196 allows a composite to ship glue SQL.
None of the composites did.

## Decision

`projects` requires those six blocks and the subjects block, so an existing
install gains whichever of them it did not already have on `upgrade`. The
composite's first glue module, `src/sql/modules/projects.ts`, owns project
updates and initiatives. Tasks keeps the project, milestone and iteration
rows, because a task points at them. The module is registered immediately
before the row-level-security pass. `overview`, `cards` and `views` live in
their own files so the composite entry stays under the 12 000 byte cap.

## Alternatives considered

A new composite would have split project work across two installs. Putting
updates and initiatives in tasks would have mixed rows a task never points at
into the task module.

## Consequences

`upgrade` installs the new parts and the glue module. Apps that renamed the
project subject pass that name to `overview`. A later page in the example is
recorded on the roadmap, not built here.
