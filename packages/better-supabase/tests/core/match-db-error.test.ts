import { describe, expect, it } from "vitest";

import { DbException, dbError, matchDbError } from "../../src/core/errors.ts";
import { AsyncResult } from "../../src/core/result.ts";

class ConflictError extends Error {}

class InvalidError extends Error {}

describe("matchDbError", () => {
  const toAppError = matchDbError({
    conflict: (error) => new ConflictError(error.constraint),
    not_found: () => undefined,
    codes: { "23514": (error) => new InvalidError(error.message) },
  });

  it("maps by kind", () => {
    const error = dbError("conflict", "taken", {
      constraint: "users_email_key",
    });

    const mapped = toAppError(error);

    expect(mapped).toBeInstanceOf(ConflictError);
    expect((mapped as Error).message).toBe("users_email_key");
  });

  it("checks SQLSTATE codes before the kind", () => {
    const error = dbError("check", "bad", { code: "23514" });
    expect(toAppError(error)).toBeInstanceOf(InvalidError);

    const both = dbError("conflict", "taken", { code: "23514" });
    expect(toAppError(both)).toBeInstanceOf(InvalidError);
  });

  it("falls through to a DbException", () => {
    expect(toAppError(dbError("not_found", "none"))).toBeInstanceOf(
      DbException,
    );
    expect(toAppError(dbError("timeout", "slow"))).toBeInstanceOf(DbException);
    expect(
      toAppError(dbError("check", "bad", { code: "99999" })),
    ).toBeInstanceOf(DbException);
  });

  it("is the factory orThrow takes", async () => {
    await expect(
      AsyncResult.err(dbError("conflict", "taken")).orThrow(toAppError),
    ).rejects.toBeInstanceOf(ConflictError);
  });
});
