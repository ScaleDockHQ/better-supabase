import { describe, expectTypeOf, it } from "vitest";

import { defineBucket, type TemplateParams } from "../../src/storage/index.ts";

describe("bucket types", () => {
  it("derives path values from the template", () => {
    const logos = defineBucket({
      id: "logos",
      path: "{organizationId}/{customerId}/logo/{version}.webp",
    });
    expectTypeOf<TemplateParams<"{a}/x/{b}.png">>().toEqualTypeOf<"a" | "b">();
    expectTypeOf(logos.params).toEqualTypeOf<
      readonly ("organizationId" | "customerId" | "version")[]
    >();
    logos.path({ organizationId: "o", customerId: "c", version: 1 });
    // @ts-expect-error missing customerId
    logos.path({ organizationId: "o", version: 1 });
    logos.path({
      organizationId: "o",
      customerId: "c",
      version: 1,
      // @ts-expect-error unknown placeholder
      other: "x",
    });
  });
});

describe("bucket layouts", () => {
  it("types values per template", () => {
    const files = defineBucket({
      id: "files",
      path: [
        "{organizationId}/files/{fileId}.{ext}",
        "{organizationId}/{...rest}",
      ],
    });
    expectTypeOf<TemplateParams<"{organizationId}/{...rest}">>().toEqualTypeOf<
      "organizationId" | "rest"
    >();
    files.path({ organizationId: "o", fileId: "f", ext: "pdf" });
    files.path({ organizationId: "o", rest: "a/b.pdf" });
    // @ts-expect-error fileId belongs to the first template, ext is missing
    files.path({ organizationId: "o", fileId: "f" });
    expectTypeOf(files.match("x")).toEqualTypeOf<
      | {
          readonly organizationId: string | number;
          readonly fileId: string | number;
          readonly ext: string | number;
        }
      | {
          readonly organizationId: string | number;
          readonly rest: string | number;
        }
      | null
    >();
  });
});
