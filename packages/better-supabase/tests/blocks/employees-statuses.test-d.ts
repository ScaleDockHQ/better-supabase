import { expectTypeOf, test } from "vitest";

import type { EmployeeInput } from "../../src/blocks/employees/employees.ts";

test("accepts the app's status values next to the labels", () => {
  expectTypeOf<
    EmployeeInput<Record<never, never>, "offboarding">["status"]
  >().toEqualTypeOf<
    "preboarding" | "active" | "on_leave" | "offboarding" | undefined
  >();
  expectTypeOf<EmployeeInput["status"]>().toEqualTypeOf<
    "preboarding" | "active" | "on_leave" | undefined
  >();
});
