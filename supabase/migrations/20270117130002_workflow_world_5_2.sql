CREATE TABLE "workflow"."workflow_job_lock_holders" (
  "worker_id"  text                     NOT NULL,
  "renewed_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "workflow_job_lock_holders_pkey" PRIMARY KEY (worker_id)
);

ALTER TABLE "workflow"."workflow_job_lock_holders"
  ENABLE ROW LEVEL SECURITY;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "workflow"."workflow_job_lock_holders" TO "service_role";
