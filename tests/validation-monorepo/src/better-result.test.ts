import type { DbError } from "better-supabase";

import { Result as BetterResult, matchError, TaggedError } from "better-result";
import {
  AsyncResult,
  dbError,
  defineBetterResultErrors,
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

  it("types the value as better-result's Result without a cast", async () => {
    const found: BetterResult<{ id: string }, AppError> = toBetterResult(
      ok({ id: "c1" }),
      BetterResult,
      (error) => new AppError(error.kind),
    );
    expect(found.map((row) => row.id).unwrap()).toBe("c1");

    const load = async (): Promise<BetterResult<number, AppError>> =>
      toBetterResult(
        AsyncResult.err(dbError("forbidden", "Not yours")),
        BetterResult,
        (error) => new AppError(error.kind),
      );
    const failed = await load();
    expect(failed.isErr()).toBe(true);
    expect(failed.mapError((error) => error.code).unwrapOr(0)).toBe(0);

    const plain = toBetterResult<BetterResult<number, DbError>>(
      err(dbError("not_found", "No customer c1")),
      BetterResult,
    );
    expect(plain.isErr() && plain.error.kind).toBe("not_found");
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

class NotFound extends TaggedError("NotFound")<{
  message: string;
  error: DbError;
}> {}
class Conflict extends TaggedError("Conflict")<{
  message: string;
  error: DbError;
}> {}
class DbFailure extends TaggedError("DbFailure")<{ message: string }> {}

describe("defineBetterResultErrors with TaggedError classes", () => {
  const toResult = defineBetterResultErrors(
    BetterResult,
    { not_found: NotFound, conflict: Conflict },
    DbFailure,
  );

  it("returns better-result values with tagged errors", async () => {
    const found: BetterResult<number, NotFound | Conflict | DbFailure> =
      toResult(ok(1));
    expect(found.unwrap()).toBe(1);

    const load = async (): Promise<
      BetterResult<number, NotFound | Conflict | DbFailure>
    > => toResult(AsyncResult.err(dbError("conflict", "duplicate key")));
    const failed = await load();
    expect(failed.isErr()).toBe(true);
    if (!failed.isErr()) return;
    expect(TaggedError.is(failed.error)).toBe(true);
    expect(
      matchError(failed.error, {
        NotFound: () => "missing",
        Conflict: (error) => `conflict: ${error.error.kind}`,
        DbFailure: (error) => error.message,
      }),
    ).toBe("conflict: conflict");
  });

  it("uses the fallback for kinds without a class", () => {
    const error = toResult.map(dbError("forbidden", "Not yours"));
    expect(error).toBeInstanceOf(DbFailure);
    expect(DbFailure.is(error)).toBe(true);
    expect(error.message).toBe("Not yours");
  });
});
