import * as v from "valibot";
import { describe, expect, it } from "vitest";

import {
  createTemplates,
  defineTemplateType,
  TEMPLATES_APPLY_STEP,
  templatesApplyStep,
} from "../../../src/blocks/templates/index.ts";
import { AsyncResult } from "../../../src/core/result.ts";

function transport(
  results: Record<string, (args: Record<string, unknown>) => unknown>,
) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    call(schema: string, fn: string, args: Record<string, unknown>) {
      expect(schema).toBe("better_supabase");
      calls.push([fn, args]);
      const result = results[fn];

      if (!result) {
        return Promise.reject(new Error(`unexpected ${fn}`));
      }

      return Promise.resolve(result(args));
    },
  };
}

const AT = "2026-10-06T09:00:00Z";

const TEMPLATE = {
  id: "t1",
  tenant: "o",
  scope: "tenant",
  key: null,
  type: "project",
  name: "Launch",
  language: "en",
  isDefault: false,
  settings: { color: "blue" },
  forkedFrom: "s1",
  forkedFromVersion: 2,
  publishedVersion: 1,
  upstreamVersion: 3,
  createdBy: "u1",
  createdAt: AT,
  updatedAt: AT,
};

const VERSION = {
  id: "v1",
  template: "t1",
  version: 1,
  hash: "abc",
  publishedAt: AT,
  createdBy: "u1",
  createdAt: AT,
  body: { tasks: ["Kickoff"] },
};

const APPLICATION = {
  id: "a1",
  template: "t1",
  version: "v1",
  tenant: "o",
  subjectType: "project",
  subjectId: "p1",
  appliedBy: "u1",
  appliedAt: AT,
};

const applied: { color: string; tasks: string[] }[] = [];

const project = defineTemplateType({
  settings: v.object({ color: v.string() }),
  body: v.object({ tasks: v.array(v.string()) }),
  apply: (call) => {
    applied.push({ color: call.settings.color, tasks: call.body.tasks });

    return { subject: { type: "project", id: "p1" } };
  },
});

