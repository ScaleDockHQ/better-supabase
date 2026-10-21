import type { StandardSchemaV1 } from "@standard-schema/spec";

import { describe, expectTypeOf, it } from "vitest";

import type { NewAttachment } from "../../src/blocks/attachments/attachments.ts";
import type { attachmentInputSchema } from "../../src/blocks/attachments/schemas.ts";
import type { CalendarEventInput } from "../../src/blocks/calendar/calendar.ts";
import type { calendarEventInputSchema } from "../../src/blocks/calendar/schemas.ts";
import type { ProductInput } from "../../src/blocks/catalog/catalog.ts";
import type { productInputSchema } from "../../src/blocks/catalog/schemas.ts";
import type {
  CommentEdit,
  NewComment,
} from "../../src/blocks/comments/comments.ts";
import type {
  commentChangeSchema,
  commentInputSchema,
} from "../../src/blocks/comments/schemas.ts";
import type { DealChange, DealInput } from "../../src/blocks/deals/deals.ts";
import type {
  dealChangeSchema,
  dealInputSchema,
} from "../../src/blocks/deals/schemas.ts";
import type {
  EmployeeChange,
  EmployeeInput,
} from "../../src/blocks/employees/employees.ts";
import type {
  employeeChangeSchema,
  employeeInputSchema,
} from "../../src/blocks/employees/schemas.ts";
import type { EngagementInput } from "../../src/blocks/engagements/engagements.ts";
import type {
  engagementChangeSchema,
  engagementInputSchema,
} from "../../src/blocks/engagements/schemas.ts";
import type {
  CompanyInput,
  PartyListOptions,
  PersonInput,
} from "../../src/blocks/parties/parties.ts";
import type {
  companyInputSchema,
  partyListFilterSchema,
  personInputSchema,
} from "../../src/blocks/parties/schemas.ts";
import type {
  workItemChangeSchema,
  workItemInputSchema,
  workItemListFilterSchema,
} from "../../src/blocks/work-items/schemas.ts";
import type {
  WorkItemChange,
  WorkItemInput,
  WorkItemListOptions,
} from "../../src/blocks/work-items/work-items.ts";

import { entitySchema } from "../../src/blocks/entity-schema.ts";

type Out<S extends StandardSchemaV1> = StandardSchemaV1.InferOutput<S>;

interface Note {
  readonly title: string;
  readonly body?: string;
  readonly tags: readonly string[];
}

describe("entitySchema", () => {
  it("outputs the hand-written types", () => {
    expectTypeOf<
      StandardSchemaV1.InferOutput<typeof workItemInputSchema>
    >().toEqualTypeOf<WorkItemInput>();
    expectTypeOf<
      StandardSchemaV1.InferOutput<typeof workItemChangeSchema>
    >().toEqualTypeOf<WorkItemChange>();
    expectTypeOf<
      StandardSchemaV1.InferOutput<typeof workItemListFilterSchema>
    >().toEqualTypeOf<WorkItemListOptions>();
  });

  it("outputs the other entity blocks' types", () => {
    expectTypeOf<Out<typeof dealInputSchema>>().toEqualTypeOf<DealInput>();
    expectTypeOf<Out<typeof dealChangeSchema>>().toEqualTypeOf<DealChange>();
    expectTypeOf<
      Out<typeof companyInputSchema>
    >().toEqualTypeOf<CompanyInput>();
    expectTypeOf<Out<typeof personInputSchema>>().toEqualTypeOf<PersonInput>();
    expectTypeOf<
      Out<typeof partyListFilterSchema>
    >().toEqualTypeOf<PartyListOptions>();
    expectTypeOf<
      Out<typeof productInputSchema>
    >().toEqualTypeOf<ProductInput>();
    expectTypeOf<
      Out<typeof employeeInputSchema>
    >().toEqualTypeOf<EmployeeInput>();
    expectTypeOf<
      Out<typeof employeeChangeSchema>
    >().toEqualTypeOf<EmployeeChange>();
  });

  it("outputs the collaboration blocks' types", () => {
    expectTypeOf<Out<typeof commentInputSchema>>().toEqualTypeOf<NewComment>();
    expectTypeOf<
      Out<typeof commentChangeSchema>
    >().toEqualTypeOf<CommentEdit>();
    expectTypeOf<
      Out<typeof attachmentInputSchema>
    >().toEqualTypeOf<NewAttachment>();
    expectTypeOf<Out<typeof engagementInputSchema>>().toEqualTypeOf<
      EngagementInput & { readonly type: string; readonly title: string }
    >();
    expectTypeOf<
      Out<typeof engagementChangeSchema>
    >().toEqualTypeOf<EngagementInput>();
    expectTypeOf<
      Out<typeof calendarEventInputSchema>
    >().toEqualTypeOf<CalendarEventInput>();
  });

  it("needs every key, with optional and array flags that match the type", () => {
    entitySchema<Note>({
      fields: {
        title: { kind: "string" },
        body: { kind: "string", optional: true },
        tags: { kind: "string", array: true },
      },
    });

    entitySchema<Note>({
      // @ts-expect-error -- `tags` is missing.
      fields: {
        title: { kind: "string" },
        body: { kind: "string", optional: true },
      },
    });

    entitySchema<Note>({
      fields: {
        // @ts-expect-error -- `title` is required.
        title: { kind: "string", optional: true },
        body: { kind: "string", optional: true },
        tags: { kind: "string", array: true },
      },
    });

    entitySchema<Note>({
      fields: {
        title: { kind: "string" },
        // @ts-expect-error -- `body` is optional.
        body: { kind: "string" },
        tags: { kind: "string", array: true },
      },
    });

    entitySchema<Note>({
      fields: {
        title: { kind: "string" },
        body: { kind: "string", optional: true },
        // @ts-expect-error -- `tags` is a list.
        tags: { kind: "string" },
      },
    });

    entitySchema<Note>({
      fields: {
        title: { kind: "string" },
        body: { kind: "string", optional: true },
        tags: { kind: "string", array: true },
        // @ts-expect-error -- `Note` has no `extra`.
        extra: { kind: "string" },
      },
    });
  });
});
