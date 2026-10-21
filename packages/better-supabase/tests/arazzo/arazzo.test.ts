import { describe, expect, expectTypeOf, it } from "vitest";

import type {
  AnyArazzoDocument,
  ResourceOperationIds,
} from "../../src/arazzo/index.ts";
import type { SpecDiagnostic } from "../../src/spec/format.ts";

import {
  arazzoFormat,
  authWorkflow,
  createArazzo,
  createArazzoFormat,
  createThenGetWorkflows,
  defineWorkflow,
  paginationWorkflows,
} from "../../src/arazzo/index.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import { defineApi } from "../../src/spec/api.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { opaque, standard } from "../spec/helpers.ts";
import { problems, validatorFor } from "../standards/validator.ts";

type Json = Record<string, unknown>;

const betterSupabase = defineSupabase(schema);
const info = { title: "CRM", version: "1.0.0" };

const onboarding = defineWorkflow<ResourceOperationIds<"customers">>({
  id: "onboardCustomer",
  summary: "Create a customer and read it",
  description: "Two steps",
  inputs: standard({ type: "object", properties: { row: { type: "object" } } }),
  steps: [
    {
      id: "create",
      description: "Insert",
      operationId: "createCustomers",
      requestBody: "$inputs.row",
      successCriteria: ["$statusCode == 201"],
      outputs: { id: "$response.body#/id" },
    },
    {
      id: "get",
      operationId: "getCustomers",
      parameters: { id: "$steps.create.outputs.id" },
      outputs: { row: "$response.body" },
    },
  ],
  outputs: { row: "$steps.get.outputs.row" },
});

const api = defineApi(betterSupabase, {
  info: { ...info, summary: "Workflows", description: "CRM workflows" },
  resources: {
    customers: {},
    notes: { operations: ["list", "get"], pagination: "offset" },
  },
  routes: [
    {
      method: "post",
      path: "/sign-in",
      operationId: "signIn",
      input: standard({ type: "object" }),
      output: standard({ type: "object" }),
    },
  ],
  workflows: [
    onboarding,
    paginationWorkflows(),
    createThenGetWorkflows(),
    authWorkflow({ call: "getCustomers" }),
  ],
});

const codes = (diagnostics: readonly SpecDiagnostic[]) =>
  diagnostics.map((diagnostic) => diagnostic.code);

const step = (doc: AnyArazzoDocument, workflow: string, id: string) =>
  doc.workflows
    .find((each) => each.workflowId === workflow)
    ?.steps.find((each) => each.stepId === id);

describe("defineWorkflow", () => {
  it("types operationIds and converts inputs and criteria", () => {
    expectTypeOf<
      ResourceOperationIds<"customer_tags", "list">
    >().toEqualTypeOf<"listCustomerTags">();
    expectTypeOf<ResourceOperationIds<"a-b">>().toEqualTypeOf<
      "listAB" | "getAB" | "createAB" | "updateAB" | "deleteAB"
    >();
    defineWorkflow<ResourceOperationIds<"customers">>({
      id: "typed",
      // @ts-expect-error: not an operation of customers
      steps: [{ id: "a", operationId: "listNotes" }],
    });
    expect(onboarding.inputs).toEqual({
      type: "object",
      properties: { row: { type: "object" } },
    });
    expect(onboarding.steps[0]).toEqual({
      id: "create",
      description: "Insert",
      operationId: "createCustomers",
      requestBody: { payload: "$inputs.row" },
      successCriteria: [{ condition: "$statusCode == 201" }],
      outputs: { id: "$response.body#/id" },
    });
    expect(onboarding.steps[1]?.parameters).toEqual([
      { name: "id", value: "$steps.create.outputs.id" },
    ]);
  });

  it("keeps list parameters, Criterion Objects and the other targets", () => {
    const workflow = defineWorkflow({
      id: "mixed",
      inputs: { type: "object" },
      steps: [
        {
          id: "sub",
          workflowId: "other",
          parameters: [
            { name: "a", in: "query", value: 1 },
            { name: "b", value: 2 },
          ],
          successCriteria: [
            { condition: "$.ok", context: "$response.body", type: "jsonpath" },
          ],
          onSuccess: [{ name: "done", type: "end" }],
          onFailure: [{ name: "again", type: "retry", retryAfter: 1 }],
        },
        { id: "wait", channel: { id: "tableCustomers", action: "receive" } },
      ],
    });

    expect(workflow.steps[0]).toMatchObject({
      workflowId: "other",
      parameters: [
        { name: "a", in: "query", value: 1 },
        { name: "b", value: 2 },
      ],
      successCriteria: [
        { condition: "$.ok", context: "$response.body", type: "jsonpath" },
      ],
    });
    expect(workflow.steps[1]?.channel).toEqual({
      id: "tableCustomers",
      action: "receive",
    });
  });

  it("rejects Standard Schema inputs without JSON Schema", () => {
    expect(() =>
      defineWorkflow({ id: "x", inputs: opaque(), steps: [] }),
    ).toThrow(/Standard JSON Schema/);
  });
});

