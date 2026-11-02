---
"better-supabase": minor
---

The `comments`, `inbox`, `workflows`, `enrollments`, `automations` and `sequences` SQL modules now
call `before_` and `after_` hooks around their write functions: `create_comment`, `assign_comment`,
the inbox start, send, assign and status change functions, `create_workflow_schedule`,
`request_workflow_start`, `enroll`, `cancel_enrollment`, `save_rule`, `remove_rule`, `save_sequence`
and `enroll_in_sequence`. Define a function named after the hook (for example
`before_comment_create`) and the module calls it. Run `better-supabase upgrade` to regenerate the
module files.
