---
"better-supabase": minor
---

Add the `reactions` block (`better-supabase/blocks/reactions`, `better-supabase/blocks/reactions/react` and the `reactions` SQL module): emoji reactions on any registry subject, comments and inbox messages, checked against each subject's own read policies, with counts, `reacted` and the first actors per emoji, custom emoji per organization, a `reactions:{organizationId}` realtime topic and `useReactions()`. The module records `reaction.added` and `reaction.removed`. With it installed, the inbox's `react_to_message` stores reactions in the table and keeps the message's `reactions` column as a copy; installing it copies existing message reactions.
