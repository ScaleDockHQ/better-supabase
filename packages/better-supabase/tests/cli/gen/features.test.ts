import { describe, expect, it } from "vitest";

import { emitFeatures } from "../../../src/cli/gen/features.ts";
import { resolveConfig } from "../../../src/config/resolve.ts";

function config(extra: Record<string, unknown> = {}) {
  return resolveConfig(
    {
      records: {
        customer: { table: "customers" },
        project: {
          table: "projects",
          versions: { columns: ["name"], auto: true },
        },
        country: { table: "countries", tenant: false },
      },
      blocks: {
        tenant: {},
        access: {},
        comments: {},
        tags: {},
        versions: {},
        sla: {},
      },
      ...extra,
    },
    "/project",
  );
}

function contents(files: readonly { path: string; contents: string }[]) {
  return Object.fromEntries(files.map((file) => [file.path, file.contents]));
}

describe("record features", () => {
  it("writes a feature per subject with a section per block that serves it", () => {
    const files = contents(emitFeatures(config(), ["next"]));

    expect(Object.keys(files).toSorted()).toEqual([
      "src/lib/supabase/features/customer/customer-actions.ts",
      "src/lib/supabase/features/customer/customer-feature.ts",
      "src/lib/supabase/features/customer/customer-provider.ts",
      "src/lib/supabase/features/customer/customer-server.ts",
      "src/lib/supabase/features/index.ts",
      "src/lib/supabase/features/project/project-actions.ts",
      "src/lib/supabase/features/project/project-feature.ts",
      "src/lib/supabase/features/project/project-provider.ts",
      "src/lib/supabase/features/project/project-server.ts",
    ]);

    const customer =
      files["src/lib/supabase/features/customer/customer-feature.ts"];

    const project =
      files["src/lib/supabase/features/project/project-feature.ts"];

    expect(customer).toContain("    sla: slaBlock,");
    expect(customer).not.toContain("versions");
    expect(project).toContain("    versions: versionsBlock,");
    expect(project).toContain("    sla: slaBlock,");
  });

  it("matches the golden Next.js bindings", () => {
    const files = contents(emitFeatures(config(), ["next"]));

    const customer = (name: string) =>
      files[`src/lib/supabase/features/customer/customer-${name}.ts`];

    expect(customer("feature")).toMatchSnapshot("feature");
    expect(customer("server")).toMatchSnapshot("server");
    expect(customer("actions")).toMatchSnapshot("actions");
    expect(customer("provider")).toMatchSnapshot("provider");

    expect(files["src/lib/supabase/features/index.ts"]).toMatchSnapshot(
      "index",
    );
  });

  it("writes TanStack Query bindings and a client provider without Next.js", () => {
    const files = contents(emitFeatures(config(), ["vite", "tanstack-query"]));

    expect(
      files["src/lib/supabase/features/customer/customer-queries.ts"],
    ).toMatchSnapshot("queries");

    const provider =
      files["src/lib/supabase/features/customer/customer-provider.ts"];

    expect(provider).toMatchSnapshot("client provider");
    expect(provider).not.toContain("customer-actions");
    expect(
      files["src/lib/supabase/features/customer/customer-server.ts"],
    ).toBeUndefined();
  });

  it("writes only the features for other frameworks", () => {
    const files = emitFeatures(config(), ["hono"]).map((file) => file.path);

    expect(files.toSorted()).toEqual([
      "src/lib/supabase/features/customer/customer-feature.ts",
      "src/lib/supabase/features/index.ts",
      "src/lib/supabase/features/project/project-feature.ts",
    ]);
  });

  it("writes nothing with generateFeatures: false or without section blocks", () => {
    expect(emitFeatures(config({ generateFeatures: false }), ["next"])).toEqual(
      [],
    );

    const bare = resolveConfig(
      {
        records: { customer: { table: "customers" } },
        blocks: { tenant: {}, access: {} },
      },
      "/project",
    );

    expect(emitFeatures(bare, ["next"])).toEqual([]);
  });

  it("adds a section and its actions when a block is installed", () => {
    const before = contents(emitFeatures(config(), ["next"]));

    const after = contents(
      emitFeatures(
        config({
          blocks: {
            tenant: {},
            access: {},
            comments: {},
            tags: {},
            versions: {},
            sla: {},
            "share-links": {},
          },
        }),
        ["next"],
      ),
    );

    const feature = "src/lib/supabase/features/customer/customer-feature.ts";
    const actions = "src/lib/supabase/features/customer/customer-actions.ts";

    expect(before[feature]).not.toContain("shareLinks");
    expect(after[feature]).toContain("    shareLinks: shareLinksBlock,");
    expect(after[actions]).toContain(
      "export const createCustomerShareLinks = customerRecord.actions.shareLinks.create;",
    );
  });

  it("renders the same files twice", () => {
    expect(emitFeatures(config(), ["next"])).toEqual(
      emitFeatures(config(), ["next"]),
    );
  });

  it("follows blocks.<name>.options.subjects", () => {
    const files = emitFeatures(
      config({
        blocks: { tenant: {}, tags: { options: { subjects: ["project"] } } },
      }),
      [],
    ).map((file) => file.path);

    expect(files).toContain(
      "src/lib/supabase/features/project/project-feature.ts",
    );
    expect(files).not.toContain(
      "src/lib/supabase/features/customer/customer-feature.ts",
    );
  });
});
