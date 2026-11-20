CREATE TABLE "workflow"."workflow_run_delivery_leases" (
  "run_id"       character varying        NOT NULL,
  "owner_job_id" bigint                   NOT NULL,
  "wake"         jsonb,
  "wake_resume"  boolean                  NOT NULL DEFAULT false,
  "deferred"     jsonb                    NOT NULL DEFAULT '[]'::jsonb,
  "claimed_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "workflow_run_delivery_leases_pkey" PRIMARY KEY (run_id)
);

ALTER TABLE "workflow"."workflow_run_delivery_leases"
  ENABLE ROW LEVEL SECURITY;

-- Runs that exist before this migration start with wake_pending set, as in
-- @workflow/world-postgres migration 0032: startup recovery then lets their next
-- completed delivery decide. New runs start clear.
ALTER TABLE "workflow"."workflow_runs"
  ADD COLUMN "wake_pending" boolean NOT NULL DEFAULT true;

ALTER TABLE "workflow"."workflow_runs"
  ALTER COLUMN "wake_pending" SET DEFAULT false;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "workflow"."workflow_run_delivery_leases" TO "service_role";
