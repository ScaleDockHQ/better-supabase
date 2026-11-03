import * as v from "valibot";
import { describe, expectTypeOf, it } from "vitest";

import type {
  Workflows,
  WorkflowRun,
} from "../../../src/blocks/workflows/workflows.ts";

import { createWorkflows } from "../../../src/blocks/workflows/workflows.ts";
import { rpcTransport } from "../../../src/core/block-transport.ts";

const transport = rpcTransport({} as never);

describe("createWorkflows fields", () => {
  it("types the extra run columns from the schema", () => {
    const workflows = createWorkflows({
      transport,
      fields: v.object({ region: v.string() }),
    });

    expectTypeOf(workflows).toEqualTypeOf<Workflows<{ region: string }>>();
    expectTypeOf(workflows.runs.get("r1").orThrow()).resolves.toEqualTypeOf<
      WorkflowRun<{ region: string }> | undefined
    >();
  });

  it("keeps the run's fields open without a schema", () => {
    const workflows = createWorkflows({ transport });

    expectTypeOf(workflows).toEqualTypeOf<Workflows>();
  });
});
