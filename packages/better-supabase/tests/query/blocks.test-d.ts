import type { SkipToken } from "@tanstack/query-core";

import { describe, expectTypeOf, it } from "vitest";

import type { AsyncResult } from "../../src/core/result.ts";
import type {
  MutationOptionsOf,
  QueryOptionsOf,
} from "../../src/query/queries.ts";

import { blockQueries } from "../../src/query/blocks.ts";

interface Task {
  readonly id: string;
}

declare const tasks: {
  listTasks(filter?: { readonly done?: boolean }): AsyncResult<Task[]>;
  getTask(id: string): AsyncResult<Task>;
  createTask(input: { readonly title: string }): AsyncResult<Task>;
  moveTask(id: string, position: number): AsyncResult<Task>;
  issueTask(id: string): AsyncResult<Task>;
  readonly label: string;
};

describe("blockQueries", () => {
  const queries = blockQueries({ tasks });

  it("types read methods as query options", () => {
    expectTypeOf(queries.tasks.listTasks).returns.toEqualTypeOf<
      QueryOptionsOf<Task[]>
    >();
    expectTypeOf(queries.tasks.getTask)
      .parameter(0)
      .toEqualTypeOf<string | SkipToken>();
  });

  it("types other methods as mutation options", () => {
    expectTypeOf(queries.tasks.createTask).returns.toEqualTypeOf<
      MutationOptionsOf<{ readonly title: string }, Task>
    >();
    expectTypeOf(queries.tasks.moveTask).returns.toEqualTypeOf<
      MutationOptionsOf<[id: string, position: number], Task>
    >();
    expectTypeOf(queries.tasks.issueTask).returns.toEqualTypeOf<
      MutationOptionsOf<string, Task>
    >();
    expectTypeOf(queries.tasks).not.toHaveProperty("label");
  });
});
