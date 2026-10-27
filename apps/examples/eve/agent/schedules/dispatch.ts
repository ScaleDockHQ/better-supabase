import { queueSchedules } from "better-supabase/eve";
import { defineSchedule } from "eve/schedules";

import eve from "../channels/eve";
import { agentJobs } from "../lib/server";

// Every minute: enqueue the queue block's due schedules, then start a session
// for each `eve` job, as the member who scheduled it. Members schedule their
// own digests with `scheduleAgent(agentJobs, name, cron, job, { context })`.
export default defineSchedule({
  cron: "* * * * *",
  run: queueSchedules({ queue: agentJobs, channels: { eve } }),
});
