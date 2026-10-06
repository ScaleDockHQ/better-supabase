import { describe, expect, it } from "vitest";

import type { DbError, RawDbError } from "../../src/core/errors.ts";

import {
  DbException,
  dbError,
  dbErrorOf,
  isCheck,
  isConflict,
  isDbError,
  isForeignKey,
  mapDbError,
  statusOf,
} from "../../src/core/errors.ts";

describe("dbError", () => {
  it("sets the default status and drops undefined extras", () => {
    expect(
      dbError("conflict", "Taken", {
        constraint: "k",
        columns: undefined,
        code: "23505",
      } as never),
    ).toEqual({
      kind: "conflict",
      message: "Taken",
      status: 409,
      constraint: "k",
      code: "23505",
    });
  });

  it("lets the extras override the status", () => {
    expect(dbError("unexpected", "Boom", { status: 502 })).toEqual({
      kind: "unexpected",
      message: "Boom",
      status: 502,
    });
  });

  it.each([
    ["not_found", 404],
    ["aborted", 499],
    ["stale", 412],
    ["rate_limited", 429],
    ["quota_exceeded", 429],
    ["unsupported", 501],
    ["timeout", 504],
  ] as const)("maps %s to %i", (kind, status) => {
    expect(statusOf(kind)).toBe(status);
  });
});

describe("isDbError and dbErrorOf", () => {
  const error = dbError("not_found", "Gone");

  it.each<[string, unknown, boolean]>([
    ["a DbError", error, true],
    ["null", null, false],
    ["a string", "not_found", false],
    ["an object without status", { kind: "x", message: "y" }, false],
    [
      "an object with a numeric kind",
      { kind: 1, message: "y", status: 400 },
      false,
    ],
  ])("isDbError(%s)", (_name, value, expected) => {
    expect(isDbError(value)).toBe(expected);
  });

  it.each<[string, unknown, DbError | undefined]>([
    ["a DbException", new DbException(error), error],
    [
      "an Error caused by a DbError",
      new Error("wrapped", { cause: error }),
      error,
    ],
    [
      "an Error with another cause",
      new Error("wrapped", { cause: "x" }),
      undefined,
    ],
    ["a plain DbError", error, error],
    ["anything else", { kind: "not_found" }, undefined],
  ])("dbErrorOf(%s)", (_name, value, expected) => {
    expect(dbErrorOf(value)).toBe(expected);
  });

  it("exposes the kind and message on DbException", () => {
    const exception = new DbException(error);
    expect(exception).toMatchObject({
      name: "DbException",
      message: "Gone",
      kind: "not_found",
    });
  });
});

describe("constraint guards", () => {
  const conflict = dbError("conflict", "Taken", {
    constraint: "customers_kvk_key",
  });
  const check = dbError("check", "Bad", { constraint: "status_check" });
  const foreignKey = dbError("foreign_key", "Missing", {});

  it.each<[string, boolean]>([
    ["isConflict without a constraint", isConflict(conflict)],
    ["isConflict on the constraint", isConflict(conflict, "customers_kvk_key")],
    ["isConflict on a DbException", isConflict(new DbException(conflict))],
    ["isCheck on the constraint", isCheck(check, "status_check")],
    ["isForeignKey without a constraint", isForeignKey(foreignKey)],
  ])("%s matches", (_name, result) => {
    expect(result).toBe(true);
  });

  it.each<[string, boolean]>([
    ["isConflict on another constraint", isConflict(conflict, "other")],
    ["isConflict on another kind", isConflict(check)],
    ["isCheck on a non-error", isCheck("check")],
    ["isForeignKey on a constraint it lacks", isForeignKey(foreignKey, "fk")],
  ])("%s does not match", (_name, result) => {
    expect(result).toBe(false);
  });
});

