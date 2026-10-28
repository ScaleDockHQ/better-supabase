-- better-supabase upgrade: steps that run before the schema diff.

-- state-machine: version 2 to 3. status_history keeps the actor name, email, IP address and user agent that transition() takes as actor; history: "app" leaves the history to the app, and history.write: false only reads the app table.
drop function if exists "better_supabase"."transition"(text, text, text, text);
