import { createAiSchedules } from "better-supabase/blocks/ai-schedules";
import { aiScheduleDispatch } from "better-supabase/eve";
import { defineSchedule } from "eve/schedules";

import eve from "../channels/eve";
import { transport } from "../lib/blocks";

// Tasks in `ai_scheduled_tasks` (source `ai-schedules`) run as eve sessions of
// the member who owns them, on the `eve` channel. Each run is recorded in
// `ai_task_runs`; the block's notifier tells the member when one fails.
const dispatch = aiScheduleDispatch({ channels: { eve }, channel: "eve" });

const schedules = createAiSchedules({
  transport,
  service: transport,
  run: dispatch.run,
});

export default defineSchedule({
  cron: "* * * * *",
  run: dispatch.handler(schedules),
});
