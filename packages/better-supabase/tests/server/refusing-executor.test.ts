import { describe, expect, it } from "vitest";

import type { Operation } from "../../src/ir/types.ts";

import { dbError } from "../../src/core/errors.ts";
import { refusingExecutor } from "../../src/server/refusing-executor.ts";

describe("refusingExecutor", () => {
  const error = dbError("unauthorized", "Credentials did not verify");
  const executor = refusingExecutor(error);
  const context = { errorMappers: [] };

  it("answers the error to every operation, function call and batch", async () => {
    // SAFETY: the refusing executor never reads the operation.
    const op = {} as Operation;
    expect(await executor.execute(op, context)).toMatchObject({
      ok: false,
      error,
    });
    expect(
      await executor.rpc!("fn", {}, { ...context, schema: "public" }),
    ).toMatchObject({ ok: false, error });
    expect(await executor.batch!([op, op], context)).toMatchObject([
      { ok: false, error },
      { ok: false, error },
    ]);
  });

  it("reports the refusal for function sources too", () => {
    expect(executor.functionSources).toBe(true);
  });
});
