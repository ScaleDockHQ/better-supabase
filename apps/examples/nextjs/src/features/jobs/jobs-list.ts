import { defineBlockList } from "@/lib/block-list-url";

/** `/settings/jobs/runs?q=&status=&queue=&sort=&after=`. */
export const jobList = defineBlockList({
  facets: ["status", "queue"],
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
