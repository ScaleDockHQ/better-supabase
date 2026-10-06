import { describe, expectTypeOf, it } from "vitest";

import { defineBucket, type TemplateParams } from "../../src/storage/index.ts";

describe("bucket types", () => {
  it("derives path values from the template", () => {
    const logos = defineBucket({
      id: "logos",
      path: "{orgId}/{customerId}/logo/{version}.webp",
    });
    expectTypeOf<TemplateParams<"{a}/x/{b}.png">>().toEqualTypeOf<"a" | "b">();
    expectTypeOf(logos.params).toEqualTypeOf<
      readonly ("orgId" | "customerId" | "version")[]
    >();
    logos.path({ orgId: "o", customerId: "c", version: 1 });
    // @ts-expect-error missing customerId
    logos.path({ orgId: "o", version: 1 });
    // @ts-expect-error unknown placeholder
    logos.path({ orgId: "o", customerId: "c", version: 1, other: "x" });
  });
});

describe("bucket layouts", () => {
  it("types values per template", () => {
    const files = defineBucket({
      id: "files",
      path: ["{orgId}/files/{fileId}.{ext}", "{orgId}/{...rest}"],
    });
    expectTypeOf<TemplateParams<"{orgId}/{...rest}">>().toEqualTypeOf<
      "orgId" | "rest"
    >();
    files.path({ orgId: "o", fileId: "f", ext: "pdf" });
    files.path({ orgId: "o", rest: "a/b.pdf" });
    // @ts-expect-error fileId belongs to the first template, ext is missing
    files.path({ orgId: "o", fileId: "f" });
    expectTypeOf(files.match("x")).toEqualTypeOf<
      | {
          readonly orgId: string | number;
          readonly fileId: string | number;
          readonly ext: string | number;
        }
      | { readonly orgId: string | number; readonly rest: string | number }
      | null
    >();
  });
});
