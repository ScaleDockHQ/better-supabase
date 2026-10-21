import type { SupabaseClient } from "@supabase/supabase-js";

import { describe, expectTypeOf, it } from "vitest";

import type {
  Bucket,
  StorageApi,
  StorageBucketApi,
  StorageClient,
  TemplateParams,
  TransformOptions,
} from "../../src/storage/index.ts";

import { avatarBucket, defineBucket } from "../../src/storage/index.ts";

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

describe("bucket variants", () => {
  it("types variant names in renderUrl, signedUrl and publicUrl", () => {
    const storage = defineBucket({
      id: "photos",
      path: "{userId}/{file}",
      variants: { thumb: { width: 96, height: 96 }, hero: { width: 1600 } },
    }).connect({} as SupabaseClient);

    expectTypeOf(storage.bucket.variants).toEqualTypeOf<
      Readonly<Record<"thumb" | "hero", TransformOptions>>
    >();
    expectTypeOf<Parameters<typeof storage.renderUrl>[1]>().toEqualTypeOf<
      "thumb" | "hero" | TransformOptions
    >();
    storage.renderUrl("u/a.png", "thumb");
    storage.renderUrl("u/a.png", { width: 10 });
    storage.signedUrl("u/a.png", { transform: "hero" });
    storage.publicUrl("u/a.png", { transform: "thumb" });
    // @ts-expect-error unknown variant
    storage.renderUrl("u/a.png", "huge");

    const plain = defineBucket({ id: "plain", path: "{file}" }).connect(
      {} as SupabaseClient,
    );

    // @ts-expect-error a bucket without variants takes inline transforms only
    plain.renderUrl("a.png", "thumb");
    expectTypeOf<
      Parameters<typeof plain.renderUrl>[1]
    >().toEqualTypeOf<TransformOptions>();
  });

  it("keeps a bucket with variants assignable to the loose Bucket type", () => {
    const photos = defineBucket({
      id: "photos",
      path: "{file}",
      variants: { thumb: { width: 96 } },
    });

    expectTypeOf(photos).toExtend<Bucket<string>>();
    expectTypeOf(avatarBucket()).toExtend<Bucket<string>>();
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

describe("storage clients", () => {
  it("takes a supabase-js client, its storage, or any StorageApi", () => {
    expectTypeOf<SupabaseClient>().toExtend<StorageClient>();
    expectTypeOf<SupabaseClient["storage"]>().toExtend<StorageApi>();
    expectTypeOf<
      ReturnType<SupabaseClient["storage"]["from"]>
    >().toExtend<StorageBucketApi>();

    const files = defineBucket({
      id: "files",
      path: "{organizationId}/{file}",
    });

    const supabase = {} as SupabaseClient;
    files.connect(supabase);
    files.connect(supabase.storage);
    const custom: StorageApi = { from: () => supabase.storage.from("files") };
    files.connect(custom);
    files.apply(supabase);
    // @ts-expect-error apply needs the bucket admin API of a supabase-js client
    files.apply(custom);
  });
});
