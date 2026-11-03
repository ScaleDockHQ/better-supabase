import { describe, expectTypeOf, it } from "vitest";

import type {
  DeadLetter,
  SupabaseWorldOptions,
} from "../../../src/workflow-sdk/world/index.ts";

describe("World 5.1 options", () => {
  it("types the dead-letter hook and the new switches", () => {
    expectTypeOf<SupabaseWorldOptions["onDeadLetter"]>().toEqualTypeOf<
      ((info: DeadLetter) => void | Promise<void>) | undefined
    >();
    expectTypeOf<SupabaseWorldOptions["enableInvoke"]>().toEqualTypeOf<
      boolean | undefined
    >();
    expectTypeOf<SupabaseWorldOptions["streamFlushIntervalMs"]>().toEqualTypeOf<
      number | undefined
    >();
  });

  it("keeps a dead letter's identifiers as strings", () => {
    expectTypeOf<DeadLetter["jobId"]>().toEqualTypeOf<string>();
    expectTypeOf<DeadLetter["attempts"]>().toEqualTypeOf<number>();
  });
});
