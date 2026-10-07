---
"better-supabase": patch
---

`supabase db lint` passes with the comments module installed. `copy_comments` built its id map in a temporary table, which plpgsql_check cannot see, so the lint failed with `relation "bs_comment_copy" does not exist`. It now maps the ids in a materialized CTE and inserts the copies in one statement. A test checks that no SQL module creates a temporary table.
