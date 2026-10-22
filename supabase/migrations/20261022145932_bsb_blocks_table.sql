DROP TABLE "better_supabase"."modules";

CREATE TABLE "better_supabase"."blocks" (
  "name"         text                     NOT NULL,
  "version"      integer                  NOT NULL,
  "mode"         text                     NOT NULL,
  "installed_at" timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "blocks_pkey" PRIMARY KEY (name)
);

ALTER TABLE "better_supabase"."blocks"
  ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON TABLE "better_supabase"."blocks" TO "service_role";