describe("arazzoFormat", () => {
  const rendered = api.render(arazzoFormat);
  const doc = rendered.document;

  it("renders 1.0 by default with the OpenAPI file as source", () => {
    expect(rendered.version).toBe("1.0");
    expect(rendered.fileName).toBe("arazzo.json");
    expect(doc.arazzo).toBe(SPEC_PINS.arazzo10);
    expect(doc.info).toEqual({
      title: "CRM",
      version: "1.0.0",
      summary: "Workflows",
      description: "CRM workflows",
    });
    expect(doc.sourceDescriptions).toEqual([
      { name: "api", url: "openapi.json", type: "openapi" },
    ]);
    expect(rendered.diagnostics).toEqual([]);
  });

  it("validates against the official 1.0 and 1.1 schemas", () => {
    expect(problems(validatorFor("arazzo-1.0.json"), doc)).toEqual([]);
    const v11 = api.render(arazzoFormat, { version: "1.1" }).document;
    expect(v11.arazzo).toBe(SPEC_PINS.arazzo11);
    expect(problems(validatorFor("arazzo-1.1.json"), v11)).toEqual([]);
    expect(problems(validatorFor("arazzo-1.1.json"), {})).not.toEqual([]);
  });

  it("infers parameter locations, content types and success criteria", () => {
    expect(step(doc, "onboardCustomer", "create")).toMatchObject({
      operationId: "createCustomers",
      requestBody: { contentType: "application/json", payload: "$inputs.row" },
      successCriteria: [{ condition: "$statusCode == 201" }],
    });
    expect(step(doc, "onboardCustomer", "get")).toMatchObject({
      parameters: [
        { name: "id", in: "path", value: "$steps.create.outputs.id" },
      ],
      successCriteria: [{ condition: "$statusCode == 200" }],
    });
  });

  it("builds a pagination workflow per cursor list", () => {
    const ids = doc.workflows.map((workflow) => workflow.workflowId);
    expect(ids).toContain("paginateCustomers");
    expect(ids).not.toContain("paginateNotes");
    expect(step(doc, "paginateCustomers", "nextPage")?.parameters).toEqual([
      { name: "size", in: "query", value: "$inputs.size" },
      {
        name: "after",
        in: "query",
        value: "$steps.firstPage.outputs.nextCursor",
      },
    ]);
  });

  it("builds create-then-get only where both exist", () => {
    const ids = doc.workflows.map((workflow) => workflow.workflowId);
    expect(ids).toContain("createThenGetCustomers");
    expect(ids).not.toContain("createThenGetNotes");
    expect(step(doc, "createThenGetCustomers", "create")?.outputs).toEqual({
      key: "$response.body#/id",
    });
  });

  it("builds the auth workflow with the approval branch", () => {
    const call = step(doc, "signInThenGetCustomers", "call");
    expect(call?.parameters).toEqual([
      {
        name: "Authorization",
        in: "header",
        value: "Bearer {$steps.signIn.outputs.accessToken}",
      },
      { name: "id", in: "path", value: "$inputs.id" },
    ]);
    expect(call?.onFailure?.[0]).toMatchObject({
      name: "approvalRequired",
      type: "end",
    });
    expect(step(doc, "signInThenGetCustomers", "signIn")?.outputs).toEqual({
      accessToken: "$response.body#/access_token",
    });
  });
});

