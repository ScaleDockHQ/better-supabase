import { defineSchedule } from "eve/schedules";

import { sync } from "../lib/sync";

// The safety net behind the wake-ups: every minute, sync the sessions a job
// has not caught up with.
export default defineSchedule({
  cron: "* * * * *",
  run: async () => {
    await sync.sweepSessions();
  },
});
