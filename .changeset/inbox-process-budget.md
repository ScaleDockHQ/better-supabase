---
"better-supabase": minor
---

`inbox.process` takes `budgetMs`, like the jobs drain: it stops claiming once the budget is spent and finishes the messages it already claimed, so a backlog can't outrun a serverless function. Its options are exported as `InboxProcessOptions`.