describe("templates client", () => {
  it("maps templates and flags a fork that is behind its source", async () => {
    const fake = transport({ templates_list: () => [TEMPLATE] });
    const templates = createTemplates({ transport: fake });

    const [row] = await templates
      .list({ organizationId: "o", filter: { type: "project" } })
      .orThrow();

    expect(row).toMatchObject({
      organizationId: "o",
      scope: "tenant",
      key: undefined,
      behind: true,
      settings: { color: "blue" },
    });
    expect(row?.createdAt).toBeInstanceOf(Temporal.Instant);
    expect(fake.calls[0]).toEqual([
      "templates_list",
      { tenant: "o", type: "project", language: null },
    ]);
  });

  it("checks settings and bodies against the type's schemas", async () => {
    const fake = transport({
      save_template: () => TEMPLATE,
      template_get: () => ({ ...TEMPLATE, published: VERSION, draft: null }),
      save_template_draft: () => ({
        ...VERSION,
        version: 2,
        publishedAt: null,
      }),
    });

    const templates = createTemplates({ transport: fake, types: { project } });

    const bad = await templates.upsert({
      organizationId: "o",
      type: "project",
      name: "Launch",
      settings: { color: 3 },
    });

    expect(bad.ok ? undefined : bad.error.kind).toBe("validation");
    expect(fake.calls).toHaveLength(0);

    const badBody = await templates.versions.upsert({
      template: "t1",
      body: { tasks: "no" },
    });

    expect(badBody.ok ? undefined : badBody.error.kind).toBe("validation");

    const draft = await templates.versions
      .upsert({ template: "t1", body: { tasks: ["A"] } })
      .orThrow();

    expect(draft.publishedAt).toBeUndefined();
    expect(fake.calls.at(-1)).toEqual([
      "save_template_draft",
      { template_id: "t1", body: { tasks: ["A"] } },
    ]);
  });

  it("applies a template, records it and starts its workflows on the record", async () => {
    const fake = transport({
      template_apply_target: () => ({
        template: TEMPLATE,
        version: VERSION,
        workflows: [{ definition: "d1", inputs: { owner: "u1" } }],
      }),
      record_template_application: () => APPLICATION,
    });

    const runs: unknown[] = [];

    const templates = createTemplates({
      transport: fake,
      types: { project },
      workflows: {
        run: (input) => {
          runs.push(input);

          return AsyncResult.ok("run-1");
        },
      },
    });

    const result = await templates
      .apply({ template: "t1", options: { into: "o" } })
      .orThrow();

    expect(applied.at(-1)).toEqual({ color: "blue", tasks: ["Kickoff"] });
    expect(result.subject).toEqual({ type: "project", id: "p1" });
    expect(result.application.subject).toEqual({ type: "project", id: "p1" });
    expect(result.runs).toEqual([{ definition: "d1", runId: "run-1" }]);
    expect(runs).toEqual([
      {
        definition: "d1",
        input: { owner: "u1" },
        subject: { type: "project", id: "p1" },
        tenant: "o",
        idempotencyKey: "template-application:a1:d1",
      },
    ]);
    expect(fake.calls[1]).toEqual([
      "record_template_application",
      {
        template_id: "t1",
        version_id: "v1",
        tenant: "o",
        subject_type: "project",
        subject_id: "p1",
      },
    ]);
  });

  it("refuses to apply without a handler, or with workflows and no builder", async () => {
    const target = transport({
      template_apply_target: () => ({
        template: TEMPLATE,
        version: VERSION,
        workflows: [{ definition: "d1", inputs: {} }],
      }),
    });

    const none = await createTemplates({ transport: target }).apply({
      template: "t1",
      options: { into: "o" },
    });

    expect(none.ok ? undefined : none.error.kind).toBe("invalid_request");

    const noBuilder = await createTemplates({
      transport: target,
      types: { project },
    }).apply({ template: "t1", options: { into: "o" } });

    expect(noBuilder.ok ? undefined : noBuilder.error.message).toMatch(
      /workflows/,
    );
  });

  it("returns the handler's throw as an error and records nothing", async () => {
    const fake = transport({
      template_apply_target: () => ({
        template: TEMPLATE,
        version: VERSION,
        workflows: [],
      }),
    });

    const templates = createTemplates({
      transport: fake,
      types: {
        project: defineTemplateType({
          apply: () => {
            throw new Error("boom");
          },
        }),
      },
    });

    const result = await templates.apply({
      template: "t1",
      options: { into: "o" },
    });

    expect(result.ok).toBe(false);
    expect(fake.calls.map(([fn]) => fn)).toEqual(["template_apply_target"]);
  });

  it("maps brand templates and syncs brand starters", async () => {
    const fake = transport({
      templates_list: () => [
        { ...TEMPLATE, tenant: null, scope: "brand", brand: "acme" },
      ],
      sync_templates: () => 1,
    });

    const templates = createTemplates({ transport: fake, types: { project } });
    const [row] = await templates.list({ organizationId: "o" }).orThrow();
    expect(row).toMatchObject({ scope: "brand", brand: "acme" });

    await templates
      .sync([
        {
          key: "launch",
          brand: "acme",
          type: "project",
          name: "Launch",
          settings: { color: "red" },
          body: { tasks: [] },
        },
      ])
      .orThrow();

    expect(fake.calls[1]?.[1]).toMatchObject({
      starters: [{ key: "launch", brand: "acme" }],
    });
  });

  it("validates starters before syncing them", async () => {
    const fake = transport({ sync_templates: () => 2 });
    const templates = createTemplates({ transport: fake, types: { project } });

    const bad = await templates.sync([
      { key: "launch", type: "project", name: "Launch", body: { tasks: 1 } },
    ]);

    expect(bad.ok).toBe(false);

    const count = await templates
      .sync([
        {
          key: "launch",
          type: "project",
          name: "Launch",
          settings: { color: "red" },
          body: { tasks: [] },
        },
      ])
      .orThrow();

    expect(count).toBe(2);
    expect(fake.calls[0]?.[1]).toEqual({
      starters: [
        {
          key: "launch",
          type: "project",
          name: "Launch",
          settings: { color: "red" },
          body: { tasks: [] },
        },
      ],
    });
  });

  it("removes, defaults, forks, publishes and lists versions, workflows and applications", async () => {
    const WORKFLOW = {
      id: "w1",
      template: "t1",
      definition: "d1",
      inputs: { notify: true },
      enabled: true,
      createdBy: "u1",
      createdAt: AT,
    };

    const fake = transport({
      remove_template: () => true,
      set_default_template: () => true,
      fork_template: () => ({ ...TEMPLATE, id: "t2" }),
      publish_template_version: () => VERSION,
      template_versions_list: () => [VERSION],
      attach_template_workflow: () => WORKFLOW,
      detach_template_workflow: () => true,
      template_workflows_list: () => [{ ...WORKFLOW, enabled: false }],
      template_applications_list: () => [APPLICATION],
    });

    const templates = createTemplates({ transport: fake });

    expect(await templates.remove("t1").orThrow()).toBe(true);
    expect(await templates.setDefault({ id: "t1" }).orThrow()).toBe(true);
    expect(
      (await templates.fork({ source: "s1", organizationId: "o" }).orThrow())
        .id,
    ).toBe("t2");
    expect((await templates.versions.publish("t1").orThrow()).version).toBe(1);
    expect(await templates.versions.list("t1").orThrow()).toHaveLength(1);
    expect(
      await templates.workflows
        .attach({ template: "t1", definition: "d1" })
        .orThrow(),
    ).toMatchObject({
      definition: "d1",
      inputs: { notify: true },
      enabled: true,
    });
    expect(
      await templates.workflows
        .detach({ template: "t1", definition: "d1" })
        .orThrow(),
    ).toBe(true);
    const [workflow] = await templates.workflows.list("t1").orThrow();
    expect(workflow?.enabled).toBe(false);

    const [application] = await templates.applications
      .list({
        organizationId: "o",
        filter: { template: "t1", subject: { type: "project", id: "p1" } },
      })
      .orThrow();

    expect(application).toMatchObject({
      organizationId: "o",
      subject: { type: "project", id: "p1" },
    });

    expect(fake.calls.map(([fn, args]) => [fn, args])).toEqual([
      ["remove_template", { template_id: "t1" }],
      ["set_default_template", { template_id: "t1", on_default: true }],
      ["fork_template", { source: "s1", tenant: "o" }],
      ["publish_template_version", { template_id: "t1" }],
      ["template_versions_list", { template_id: "t1" }],
      [
        "attach_template_workflow",
        { template_id: "t1", definition: "d1", inputs: {}, enabled: true },
      ],
      ["detach_template_workflow", { template_id: "t1", definition: "d1" }],
      ["template_workflows_list", { template_id: "t1" }],
      [
        "template_applications_list",
        {
          tenant: "o",
          template_id: "t1",
          subject_type: "project",
          subject_id: "p1",
        },
      ],
    ]);
  });
});

