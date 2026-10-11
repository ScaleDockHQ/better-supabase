import { describe, expect, it } from "vitest";

import {
  arazzoFormat,
  authWorkflow,
  createThenGetWorkflows,
  paginationWorkflows,
} from "../../src/arazzo/index.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import { defineApi } from "../../src/spec/api.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { problems, validatorFor } from "./validator.ts";

const workflows = defineApi(defineSupabase(schema), {
  info: { title: "CRM workflows", version: "1.0.0" },
  resources: { customers: { pagination: "cursor" } },
  workflows: [
    paginationWorkflows(),
    createThenGetWorkflows(),
    authWorkflow({ call: "listCustomers", signIn: "listCustomers" }),
  ],
});

/** The smallest Arazzo document: one workflow calling one OpenAPI operation. */
const minimal = (arazzo: string) => ({
  arazzo,
  info: { title: "CRM workflows", version: "1.0.0" },
  sourceDescriptions: [
    { name: "crm", url: "https://api.test/openapi.json", type: "openapi" },
  ],
  workflows: [
    {
      workflowId: "listCustomers",
      steps: [{ stepId: "list", operationId: "listCustomers" }],
    },
  ],
});

describe.each([
  [SPEC_PINS.arazzo10, "arazzo-1.0.json", SPEC_PINS.arazzo11],
  [SPEC_PINS.arazzo11, "arazzo-1.1.json", SPEC_PINS.arazzo10],
] as const)("Arazzo %s", (pin, file, other) => {
  it("the pin is the version the vendored schema accepts", () => {
    expect(problems(validatorFor(file), minimal(pin))).toEqual([]);
    expect(problems(validatorFor(file), minimal(other))).not.toEqual([]);
  });

  it("arazzoFormat renders a document the vendored schema accepts", () => {
    const version = pin === SPEC_PINS.arazzo10 ? "1.0" : "1.1";
    const { document, diagnostics } = workflows.render(arazzoFormat, {
      version,
    });
    expect(diagnostics.filter((d) => d.severity === "error")).toEqual([]);
    expect(document.arazzo).toBe(pin);
    expect(document.workflows.length).toBeGreaterThan(1);
    expect(problems(validatorFor(file), document)).toEqual([]);
  });

  it("the schema rejects a workflow without steps", () => {
    const document = minimal(pin);
    expect(
      problems(validatorFor(file), {
        ...document,
        workflows: [{ workflowId: "empty", steps: [] }],
      }),
    ).not.toEqual([]);
  });
});
