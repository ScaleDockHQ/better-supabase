CREATE TABLE "workflow"."workflow_rate_limits" (
  "scope"  character varying NOT NULL,
  "key"    character varying NOT NULL,
  "tat_us" bigint,
  CONSTRAINT "workflow_rate_limits_scope_key_pk" PRIMARY KEY (scope, key)
);

ALTER TABLE "workflow"."workflow_rate_limits"
  ENABLE ROW LEVEL SECURITY;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "workflow"."workflow_rate_limits" TO "service_role";
