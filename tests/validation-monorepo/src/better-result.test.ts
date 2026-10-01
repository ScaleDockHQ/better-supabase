import type { DbError } from "better-supabase";

import { Result as BetterResult } from "better-result";
import {
  AsyncResult,
  dbError,
  err,
  fromBetterResult,
  ok,
  toBetterResult,
} from "better-supabase";
import { describe, expect, it } from "vitest";

class AppError extends Error {
  readonly code: string;
  constructor(code: string) {
    super(code);
    this.code = code;
  }
}

describe("better-result 3.0.1 round trip", () => {
  it("keeps sync values and DbErrors", () => {
    const value = toBetterResult(ok({ id: "c1" }), BetterResult);
    const real = value as BetterResult<{ id: string }, DbError>;
    expect(real.isOk()).toBe(true);
    expect(real.map((row) => row.id).unwrap()).toBe("c1");
    expect(fromBetterResult(value)).toEqual(ok({ id: "c1" }));

    const missing = dbError("not_found", "No customer c1");
    const failed = toBetterResult(err(missing), BetterResult);
    expect((failed as BetterResult<never, DbError>).isErr()).toBe(true);
    expect(fromBetterResult(failed)).toEqual(err(missing));
  });

  it("maps errors both ways for async results", async () => {
    const failed = await toBetterResult(
      AsyncResult.err(dbError("forbidden", "Not yours")),
      BetterResult,
      (error) => new AppError(error.kind),
    );
    expect(failed.status).toBe("error");
    const back = fromBetterResult(failed, (error) =>
      dbError(
        "forbidden",
        error instanceof AppError ? error.code : String(error),
      ),
    );
    expect(back).toMatchObject({
      ok: false,
      error: { kind: "forbidden", message: "forbidden" },
    });

    const value = await toBetterResult(AsyncResult.ok(2), BetterResult);
    expect(fromBetterResult(value)).toEqual(ok(2));
  });
});
