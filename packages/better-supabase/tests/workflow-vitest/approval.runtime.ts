import { waitForHook } from "@workflow/vitest";
import { describe, expect, it } from "vitest";
import { start } from "workflow/api";

import { approvalWaiter } from "../../src/workflow-sdk/approval-waiter.ts";
import { waitForApproval } from "./workflows/approval.ts";

describe("approvalWaiter on the Workflow runtime", () => {
  it("resumes a waiting run when the approval is woken", async () => {
    const run = await start(waitForApproval, ["apr_rt_1"]);
    await waitForHook(run, { token: "apr_rt_1" });
    await approvalWaiter.wake("apr_rt_1", { approved: true });

    expect(await run.returnValue).toEqual({ status: "resumed" });
  });

  it("wakes a run whose hook is created after the decision", async () => {
    const run = await start(waitForApproval, ["apr_rt_2"]);
    // The decision lands before the run reaches createHook; the bounded retry catches up.
    await approvalWaiter.wake("apr_rt_2", { approved: false });

    expect(await run.returnValue).toEqual({ status: "resumed" });
  });
});
