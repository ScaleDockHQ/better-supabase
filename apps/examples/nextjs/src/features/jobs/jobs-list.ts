import { defineAdminList } from "@/lib/admin-list";

/** `/settings/jobs/runs?q=&status=&queue=&sort=&after=`. */
export const jobList = defineAdminList({
  facets: {
    status: ["queued", "scheduled", "running", "retrying", "succeeded", "dead"],
    // The queue names are the data's, so any value passes.
    queue: [],
  },
  sorts: ["newest", "oldest"],
  defaultSort: "newest",
  pageSize: 25,
});

/** One job run as the overview and the list route send it. */
export interface JobRow {
  /** `<queue>:<message id>`. */
  readonly id: string;
  readonly queue: string;
  readonly messageId: number;
  readonly status: string;
  readonly attempts: number;
  readonly lastError: string | null;
  readonly enqueuedAt: string;
  readonly finishedAt: string | null;
}