describe("arazzoFormat: findings", () => {
  const render = (
    workflows: NonNullable<Parameters<typeof defineApi>[1]["workflows"]>,
    version: "1.0" | "1.1" = "1.0",
    extra: Partial<Parameters<typeof defineApi>[1]> = {},
  ) =>
    defineApi(betterSupabase, {
      info,
      resources: { customers: {} },
      workflows,
      ...extra,
    }).render(arazzoFormat, { version });

  it("reports unknown operations and missing parameter locations", () => {
    const { diagnostics } = render([
      defineWorkflow({
        id: "bad",
        steps: [
          { id: "a", operationId: "nope", parameters: { x: 1 } },
          { id: "b", operationId: "getCustomers", parameters: { y: 1 } },
        ],
      }),
      authWorkflow({ call: "missing", signIn: "alsoMissing", id: "auth" }),
    ]);

    expect(codes(diagnostics)).toEqual(
      expect.arrayContaining([
        "arazzo-operation-unknown",
        "arazzo-parameter-in-missing",
      ]),
    );
  });

  it("reports an empty document", () => {
    expect(codes(render([]).diagnostics)).toEqual(["arazzo-workflows-empty"]);
  });

  it("allows channel steps only in 1.1, against the AsyncAPI source", () => {
    const workflows = [
      defineWorkflow({
        id: "listen",
        steps: [
          { id: "list", operationId: "listCustomers" },
          {
            id: "wait",
            channel: {
              id: "tableCustomers",
              action: "receive",
              correlationId: "$message.payload#/table",
            },
          },
          { id: "lost", channel: { id: "missing", action: "send" } },
        ],
      }),
    ];

    const v10 = render(workflows, "1.0", { events: {} });
    expect(codes(v10.diagnostics)).toContain("arazzo-channel-step-unsupported");
    expect(v10.document.workflows[0]?.steps.map((each) => each.stepId)).toEqual(
      ["list"],
    );
    expect(v10.document.sourceDescriptions).toHaveLength(1);

    const v11 = render(workflows, "1.1", { events: {} });
    expect(v11.document.sourceDescriptions).toEqual([
      { name: "api", url: "openapi.json", type: "openapi" },
      { name: "events", url: "asyncapi.json", type: "asyncapi" },
    ]);
    expect(v11.document.workflows[0]?.steps[0]?.operationId).toBe(
      "$sourceDescriptions.api.listCustomers",
    );
    expect(v11.document.workflows[0]?.steps[1]).toMatchObject({
      channelPath: "{$sourceDescriptions.events.url}#/channels/tableCustomers",
      action: "receive",
      correlationId: "$message.payload#/table",
    });
    expect(codes(v11.diagnostics)).toContain("arazzo-channel-unknown");
  });

  it("uses only the AsyncAPI source for channel-only workflows", () => {
    const format = createArazzoFormat({
      openapi: { name: "rest", url: "https://api.test/openapi.json" },
      asyncapi: { name: "rt", url: "https://api.test/asyncapi.json" },
    });

    const { document } = defineApi(betterSupabase, {
      info,
      events: {},
      workflows: [
        defineWorkflow({
          id: "wait",
          steps: [
            { id: "w", channel: { id: "tableCustomers", action: "receive" } },
          ],
        }),
      ],
    }).render(format, { version: "1.1" });

    expect(document.sourceDescriptions).toEqual([
      { name: "rt", url: "https://api.test/asyncapi.json", type: "asyncapi" },
    ]);
    expect(document.workflows[0]?.steps[0]?.channelPath).toBe(
      "{$sourceDescriptions.rt.url}#/channels/tableCustomers",
    );
  });

  it("strips action parameters in 1.0 and keeps them in 1.1", () => {
    const workflows = [
      defineWorkflow({
        id: "next",
        steps: [
          {
            id: "a",
            operationId: "listCustomers",
            onSuccess: [
              { name: "go", type: "goto", workflowId: "next", parameters: [] },
            ],
            onFailure: [{ name: "stop", type: "end", parameters: [] }],
          },
        ],
      }),
    ];

    const v10 = render(workflows);
    expect(codes(v10.diagnostics)).toEqual([
      "arazzo-action-parameters-unsupported",
      "arazzo-action-parameters-unsupported",
    ]);
    expect(
      v10.document.workflows[0]?.steps[0]?.onSuccess?.[0],
    ).not.toHaveProperty("parameters");
    const v11 = render(workflows, "1.1");
    expect(v11.diagnostics).toEqual([]);
    expect(v11.document.workflows[0]?.steps[0]?.onSuccess?.[0]).toHaveProperty(
      "parameters",
    );
  });

  it("uses the model's self as the OpenAPI URL", () => {
    const { document } = render([onboarding], "1.0", {
      self: "https://api.test/openapi.json",
    });

    expect(document.sourceDescriptions[0]?.url).toBe(
      "https://api.test/openapi.json",
    );
  });
});

