import { describe, expect, it } from "vitest";

import { mapDbError } from "../../src/core/errors.ts";
import { toProblem } from "../../src/core/problem.ts";
import {
  isStaleWrite,
  STALE_WRITE,
  STALE_WRITE_SQLSTATE,
  staleWriteError,
} from "../../src/core/stale-write.ts";

describe("STALE_WRITE", () => {
  it("is a conflict with its own hint", () => {
    const error = staleWriteError();

    expect(error.kind).toBe("conflict");
    expect(error.status).toBe(409);
    expect(error.hint).toBe(STALE_WRITE);
    expect(isStaleWrite(error)).toBe(true);
  });

  it("is what the module's SQLSTATE maps to", () => {
    const error = mapDbError({
      code: STALE_WRITE_SQLSTATE,
      message: "the work item changed since it was read",
      hint: STALE_WRITE,
    });

    expect(error.kind).toBe("conflict");
    expect(isStaleWrite(error)).toBe(true);
  });

  it("does not match another conflict", () => {
    const error = mapDbError({ code: "23505", message: "duplicate key" });

    expect(isStaleWrite(error)).toBe(false);
  });

  it("answers Problem Details with its own type", () => {
    const problem = toProblem(staleWriteError());

    expect(problem.type).toBe(
      "https://bettersupabase.com/problems/stale-write",
    );
    expect(problem.status).toBe(409);
    expect(problem.kind).toBe("conflict");
    expect(problem.hint).toBe(STALE_WRITE);
  });

  it("keeps the generic type for other conflicts", () => {
    const problem = toProblem(mapDbError({ code: "23505", message: "dup" }));

    expect(problem.type).toBe("about:blank");
  });
});