describe("templates.apply step", () => {
  it("describes its config and checks templates.apply at publish", () => {
    expect(TEMPLATES_APPLY_STEP).toMatchObject({
      name: "templates.apply",
      operation: "templates.apply",
    });
  });

  it("applies into the run's tenant with a key per run and node", async () => {
    const fake = transport({
      template_apply_target: () => ({
        template: TEMPLATE,
        version: VERSION,
        workflows: [],
      }),
      record_template_application: () => APPLICATION,
    });

    const keys: (string | undefined)[] = [];

    const templates = createTemplates({
      transport: fake,
      types: {
        project: defineTemplateType({
          apply: (call) => {
            keys.push(call.key);
            expect(call.values).toEqual({ month: "October" });

            return { subject: { type: "project", id: "p1" } };
          },
        }),
      },
    });

    const step = templatesApplyStep(templates);

    const output = await step({
      node: "n1",
      step: "templates.apply",
      config: { template: "t1", values: { month: "October" } },
      input: {},
      results: {},
      runKey: "run-9",
      tenant: "o",
    });

    expect(output).toEqual({
      applicationId: "a1",
      subject: { type: "project", id: "p1" },
      runs: [],
    });
    expect(keys).toEqual(["run-9:n1"]);
  });

  it("fails the node without a template or a tenant", async () => {
    const step = templatesApplyStep(
      createTemplates({ transport: transport({}) }),
    );

    const base = {
      node: "n",
      step: "templates.apply",
      input: {},
      results: {},
      runKey: "r",
    };

    await expect(step({ ...base, config: {}, tenant: "o" })).rejects.toThrow(
      /config.template/,
    );
    await expect(step({ ...base, config: { template: "t1" } })).rejects.toThrow(
      /tenant/,
    );
  });
});
