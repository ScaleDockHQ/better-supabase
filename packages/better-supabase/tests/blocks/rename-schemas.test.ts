import { describe, expect, it } from "vitest";

import type { EntitySchema } from "../../src/blocks/entity-schema.ts";

import { renameSchemas } from "../../src/blocks/rename-schemas.ts";
import { entityNames } from "../../src/core/entity-naming.ts";

const names = entityNames([
  {
    from: { singular: "task", plural: "tasks" },
    to: { singular: "job", plural: "jobs" },
  },
]);

const translate = {
  forward: (value: unknown) => ({ forwarded: value }),
  back: (value: unknown) => ({ back: value }),
};

const schemaOf = (
  validate: (input: unknown) => unknown,
  title?: string,
): EntitySchema<unknown> =>
  // SAFETY: the test schema carries only the members renameSchemas reads.
  ({
    spec: {
      ...(title === undefined ? {} : { title }),
      fields: { task_id: { type: "uuid" } },
    },
    "~standard": {
      version: 1,
      vendor: "test",
      validate,
      jsonSchema: {
        input: () => ({
          title: "task",
          required: ["task_id", 1],
          properties: { task_id: { title: "task id" } },
          anyOf: [{ title: "task" }, "x"],
        }),
        output: () => ["not", "a", "record"],
      },
    },
  }) as unknown as EntitySchema<unknown>;

describe("renameSchemas", () => {
  it("renames entity keys, fields, titles and JSON Schema names", () => {
    const renamed = renameSchemas(
      {
        task: {
          input: schemaOf((input) => ({ value: input }), "task"),
          change: schemaOf((input) => ({ value: input })),
        },
      },
      names,
      translate,
    );

    const input = renamed["job"]?.input;

    expect(Object.keys(renamed)).toEqual(["job"]);
    expect(renamed["job"]?.listFilter).toBeUndefined();
    expect(input?.spec.title).toBe("job");
    expect(Object.keys(input?.spec.fields ?? {})).toEqual(["job_id"]);
    expect(renamed["job"]?.change?.spec.title).toBeUndefined();
    expect(
      input?.["~standard"].jsonSchema.input({ target: "draft-2020-12" }),
    ).toEqual({
      title: "job",
      required: ["job_id", 1],
      properties: { job_id: { title: "job id" } },
      anyOf: [{ title: "job" }, "x"],
    });
    expect(
      input?.["~standard"].jsonSchema.output({ target: "draft-2020-12" }),
    ).toEqual({});
    expect(input?.["~standard"].validate({ job_id: "1" })).toEqual({
      value: { forwarded: { back: { job_id: "1" } } },
    });
  });

  it("renames issue paths, also of an async validation", async () => {
    const issues = {
      issues: [{ message: "bad", path: ["task_id", 0] }, { message: "no" }],
    };

    const renamed = renameSchemas(
      {
        task: {
          input: schemaOf(() => issues),
          change: schemaOf(() => Promise.resolve(issues)),
        },
      },
      names,
      translate,
    );

    const expected = {
      issues: [
        { message: "bad", path: ["job_id", 0] },
        { message: "no", path: [] },
      ],
    };

    expect(renamed["job"]?.input?.["~standard"].validate({})).toEqual(expected);
    expect(await renamed["job"]?.change?.["~standard"].validate({})).toEqual(
      expected,
    );
  });
});
