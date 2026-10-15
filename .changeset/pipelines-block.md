---
"better-supabase": minor
---

The `pipelines` SQL module and `better-supabase/blocks/pipelines` put any record in `config.subjects` on pipelines an organization edits. Bind a type in `blocks.pipelines.options.subjects` with its categories, each mapped to `open`, `success` or `failure`, and the module keeps several pipelines per type (or one per scope, such as a job), checks every stage change, stamps the time a record entered its stage, writes a stage history and records `pipeline.stage_changed` with the record as its subject. A binding can set a status column from the stage category through the state machine, and the owner watches the record when notifications is installed. `createPipelines` manages pipelines, stages and transitions, and reads the board (counts and per-currency totals weighted by probability), stats (entries, time in stage, win rate) and health (days in stage, rotting).
