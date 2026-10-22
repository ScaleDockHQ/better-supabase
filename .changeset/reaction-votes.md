---
"better-supabase": minor
---

Breaking: reactions carry up and down votes.

- `vote(subject, value)` sets the caller's vote (`1`, `-1`, or `0` to clear it) and returns the subject's tally, and `votes(subjects)` reads tallies keyed `type:id`. The `reaction_scores` table keeps each subject's score, up and down counts.
- Reaction rows gain `kind` (`emoji` or `vote`) and `value`, and the unique key includes `kind`. `better-supabase sql upgrade` fills them for existing rows. A custom-mode reactions table needs both columns.
- `reaction.added` and `reaction.removed` also fire for votes, with `kind` and `value`. Filter on `kind === "emoji"` to keep the old meaning. See the 0.13 to 0.14 guide.
