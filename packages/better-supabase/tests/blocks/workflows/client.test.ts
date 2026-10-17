import { describe, expect, it, vi } from "vitest";

import type { WorkflowRun } from "../../../src/blocks/workflows/workflows.ts";

import {
  createWorkflowRunController,
  createWorkflowRunsController,
} from "../../../src/blocks/workflows/client.ts";
import {
  failed,
  fakeAuth,
  fakeTopic,
  flush,
  held,
  mount,
  OTHER,
  resolved,
  signedIn,
} from "../../fixtures/ports.ts";

// SAFETY: the controllers read only the id.
const run = (id: string) => ({ id }) as unknown as WorkflowRun;

describe("createWorkflowRunsController", () => {
  it("lists a tenant's runs and reloads on its topic", async () => {
    const topic = fakeTopic();
    const list = vi.fn(() => resolved([run("r1")]));

    const { view, unmount } = mount(
      createWorkflowRunsController({
        client: { runs: { list } },
        auth: fakeAuth(),
        ports: { topic: topic.port },
        tenant: "org-1",
        definition: "onboard",
        status: "running",
        limit: 5,
      }),
    );

    await flush();
    expect(list).toHaveBeenCalledWith({
      tenant: "org-1",
      definition: "onboard",
      status: "running",
      limit: 5,
    });
    expect(view().runs).toHaveLength(1);
    expect(view().status).toBe("subscribed");
    topic.emit("workflow-runs:org-1", "run.completed");
    topic.rejoin("workflow-runs:org-1");
    expect(list).toHaveBeenCalledTimes(3);
    list.mockReturnValue(failed("down"));
    await view().refresh();
    expect(view().error?.message).toBe("down");
    unmount();
  });

  it("lists the user's own runs once and drops stale answers", async () => {
    const topic = fakeTopic();
    const answer = held([run("late")]);
    const list = vi.fn(() => answer.result);

    const controller = createWorkflowRunsController({
      client: { runs: { list } },
      auth: fakeAuth(),
      ports: { topic: topic.port },
    });

    const mounted = mount(controller);
    await flush();
    expect(list).toHaveBeenCalledWith({});
    expect(topic.joined).toEqual([]);
    mounted.unmount();
    answer.release();
    await flush();
    expect(controller.getSnapshot().runs).toBeUndefined();
  });
});

describe("createWorkflowRunController", () => {
  it("loads by engine id, then follows the run's own topic", async () => {
    const auth = fakeAuth();
    const topic = fakeTopic();
    const get = vi.fn(() => resolved<WorkflowRun | undefined>(run("r1")));

    const requestCancel = vi.fn(() =>
      resolved<WorkflowRun | undefined>(run("r1")),
    );

    const { view, unmount } = mount(
      createWorkflowRunController({
        client: { runs: { get, requestCancel } },
        auth,
        ports: { topic: topic.port },
        run: "wrun_1",
      }),
    );

    await flush();
    expect(get).toHaveBeenCalledWith("wrun_1");
    expect(view().run?.id).toBe("r1");
    expect(topic.open()).toEqual(["workflow-run:r1"]);
    topic.emit("workflow-run:r1", "run.updated");
    topic.rejoin("workflow-run:r1");
    await flush();
    expect(get).toHaveBeenCalledTimes(3);
    expect(topic.joined).toHaveLength(1);

    await view().cancel();
    expect(requestCancel).toHaveBeenCalledWith("wrun_1");
    requestCancel.mockReturnValue(failed("finished"));
    await view().cancel();
    expect(view().error?.message).toBe("finished");
    get.mockReturnValue(failed("gone"));
    await view().refresh();
    expect(view().error?.message).toBe("gone");

    get.mockReturnValue(resolved<WorkflowRun | undefined>(run("r2")));
    auth.set(signedIn(OTHER));
    await flush();
    expect(topic.open()).toEqual(["workflow-run:r2"]);
    unmount();
    expect(topic.open()).toEqual([]);
  });

  it("waits without a run and does nothing for one it may not read", async () => {
    const topic = fakeTopic();
    const get = vi.fn(() => resolved<WorkflowRun | undefined>(undefined));

    const requestCancel = vi.fn(() =>
      resolved<WorkflowRun | undefined>(undefined),
    );

    const idle = mount(
      createWorkflowRunController({
        client: { runs: { get, requestCancel } },
        auth: fakeAuth(),
        ports: { topic: topic.port },
        run: null,
      }),
    );

    await idle.view().refresh();
    await idle.view().cancel();
    idle.unmount();
    expect(get).not.toHaveBeenCalled();
    expect(requestCancel).not.toHaveBeenCalled();

    const hidden = mount(
      createWorkflowRunController({
        client: { runs: { get, requestCancel } },
        auth: fakeAuth(),
        ports: { topic: topic.port },
        run: "r9",
      }),
    );

    await flush();
    expect(hidden.view().run).toBeUndefined();
    expect(topic.joined).toEqual([]);
    hidden.unmount();
  });

  it("drops an answer that arrives after it stopped", async () => {
    const topic = fakeTopic();
    const answer = held<WorkflowRun | undefined>(run("r1"));

    const controller = createWorkflowRunController({
      client: {
        runs: {
          get: () => answer.result,
          requestCancel: () => resolved(undefined),
        },
      },
      auth: fakeAuth(),
      ports: { topic: topic.port },
      run: "r1",
    });

    const mounted = mount(controller);
    await flush();
    mounted.unmount();
    answer.release();
    await flush();
    expect(controller.getSnapshot().run).toBeUndefined();
    expect(topic.joined).toEqual([]);
  });
});
