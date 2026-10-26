-- Adding a stored generated column rewrites the table under an exclusive lock.
set lock_timeout = '5s';

ALTER TABLE "public"."contacts"
  ADD COLUMN "email_domain" text GENERATED ALWAYS AS (lower(split_part(email, '@'::text, 2))) STORED;
