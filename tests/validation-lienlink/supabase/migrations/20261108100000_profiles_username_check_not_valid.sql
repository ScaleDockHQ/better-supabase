set lock_timeout = '5s';

ALTER TABLE "better_supabase"."profiles"
  DROP CONSTRAINT "bsb_profiles_username_check";

ALTER TABLE "better_supabase"."profiles"
  ADD CONSTRAINT "bsb_profiles_username_check"
    CHECK
    (((username IS NULL) OR ((length(username) >= 3) AND (length(username) <= 32) AND (username ~* '^[a-z][a-z0-9_]*$'::text) AND (lower(username) <> ALL (ARRAY['admin'::text,
    'administrator'::text,
    'api'::text,
    'app'::text,
    'auth'::text,
    'billing'::text,
    'help'::text,
    'login'::text, 'logout'::text, 'me'::text, 'null'::text, 'root'::text, 'settings'::text, 'signup'::text, 'support'::text, 'system'::text, 'www'::text]))))) NOT VALID;
