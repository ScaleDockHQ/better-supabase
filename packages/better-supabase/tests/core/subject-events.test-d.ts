import { describe, expectTypeOf, it } from "vitest";

import type {
  SubjectEventData,
  SubjectEventType,
} from "../../src/core/block-events.ts";
import type { AllBlockEvents } from "../blocks/all-blocks.ts";

type Subjects = SubjectEventType<AllBlockEvents>;

type Missing<K extends Subjects> = {
  [P in keyof SubjectEventData]-?: undefined extends AllBlockEvents[K][P]
    ? P
    : never;
}[keyof SubjectEventData];

describe("subject-bound events", () => {
  it("every subject event's data is a SubjectEventData", () => {
    expectTypeOf<AllBlockEvents[Subjects]>().toExtend<SubjectEventData>();
  });

  it("no subject event leaves the tenant, subject type or id optional", () => {
    expectTypeOf<Missing<Subjects>>().toEqualTypeOf<never>();
  });

  it("finds subject events in every block's map", () => {
    expectTypeOf<"comment.created">().toExtend<Subjects>();
    expectTypeOf<"organization.created">().not.toExtend<Subjects>();
  });
});
