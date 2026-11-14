import { queueDynamicSchedules, queueSchedules } from "better-supabase/eve";
import { defineSchedule } from "eve/schedules";

import eve from "../channels/eve";
import { agentJobs, memberSchedules, scheduleRuns } from "../lib/server";
import requests from "./requests";

const scheduled = queueSchedules({ queue: agentJobs, channels: { eve } });

// The key is the definition's path under agent/schedules/.
const dynamic = queueDynamicSchedules({
  queue: scheduleRuns,
  provider: memberSchedules,
  collections: { requests },
});

// Every minute: enqueue the queue block's due schedules, then start a session
// for each `eve` job, as the member who scheduled it, and fire the members'
// dynamic schedules. Members schedule digests with
// `scheduleAgent(agentJobs, name, cron, job, { context })`, or ask the agent,
// which manages `requests` through its schedule tools.
export default defineSchedule({
  cron: "* * * * *",
  run: (args) => {
    scheduled(args);
    dynamic(args);
  },
});
