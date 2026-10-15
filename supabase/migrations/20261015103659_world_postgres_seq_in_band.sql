ALTER TABLE "workflow"."workflow_event_slots"
  ADD COLUMN "seq_in_band" integer NOT NULL DEFAULT 1;