describe("mapDbError", () => {
  it.each<[string, RawDbError, DbError]>([
    [
      "a unique violation with its constraint and key columns",
      {
        code: "23505",
        message:
          'duplicate key value violates unique constraint "customers_organization_id_kvk_key"',
        details: "Key (organization_id, kvk)=(o1, 123) already exists.",
      },
      {
        kind: "conflict",
        status: 409,
        code: "23505",
        message:
          'duplicate key value violates unique constraint "customers_organization_id_kvk_key"',
        details: "Key (organization_id, kvk)=(o1, 123) already exists.",
        constraint: "customers_organization_id_kvk_key",
        columns: ["organization_id", "kvk"],
      },
    ],
    [
      "a unique violation without details",
      { code: "23505", message: "duplicate", details: null, hint: null },
      { kind: "conflict", status: 409, code: "23505", message: "duplicate" },
    ],
    [
      "a unique violation without a message",
      { code: "23505" },
      {
        kind: "conflict",
        status: 409,
        code: "23505",
        message: "Unknown database error",
      },
    ],
    [
      "a foreign key violation with the pg constraint field",
      {
        code: "23503",
        message: "insert violates foreign key",
        constraint: "notes_customer_id_fkey",
        details: 'Key (customer_id)=(c9) is not present in table "customers".',
      },
      {
        kind: "foreign_key",
        status: 409,
        code: "23503",
        message: "insert violates foreign key",
        details: 'Key (customer_id)=(c9) is not present in table "customers".',
        constraint: "notes_customer_id_fkey",
        columns: ["customer_id"],
      },
    ],
    [
      "a foreign key violation without detail",
      { code: "23503", message: "fk" },
      { kind: "foreign_key", status: 409, code: "23503", message: "fk" },
    ],
    [
      "a check violation",
      {
        code: "23514",
        message: 'new row violates check constraint "status_check"',
      },
      {
        kind: "check",
        status: 422,
        code: "23514",
        message: 'new row violates check constraint "status_check"',
        constraint: "status_check",
      },
    ],
    [
      "a check violation without a constraint",
      { code: "23514", message: "check" },
      { kind: "check", status: 422, code: "23514", message: "check" },
    ],
    [
      "a JSON Schema failure from the jsonb-schemas trigger",
      {
        code: "23514",
        message:
          'customers.metadata does not match its JSON Schema: "x" is not of type "integer"',
        details:
          '["\\"x\\" is not of type \\"integer\\"", "\\"tier\\" is a required property"]',
        hint: "JSON_SCHEMA_INVALID",
      },
      {
        kind: "validation",
        status: 422,
        code: "23514",
        message:
          'customers.metadata does not match its JSON Schema: "x" is not of type "integer"',
        details:
          '["\\"x\\" is not of type \\"integer\\"", "\\"tier\\" is a required property"]',
        hint: "JSON_SCHEMA_INVALID",
        issues: [
          { message: '"x" is not of type "integer"', path: ["metadata"] },
          { message: '"tier" is a required property', path: ["metadata"] },
        ],
      },
    ],
    [
      "a jsonb-schemas check constraint without the trigger's detail",
      {
        code: "23514",
        message:
          'new row for relation "customers" violates check constraint "bs_json_metadata"',
      },
      {
        kind: "validation",
        status: 422,
        code: "23514",
        message:
          'new row for relation "customers" violates check constraint "bs_json_metadata"',
        issues: [{ message: "The value does not match its JSON Schema" }],
      },
    ],
    [
      "a JSON Schema failure from Postgres with the column field",
      {
        code: "23514",
        message: "x",
        details: "not json",
        constraint: "bs_json_value_theme",
        column: "value",
      },
      {
        kind: "validation",
        status: 422,
        code: "23514",
        message: "x",
        details: "not json",
        issues: [
          {
            message: "The value does not match its JSON Schema",
            path: ["value"],
          },
        ],
      },
    ],
    [
      "a not-null violation from the message",
      {
        code: "23502",
        message: 'null value in column "name" violates not-null constraint',
      },
      {
        kind: "not_null",
        status: 422,
        code: "23502",
        message: 'null value in column "name" violates not-null constraint',
        column: "name",
      },
    ],
    [
      "a not-null violation from the pg column field",
      { code: "23502", message: "not null", column: "kvk" },
      {
        kind: "not_null",
        status: 422,
        code: "23502",
        message: "not null",
        column: "kvk",
      },
    ],
    [
      "a not-null violation without a column",
      { code: "23502", message: "not null" },
      { kind: "not_null", status: 422, code: "23502", message: "not null" },
    ],
    [
      "an exclusion violation",
      {
        code: "23P01",
        message:
          'conflicting key value violates exclusion constraint "no_overlap"',
      },
      {
        kind: "exclusion",
        status: 409,
        code: "23P01",
        message:
          'conflicting key value violates exclusion constraint "no_overlap"',
        constraint: "no_overlap",
      },
    ],
    [
      "an exclusion violation without a constraint",
      { code: "23P01", message: "exclusion" },
      { kind: "exclusion", status: 409, code: "23P01", message: "exclusion" },
    ],
    [
      "a raised exception with its hint",
      { code: "P0001", message: "Quota reached", hint: "QUOTA" },
      {
        kind: "raised",
        status: 400,
        code: "P0001",
        message: "Quota reached",
        hint: "QUOTA",
      },
    ],
    [
      "a no_data_found exception",
      { code: "P0002", message: "Invoice not found" },
      {
        kind: "not_found",
        status: 404,
        code: "P0002",
        message: "Invoice not found",
      },
    ],
    [
      "a statement timeout",
      {
        code: "57014",
        message: "canceling statement due to statement timeout",
      },
      {
        kind: "timeout",
        status: 504,
        code: "57014",
        message: "canceling statement due to statement timeout",
      },
    ],
    [
      "a serialization failure",
      { code: "40001", message: "could not serialize" },
      {
        kind: "serialization",
        status: 409,
        code: "40001",
        message: "could not serialize",
      },
    ],
    [
      "a deadlock",
      { code: "40P01", message: "deadlock detected" },
      {
        kind: "serialization",
        status: 409,
        code: "40P01",
        message: "deadlock detected",
      },
    ],
    [
      "PGRST116 with no rows",
      {
        code: "PGRST116",
        message: "JSON object requested",
        details: "The result contains 0 rows",
      },
      {
        kind: "not_found",
        status: 404,
        code: "PGRST116",
        message: "JSON object requested",
        details: "The result contains 0 rows",
      },
    ],
    [
      "PGRST116 with several rows",
      {
        code: "PGRST116",
        message: "JSON object requested",
        details: "The result contains 2 rows, more than one",
      },
      {
        kind: "multiple_rows",
        status: 409,
        code: "PGRST116",
        message: "JSON object requested",
        details: "The result contains 2 rows, more than one",
      },
    ],
    [
      "PGRST116 described only by the message",
      { code: "PGRST116", message: "Results contain multiple rows" },
      {
        kind: "multiple_rows",
        status: 409,
        code: "PGRST116",
        message: "Results contain multiple rows",
      },
    ],
    [
      "an expired JWT",
      { code: "PGRST303", message: "JWT expired" },
      {
        kind: "unauthorized",
        status: 401,
        code: "PGRST303",
        message: "JWT expired",
      },
    ],
    [
      "a missing JWT secret",
      { code: "PGRST301", message: "JWT invalid" },
      {
        kind: "unauthorized",
        status: 401,
        code: "PGRST301",
        message: "JWT invalid",
      },
    ],
    [
      "a write past max-affected",
      {
        code: "PGRST124",
        message: "Query result exceeds max-affected preference constraint",
        details: "The query affects 3 rows",
      },
      {
        kind: "max_affected",
        status: 400,
        code: "PGRST124",
        message: "Query result exceeds max-affected preference constraint",
        details: "The query affects 3 rows",
      },
    ],
    [
      "the SQL max-affected guard",
      {
        code: "22P02",
        message:
          'invalid input syntax for type integer: "better_supabase:max_affected:12"',
      },
      {
        kind: "max_affected",
        status: 400,
        code: "22P02",
        message: "The write affects 12 rows, more than maxAffected allows",
      },
    ],
    [
      "disabled aggregates",
      {
        code: "PGRST123",
        message: "Use of aggregate functions is not allowed",
      },
      {
        kind: "invalid_request",
        status: 400,
        code: "PGRST123",
        message: "Use of aggregate functions is not allowed",
        hint: "PostgREST aggregates are off. Run `alter role authenticator set pgrst.db_aggregates_enabled = 'true'; notify pgrst, 'reload config';` (see BS210), or use better-supabase/postgres.",
      },
    ],
    [
      "disabled aggregates with a server hint",
      { code: "PGRST123", message: "aggregates", hint: "Enable them" },
      {
        kind: "invalid_request",
        status: 400,
        code: "PGRST123",
        message: "aggregates",
        hint: "Enable them",
      },
    ],
    [
      "a rate limit with Retry-After",
      {
        code: "BS429",
        message: "Too many requests",
        details: "Retry after 30 seconds",
      },
      {
        kind: "rate_limited",
        status: 429,
        code: "BS429",
        message: "Too many requests",
        details: "Retry after 30 seconds",
        retryAfter: 30,
      },
    ],
    [
      "a rate limit without Retry-After",
      { code: "PT429", message: "Too many requests" },
      {
        kind: "rate_limited",
        status: 429,
        code: "PT429",
        message: "Too many requests",
      },
    ],
    [
      "an invalid text representation",
      { code: "22P02", message: 'invalid input syntax for type uuid: "x"' },
      {
        kind: "invalid_input",
        status: 400,
        code: "22P02",
        message: 'invalid input syntax for type uuid: "x"',
      },
    ],
    [
      "an unknown column in PostgREST",
      { code: "PGRST204", message: "Could not find the column" },
      {
        kind: "invalid_request",
        status: 400,
        code: "PGRST204",
        message: "Could not find the column",
      },
    ],
    [
      "a bad PostgREST request",
      { code: "PGRST100", message: "parse error" },
      {
        kind: "invalid_request",
        status: 400,
        code: "PGRST100",
        message: "parse error",
      },
    ],
    [
      "a connection failure",
      { code: "08006", message: "connection failure" },
      {
        kind: "network",
        status: 503,
        code: "08006",
        message: "connection failure",
      },
    ],
    [
      "a fetch failure",
      { message: "TypeError: fetch failed" },
      { kind: "network", status: 503, message: "TypeError: fetch failed" },
    ],
    [
      "an abort by name",
      { name: "AbortError", message: "This operation was aborted" },
      { kind: "aborted", status: 499, message: "This operation was aborted" },
    ],
    [
      "an abort by code",
      { code: "20", message: "aborted" },
      { kind: "aborted", status: 499, code: "20", message: "aborted" },
    ],
    [
      "an abort by message",
      { message: "AbortError: signal is aborted without reason" },
      {
        kind: "aborted",
        status: 499,
        message: "AbortError: signal is aborted without reason",
      },
    ],
    [
      "an unknown code",
      { code: "XX000", message: "internal error" },
      {
        kind: "unexpected",
        status: 500,
        code: "XX000",
        message: "internal error",
      },
    ],
    [
      "an empty error",
      {},
      { kind: "unexpected", status: 500, message: "Unknown database error" },
    ],
  ])("maps %s", (_name, raw, expected) => {
    expect(mapDbError(raw)).toEqual(expected);
  });

  describe("permission errors", () => {
    it.each<[string, RawDbError, string | undefined]>([
      [
        "a table without a hint",
        { code: "42501", message: "permission denied for table customers" },
        "Supabase no longer grants new tables to the Data API roles: add customers to `expose` and run `better-supabase sql add grants`. `better-supabase doctor` (BS106) lists every missing grant.",
      ],
      [
        "a view with the PostgREST hint",
        {
          code: "42501",
          message: "permission denied for view active_customers",
          hint: "Grant the required privileges to the current role.",
        },
        "Grant the required privileges to the current role. Supabase no longer grants new tables to the Data API roles: add active_customers to `expose` and run `better-supabase sql add grants`. `better-supabase doctor` (BS106) lists every missing grant.",
      ],
      [
        "a function",
        {
          code: "42501",
          message: "permission denied for function search_notes",
        },
        "Supabase no longer grants new objects to the Data API roles automatically; grant execute on function search_notes to the role that needs it.",
      ],
      [
        "a schema",
        { code: "42501", message: "permission denied for schema private" },
        "Supabase no longer grants new objects to the Data API roles automatically; grant usage on schema private to the role that needs it.",
      ],
      [
        "an object with an app hint",
        {
          code: "42501",
          message: "permission denied for table customers",
          hint: "Ask an admin",
        },
        "Ask an admin",
      ],
      [
        "a row-level security violation",
        {
          code: "42501",
          message:
            'new row violates row-level security policy for table "notes"',
        },
        undefined,
      ],
    ])("maps %s to forbidden", (_name, raw, hint) => {
      const mapped = mapDbError(raw);
      expect(mapped).toMatchObject({
        kind: "forbidden",
        status: 403,
        code: "42501",
      });
      expect(mapped.hint).toBe(hint);
    });
  });

  describe("custom mappers", () => {
    it("returns the first mapped error and passes the built-in fallback", () => {
      const seen: DbError[] = [];
      const mapped = mapDbError(
        { code: "P0001", message: "Quota", hint: "QUOTA" },
        [
          (_raw, fallback) => {
            seen.push(fallback);
            return;
          },
          (raw) =>
            raw.hint === "QUOTA"
              ? dbError("rate_limited", "Quota reached")
              : undefined,
          () => dbError("unexpected", "never reached"),
        ],
      );
      expect(mapped).toEqual({
        kind: "rate_limited",
        status: 429,
        message: "Quota reached",
      });
      expect(seen).toEqual([
        {
          kind: "raised",
          status: 400,
          code: "P0001",
          message: "Quota",
          hint: "QUOTA",
        },
      ]);
    });

    it("falls back when no mapper matches", () => {
      expect(
        mapDbError({ code: "57014", message: "slow" }, [() => undefined]),
      ).toEqual({
        kind: "timeout",
        status: 504,
        code: "57014",
        message: "slow",
      });
    });
  });
});
