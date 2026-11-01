import { describe, expect, it } from "vitest";

import { createPipelines } from "../../../src/blocks/pipelines/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const STAGE = {
  id: "s1",
  pipeline_id: "p1",
  key: "lead",
  system_key: "lead",
  name: "Lead",
  color: null,
  rank: "V",
  category: "open",
  outcome: "open",
  probability: 10,
  rotting_after_days: 14,
  wip_limit: null,
};

const PIPELINE = {
  id: "p1",
  tenant_id: "o",
  subject_type: "deal",
  scope_id: null,
  key: "default",
  name: "Default",
  rank: "V",
  is_default: true,
};

const STAGES = [{ key: "lead", name: "Lead", category: "open" }] as const;

describe("pipelines helpers", () => {
  it("default finds the default pipeline and ignores other scopes", async () => {
    const t = fieldsTransport({
      list_pipelines: () => [
        { ...PIPELINE, id: "p2", scope_id: "team-1", stages: [] },
        { ...PIPELINE, stages: [STAGE] },
      ],
    });

    const pipelines = createPipelines({ transport: t });

    const found = await pipelines
      .default({ organizationId: "o", subjectType: "deal" })
      .orThrow();

    expect(found?.id).toBe("p1");
  });

  it("ensure returns an existing pipeline without writing", async () => {
    const t = fieldsTransport({
      list_pipelines: () => [{ ...PIPELINE, stages: [STAGE] }],
    });

    const pipelines = createPipelines({ transport: t });

    const found = await pipelines
      .ensure({
        organizationId: "o",
        subjectType: "deal",
        key: "default",
        name: "Default",
        stages: STAGES,
      })
      .orThrow();

    expect(found.id).toBe("p1");
    expect(t.calls.map(([fn]) => fn)).toEqual(["list_pipelines"]);
  });

  it("ensure creates a missing pipeline with its stages", async () => {
    let listed = 0;

    const t = fieldsTransport({
      list_pipelines: () => {
        listed += 1;

        return listed === 1 ? [] : [{ ...PIPELINE, stages: [STAGE] }];
      },
      save_pipeline: () => PIPELINE,
      save_pipeline_stage: () => STAGE,
    });

    const pipelines = createPipelines({ transport: t });

    const made = await pipelines
      .ensure({
        organizationId: "o",
        subjectType: "deal",
        key: "default",
        name: "Default",
        stages: STAGES,
      })
      .orThrow();

    expect(made.stages).toHaveLength(1);
    expect(t.calls.map(([fn]) => fn)).toEqual([
      "list_pipelines",
      "save_pipeline",
      "save_pipeline_stage",
      "list_pipelines",
    ]);
  });
});
