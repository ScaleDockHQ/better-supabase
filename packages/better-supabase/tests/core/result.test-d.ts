import { describe, expectTypeOf, it } from "vitest";

import type { DbError, DbErrorOf } from "../../src/core/errors.ts";

import {
  AsyncResult,
  type BetterResultValue,
  defineBetterResultErrors,
  fromBetterResult,
  ok,
  type Result,
  toBetterResult,
} from "../../src/core/result.ts";

declare class BrOk<T, E = never> {
  readonly status: "ok";
  readonly value: T;
  map<U>(fn: (value: T) => U): BrResult<U, E>;
}
declare class BrErr<T, E> {
  readonly status: "error";
  readonly error: E;
  map<U>(fn: (value: T) => U): BrResult<U, E>;
}
type BrResult<T, E> = BrOk<T, E> | BrErr<T, E>;
declare const Br: {
  ok<T>(value: T): BrOk<T>;
  err<E>(error: E): BrErr<never, E>;
};

class AppError extends Error {}
declare const result: Result<{ id: string }>;

describe("toBetterResult", () => {
  it("types value and error", () => {
    expectTypeOf(toBetterResult(result, Br)).toEqualTypeOf<
      BetterResultValue<{ id: string }, DbError>
    >();
    expectTypeOf(
      toBetterResult(result, Br, () => new AppError()),
    ).toEqualTypeOf<BetterResultValue<{ id: string }, AppError>>();
  });

  it("types a mapper carried by betterSupabase.mapError as unknown", () => {
    expectTypeOf(toBetterResult(AsyncResult.ok(1), Br)).toEqualTypeOf<
      Promise<BetterResultValue<number, unknown>>
    >();
  });

  it("still accepts a cast to the better-result type", () => {
    const value = toBetterResult(result, Br);
    const typed = value as BrResult<{ id: string }, DbError>;
    expectTypeOf(typed.map((row) => row.id)).toEqualTypeOf<
      BrResult<string, DbError>
    >();
  });

  it("takes the better-result type from the expected type", () => {
    const typed: BrResult<{ id: string }, AppError> = toBetterResult(
      result,
      Br,
      () => new AppError(),
    );
    expectTypeOf(typed.map((row) => row.id)).toEqualTypeOf<
      BrResult<string, AppError>
    >();
    const plain: BrResult<{ id: string }, DbError> = toBetterResult(result, Br);
    expectTypeOf(plain).toEqualTypeOf<BrResult<{ id: string }, DbError>>();
  });

  it("takes the better-result type as a type argument", () => {
    expectTypeOf(
      toBetterResult<BrResult<{ id: string }, AppError>>(
        result,
        Br,
        () => new AppError(),
      ),
    ).toEqualTypeOf<BrResult<{ id: string }, AppError>>();
    expectTypeOf(
      toBetterResult<BrResult<number, AppError>>(
        AsyncResult.ok(1),
        Br,
        () => new AppError(),
      ),
    ).toEqualTypeOf<Promise<BrResult<number, AppError>>>();
    expectTypeOf(
      toBetterResult<BrResult<number, unknown>>(AsyncResult.ok(1), Br),
    ).toEqualTypeOf<Promise<BrResult<number, unknown>>>();
  });

  it("types a function's return value without a cast", () => {
    const load = async (): Promise<BrResult<number, AppError>> =>
      toBetterResult(AsyncResult.ok(1), Br, () => new AppError());
    const generic = <T>(value: Result<T>): BrResult<T, AppError> =>
      toBetterResult(value, Br, () => new AppError());
    expectTypeOf(load).returns.resolves.toEqualTypeOf<
      BrResult<number, AppError>
    >();
    expectTypeOf(generic(result)).toEqualTypeOf<
      BrResult<{ id: string }, AppError>
    >();
  });

  it("checks the expected type against the row and the error", () => {
    // @ts-expect-error the row is { id: string }, not string
    const wrongRow: BrResult<string, AppError> = toBetterResult(
      result,
      Br,
      () => new AppError(),
    );
    // @ts-expect-error mapError returns AppError, not string
    const wrongError: BrResult<{ id: string }, string> = toBetterResult(
      result,
      Br,
      () => new AppError(),
    );
    // @ts-expect-error without mapError the error is a DbError
    const unmapped: BrResult<{ id: string }, AppError> = toBetterResult(
      result,
      Br,
    );
    // @ts-expect-error a mapper set with betterSupabase.mapError is typed unknown
    const carried: Promise<BrResult<number, AppError>> = toBetterResult(
      AsyncResult.ok(1),
      Br,
    );
    expectTypeOf([wrongRow, wrongError, unmapped, carried]).not.toBeNever();
  });
});

describe("fromBetterResult", () => {
  it("returns a Result with DbError", () => {
    expectTypeOf(fromBetterResult(Br.ok(ok(1).data))).toEqualTypeOf<
      Result<number>
    >();
  });
});

declare class NotFound {
  readonly _tag: "NotFound";
  constructor(props: { message: string; error: DbError });
}
declare class Conflict {
  readonly _tag: "Conflict";
  constructor(props: { message: string; error: DbErrorOf<"conflict"> });
}
declare class DbFailure {
  readonly _tag: "DbFailure";
  constructor(props: { message: string });
}
declare const asyncResult: AsyncResult<{ id: string }>;

describe("defineBetterResultErrors", () => {
  const toResult = defineBetterResultErrors(
    Br,
    { not_found: NotFound, conflict: Conflict },
    DbFailure,
  );

  it("types each kind's error", () => {
    expectTypeOf(
      toResult.map({} as DbErrorOf<"not_found">),
    ).toEqualTypeOf<NotFound>();
    expectTypeOf(
      toResult.map({} as DbErrorOf<"forbidden">),
    ).toEqualTypeOf<DbFailure>();
    expectTypeOf(toResult.map({} as DbError)).toEqualTypeOf<
      NotFound | Conflict | DbFailure
    >();
  });

  it("returns better-result's Result from the expected type", async () => {
    const found: BrResult<{ id: string }, NotFound | Conflict | DbFailure> =
      toResult(result);
    expectTypeOf(found.map((row) => row.id)).toEqualTypeOf<
      BrResult<string, NotFound | Conflict | DbFailure>
    >();
    const later: BrResult<{ id: string }, NotFound | Conflict | DbFailure> =
      await toResult(asyncResult);
    expectTypeOf(later).not.toBeAny();
    expectTypeOf(toResult(result)).toEqualTypeOf<
      BetterResultValue<{ id: string }, NotFound | Conflict | DbFailure>
    >();
  });

  it("rejects an expected error type that misses a mapped class", () => {
    // @ts-expect-error DbFailure is not part of the expected error type
    const narrow: BrResult<{ id: string }, NotFound | Conflict> =
      toResult(result);
    expectTypeOf(narrow).not.toBeAny();
  });

  it("rejects a class whose constructor needs other props", () => {
    class Needy {
      readonly id: number;
      constructor(props: { id: number }) {
        this.id = props.id;
      }
    }
    // @ts-expect-error Needy's constructor does not take { message, error }
    defineBetterResultErrors(Br, { not_found: Needy }, DbFailure);
  });
});