describe("arazzoFormat: lint", () => {
  const lint = (doc: unknown) =>
    codes(arazzoFormat.lint?.(doc as AnyArazzoDocument, "1.0") ?? []);

  const base = (workflows: Json[]): Json => ({
    arazzo: SPEC_PINS.arazzo10,
    info,
    sourceDescriptions: [{ name: "api", url: "openapi.json", type: "openapi" }],
    workflows,
  });

  it("finds duplicate and invalid ids", () => {
    expect(
      lint(
        base([
          {
            workflowId: "w",
            steps: [
              { stepId: "a", operationId: "x" },
              { stepId: "a", operationId: "x" },
            ],
          },
          { workflowId: "w", steps: [{ stepId: "b c", operationId: "x" }] },
          { workflowId: "bad id", steps: [{ stepId: "d", operationId: "x" }] },
        ]),
      ),
    ).toEqual([
      "arazzo-workflow-id-duplicate",
      "arazzo-id-invalid",
      "arazzo-step-id-duplicate",
      "arazzo-id-invalid",
    ]);
  });

  it("finds steps with no target or two, and unknown workflows", () => {
    expect(
      lint(
        base([
          {
            workflowId: "w",
            steps: [
              { stepId: "a" },
              { stepId: "b", operationId: "x", workflowId: "w" },
              { stepId: "c", workflowId: "missing" },
            ],
          },
        ]),
      ),
    ).toEqual([
      "arazzo-step-target",
      "arazzo-step-target",
      "arazzo-workflow-unknown",
    ]);
  });

  it("checks step outputs, inputs, sources and goto targets", () => {
    expect(
      lint(
        base([
          {
            workflowId: "w",
            inputs: { type: "object", properties: { id: { type: "string" } } },
            steps: [
              {
                stepId: "a",
                operationId: "$sourceDescriptions.other.x",
                parameters: [
                  { name: "p", in: "query", value: "$steps.b.outputs.v" },
                  { name: "q", in: "query", value: "$inputs.nope" },
                  { name: "r", in: "query", value: "$inputs.id" },
                ],
                outputs: { v: "$response.body" },
                onSuccess: [
                  { name: "g", type: "goto", stepId: "missing" },
                  { name: "h", type: "goto", workflowId: "nowhere" },
                  {
                    name: "i",
                    type: "goto",
                    workflowId: "$sourceDescriptions.api.w",
                  },
                  { name: "j", type: "end" },
                ],
              },
              {
                stepId: "b",
                operationId: "x",
                parameters: [
                  { name: "p", in: "query", value: "$steps.a.outputs.missing" },
                ],
                outputs: { v: "$response.body" },
              },
            ],
            outputs: { v: "$steps.b.outputs.v", w: "$steps.zz.outputs.v" },
          },
        ]),
      ),
    ).toEqual([
      "arazzo-source-unknown",
      "arazzo-step-output-order",
      "arazzo-input-undeclared",
      "arazzo-goto-unknown",
      "arazzo-goto-unknown",
      "arazzo-step-output-unknown",
      "arazzo-step-output-unknown",
    ]);
  });
});

describe("createArazzo", () => {
  it("returns the document, with sources from the options", () => {
    const heard: string[] = [];

    const doc = createArazzo(betterSupabase, {
      info,
      resources: { customers: {} },
      workflows: [createThenGetWorkflows({ tables: ["customers"] })],
      openapi: { url: "https://api.test/openapi.json" },
      asyncapi: { url: "https://api.test/asyncapi.json" },
      onDiagnostic: (diagnostic) => heard.push(diagnostic.code),
    });

    expect(doc.arazzo).toBe(SPEC_PINS.arazzo10);
    expect(doc.sourceDescriptions[0]?.url).toBe(
      "https://api.test/openapi.json",
    );
    expect(doc.workflows.map((workflow) => workflow.workflowId)).toEqual([
      "createThenGetCustomers",
    ]);
    expect(heard).toEqual([]);
  });

  it("renders 1.1 and runs transform", () => {
    const doc = createArazzo(betterSupabase, {
      info,
      version: "1.1",
      resources: { customers: { pagination: "cursor" } },
      workflows: [paginationWorkflows({ tables: ["customers"] })],
      transform: ({ version, document }) => {
        expect(version).toBe("1.1");

        return { ...document, info: { ...document.info, title: "Changed" } };
      },
      overlays: [],
    });

    expect(doc.arazzo).toBe(SPEC_PINS.arazzo11);
    expect(doc.info.title).toBe("Changed");
  });

  it("throws on errors", () => {
    expect(() => createArazzo(betterSupabase, { info })).toThrow(
      /createArazzo: arazzo-workflows-empty/,
    );
  });
});
