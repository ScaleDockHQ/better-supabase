import type {
  StandardJSONSchemaV1,
  StandardSchemaV1,
} from "@standard-schema/spec";

import { describe, expect, it } from "vitest";

import { validate } from "../../src/core/standard.ts";
import { envSchema } from "../../src/env/index.ts";
import { defineTool } from "../../src/mcp/index.ts";

/** A schema written against the spec alone, with no validator library. */
function handRolled(
  check: (value: unknown) => StandardSchemaV1.Result<{ name: string }>,
  async = false,
): StandardSchemaV1<unknown, { name: string }> {
  return {
    "~standard": {
      version: 1,
      vendor: "hand-rolled",
      validate: (value) =>
        async ? Promise.resolve(check(value)) : check(value),
    },
  };
}

const nameCheck = (
  value: unknown,
): StandardSchemaV1.Result<{ name: string }> =>
  typeof value === "object" &&
  value !== null &&
  typeof (value as { name?: unknown }).name === "string"
    ? { value: { name: (value as { name: string }).name.trim() } }
    : { issues: [{ message: "Expected a name", path: [{ key: "name" }] }] };

describe("Standard Schema v1", () => {
  it("uses the schema's output value, not the input", async () => {
    const result = await validate(handRolled(nameCheck), { name: "  Ada " });
    expect(result).toMatchObject({ ok: true, data: { name: "Ada" } });
  });

  it("awaits a schema whose validate returns a Promise", async () => {
    const result = await validate(handRolled(nameCheck, true), { name: "Ada" });
    expect(result.ok && result.data).toEqual({ name: "Ada" });
  });

  it("maps issues, flattening PathSegment objects to their keys", async () => {
    const result = await validate(handRolled(nameCheck), {}, "input");
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toMatchObject({
      kind: "validation",
      message: "Invalid input",
      issues: [{ message: "Expected a name", path: ["name"] }],
    });
  });

  it("drops an empty path rather than reporting path: []", async () => {
    const schema = handRolled(() => ({
      issues: [{ message: "Nope", path: [] }],
    }));
    const result = await validate(schema, 1);
    expect(!result.ok && (result.error as { issues?: unknown }).issues).toEqual(
      [{ message: "Nope" }],
    );
  });

  it("envSchema() is itself a Standard Schema", () => {
    const schema = envSchema();
    const props = schema["~standard"];
    expect(props.version).toBe(1);
    expect(props.vendor).toBe("better-supabase");
    const bad = props.validate("not an object");
    expect(bad).toEqual({
      issues: [{ message: "Expected an environment object" }],
    });
    const missing = props.validate({});
    expect(missing).toHaveProperty("issues");
    if (missing instanceof Promise || !missing.issues)
      throw new Error("expected issues");
    for (const issue of missing.issues) {
      expect(typeof issue.message).toBe("string");
      expect(issue.path?.every((segment) => typeof segment === "string")).toBe(
        true,
      );
    }
  });
});

describe("Standard JSON Schema v1", () => {
  const withJsonSchema = (
    input: (options: StandardJSONSchemaV1.Options) => Record<string, unknown>,
  ): StandardSchemaV1<unknown, { name: string }> => {
    const base = handRolled(nameCheck)["~standard"];
    return {
      "~standard": {
        ...base,
        jsonSchema: { input, output: input },
      } as StandardSchemaV1.Props<unknown, { name: string }>,
    };
  };

  it("asks the schema for draft 2020-12 and drops $schema from the tool inputSchema", () => {
    const targets: string[] = [];
    const tool = defineTool({
      name: "greet",
      description: "Greets",
      input: withJsonSchema((options) => {
        targets.push(options.target);
        return {
          $schema: "https://json-schema.org/draft/2020-12/schema",
          type: "object",
          properties: { name: { type: "string" } },
          required: ["name"],
        };
      }),
      run: (args) => args.name,
    });
    expect(targets).toEqual(["draft-2020-12"]);
    expect(tool.info.inputSchema).toEqual({
      type: "object",
      properties: { name: { type: "string" } },
      required: ["name"],
    });
  });

  it("refuses a Standard Schema without JSON Schema unless inputSchema is passed", () => {
    expect(() =>
      defineTool({
        name: "greet",
        description: "Greets",
        input: handRolled(nameCheck),
        run: () => "",
      }),
    ).toThrow(/has no JSON Schema/);
    const tool = defineTool({
      name: "greet",
      description: "Greets",
      input: handRolled(nameCheck),
      inputSchema: { type: "object" },
      run: () => "",
    });
    expect(tool.info.inputSchema).toEqual({ type: "object" });
  });
});
