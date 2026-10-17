import { describe, expect, it, vi } from "vitest";

import type {
  WorkflowDefinition,
  WorkflowNodeRun,
  WorkflowStepInfo,
} from "../../../src/blocks/workflow-builder/workflow-builder.ts";
import type { WorkflowRun } from "../../../src/blocks/workflows/workflows.ts";

import {
  createWorkflowBuilderController,
  createWorkflowCanvasRunController,
} from "../../../src/blocks/workflow-builder/client.ts";
import {
  failed,
  fakeAuth,
  fakeTopic,
  flush,
  held,
  mount,
  resolved,
} from "../../fixtures/ports.ts";

// SAFETY: the controllers read only these fields.
const definition = (id: string) => ({ id }) as unknown as WorkflowDefinition;
const step = (id: string) => ({ id }) as unknown as WorkflowStepInfo;
const node = (id: string) => ({ node: id }) as unknown as WorkflowNodeRun;
const run = (id: string) => ({ id }) as unknown as WorkflowRun;

describe("createWorkflowBuilderController", () => {
  it("loads the definitions and the step library", async () => {
    const list = vi.fn(() => resolved([definition("d1")]));
    const steps = vi.fn(() => resolved([step("http")]));

    const { view, unmount } = mount(
      createWorkflowBuilderController({
        client: { definitions: { list }, steps: { list: steps } },
        auth: fakeAuth(),
        tenant: "org-1",
      }),
    );

    await flush();
    expect(list).toHaveBeenCalledWith("org-1");
    expect(view()).toMatchObject({ error: undefined });
    expect(view().definitions).toHaveLength(1);
    expect(view().steps).toHaveLength(1);

    steps.mockReturnValue(failed("no steps"));
    await view().refresh();
    expect(view().error?.message).toBe("no steps");
    expect(view().steps).toHaveLength(1);
    list.mockReturnValue(failed("no definitions"));
    await view().refresh();
    expect(view().error?.message).toBe("no definitions");
    unmount();
  });

  it("lists every tenant's definitions and drops stale answers", async () => {
    const answer = held([definition("late")]);
    const list = vi.fn(() => answer.result);

    const controller = createWorkflowBuilderController({
      client: {
        definitions: { list },
        steps: { list: () => resolved([]) },
      },
      auth: fakeAuth(),
    });

    const mounted = mount(controller);
    await flush();
    expect(list).toHaveBeenCalledWith(undefined);
    mounted.unmount();
    answer.release();
    await flush();
    expect(controller.getSnapshot().definitions).toBeUndefined();
  });
});

describe("createWorkflowCanvasRunController", () => {
  it("loads the run and its nodes and follows the run topic", async () => {
    const topic = fakeTopic();
    const get = vi.fn(() => resolved<WorkflowRun | undefined>(run("r1")));
    const nodes = vi.fn(() => resolved([node("a"), node("b")]));

    const { view, unmount } = mount(
      createWorkflowCanvasRunController({
        client: { runs: { get }, nodeRuns: { list: nodes } },
        auth: fakeAuth(),
        ports: { topic: topic.port },
        run: "wrun_1",
      }),
    );

    await flush();
    expect(view().run?.id).toBe("r1");
    expect(Object.keys(view().nodes)).toEqual(["a", "b"]);
    expect(topic.open()).toEqual(["workflow-run:r1"]);
    topic.emit("workflow-run:r1", "node.completed");
    await flush();
    expect(nodes).toHaveBeenCalledTimes(2);

    nodes.mockReturnValue(failed("no nodes"));
    await view().refresh();
    expect(view().error?.message).toBe("no nodes");
    get.mockReturnValue(failed("gone"));
    await view().refresh();
    expect(view().error?.message).toBe("gone");
    unmount();
  });

  it("waits without a run", async () => {
    const get = vi.fn(() => resolved<WorkflowRun | undefined>(undefined));

    const mounted = mount(
      createWorkflowCanvasRunController({
        client: { runs: { get }, nodeRuns: { list: () => resolved([]) } },
        auth: fakeAuth(),
        ports: { topic: fakeTopic().port },
        run: null,
      }),
    );

    await mounted.view().refresh();
    mounted.unmount();
    expect(get).not.toHaveBeenCalled();
  });
});
