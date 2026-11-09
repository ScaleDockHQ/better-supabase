import { describe, expect, it } from "vitest";

import { createPipelines } from "../../src/blocks/pipelines/pipelines.ts";

const pipeline = {
  id: "p1",
  tenant_id: "org-1",
  subject_type: "deal",
  key: "sales",
  name: "Sales",
  rank: "a",
  is_default: true,
  stages: [],
};

const stage = {
  id: "s1",
  pipeline_id: "p1",
  key: "new",
  name: "New",
  rank: "a",
  category: "open",
  outcome: "open",
};

function pipelines(fail?: string) {
  return createPipelines({
    transport: {
      call(_schema: string, fn: string) {
        if (fn === fail) {
          return Promise.reject(new Error(fn));
        }

        if (fn === "list_pipelines") {
          return Promise.resolve(fail === "empty" ? [] : [pipeline]);
        }

        if (fn === "save_pipeline_stage") {
          return Promise.resolve({
            ...stage,
            icon: "dot",
            color: "blue",
            probability: 10,
            rotting_after_days: 7,
            wip_limit: 3,
            system_key: "open",
          });
        }

        if (fn === "pipeline_board") {
          return Promise.resolve([
            {
              stageId: "s1",
              key: "new",
              name: "New",
              outcome: "open",
              count: 1,
              totals: [],
              color: "blue",
              icon: "dot",
              probability: 10,
              wipLimit: 3,
            },
            {
              stageId: "s2",
              key: "won",
              name: "Won",
              outcome: "success",
              count: null,
              totals: [],
            },
          ]);
        }

        if (fn === "set_pipeline_transitions") {
          return Promise.resolve(null);
        }

        return Promise.resolve({ ...pipeline, id: "p2", key: "next" });
      },
    },
  });
}

const input = {
  organizationId: "org-1",
  subjectType: "deal",
  key: "next",
  name: "Next",
};

describe("pipeline client", () => {
  it("returns a pipeline that already exists", async () => {
    const found = await pipelines().ensure({ ...input, key: "sales" });

    expect(found.ok ? found.data.id : found.error.message).toBe("p1");
  });

  it("creates a pipeline and its stages, and stops when a step fails", async () => {
    const created = await pipelines("empty").ensure({
      ...input,
      scopeId: "team-1",
      stages: [{ key: "new", name: "New", category: "open" }],
    });

    expect(created.ok ? created.data.key : created.error.message).toBe("next");

    expect((await pipelines("list_pipelines").ensure(input)).ok).toBe(false);
    expect((await pipelines("save_pipeline").ensure(input)).ok).toBe(false);
    expect((await pipelines("empty").ensure({ ...input, stages: [] })).ok).toBe(
      true,
    );
    expect(
      (
        await pipelines("save_pipeline_stage").ensure({
          ...input,
          stages: [{ key: "new", name: "New", category: "open" }],
        })
      ).ok,
    ).toBe(false);

    const client = pipelines();

    expect(
      (
        await client.list({
          organizationId: "org-1",
          subjectType: "deal",
          limit: 1,
        })
      ).ok,
    ).toBe(true);
    expect((await client.archiveStage({ stageId: "s1" })).ok).toBe(true);
    expect(
      (await client.archiveStage({ stageId: "s1", moveTo: "s2" })).ok,
    ).toBe(true);
    expect(
      (
        await client.setTransitions({
          pipelineId: "p1",
          transitions: [{ from: "new", to: "won" }],
        })
      ).ok,
    ).toBe(true);
    expect(
      (
        await client.board({
          subjectType: "deal",
          pipelineId: "p1",
          owner: "u1",
        })
      ).ok,
    ).toBe(true);
    expect(
      (
        await client.reorderStage({
          stageId: "s1",
          neighbors: { previous: "z", next: "a" },
        })
      ).ok,
    ).toBe(false);
    expect(
      (
        await client.saveStage({
          pipelineId: "p1",
          input: { key: "new", name: "New", category: "open" },
        })
      ).ok,
    ).toBe(true);

    const healthy = createPipelines({
      transport: {
        call(_schema: string, fn: string) {
          if (fn === "pipeline_health") {
            return Promise.resolve([
              {
                subjectType: "deal",
                subjectId: "d1",
                stageId: "s1",
                enteredAt: "2026-11-01T00:00:00Z",
                daysInStage: null,
                rotting: false,
              },
              {
                subjectType: "deal",
                subjectId: "d2",
                stageId: "s1",
                enteredAt: "2026-11-01T00:00:00Z",
                daysInStage: 4,
                rotting: true,
              },
            ]);
          }

          return Promise.resolve(true);
        },
      },
    });

    expect((await healthy.health("p1")).ok).toBe(true);

    let listed = 0;

    const reread = createPipelines({
      transport: {
        call(_schema: string, fn: string) {
          if (fn === "list_pipelines") {
            listed += 1;

            return listed === 1
              ? Promise.resolve([])
              : Promise.reject(new Error("reread"));
          }

          if (fn === "save_pipeline_stage") {
            return Promise.resolve(stage);
          }

          return Promise.resolve({ ...pipeline, id: "p2", key: "next" });
        },
      },
    });

    expect(
      (
        await reread.ensure({
          ...input,
          stages: [{ key: "new", name: "New", category: "open" }],
        })
      ).ok,
    ).toBe(false);
  });
});
