import { describe, expectTypeOf, it } from "vitest";

import type {
  BlockEventMap,
  SubjectEventData,
  SubjectEventType,
} from "../../src/core/block-events.ts";

type Missing<K extends SubjectEventType> = {
  [P in keyof SubjectEventData]-?: undefined extends BlockEventMap[K][P]
    ? P
    : never;
}[keyof SubjectEventData];

describe("subject-bound events", () => {
  it("every subject event's data is a SubjectEventData", () => {
    expectTypeOf<
      BlockEventMap[SubjectEventType]
    >().toExtend<SubjectEventData>();
  });

  it("no subject event leaves the tenant, subject type or id optional", () => {
    expectTypeOf<Missing<SubjectEventType>>().toEqualTypeOf<never>();
  });

  it("the type list names only block events", () => {
    expectTypeOf<SubjectEventType>().toExtend<keyof BlockEventMap>();
  });
});
