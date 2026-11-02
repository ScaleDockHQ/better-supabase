import * as v from "valibot";
import { describe, expect, it } from "vitest";

import {
  createTemplates,
  defineMergeFields,
  defineTemplateType,
} from "../../../src/blocks/templates/index.ts";
import { dbError } from "../../../src/core/errors.ts";
import { AsyncResult } from "../../../src/core/result.ts";

function transport(
  results: Record<string, (args: Record<string, unknown>) => unknown>,
) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    call(_schema: string, fn: string, args: Record<string, unknown>) {
      calls.push([fn, args]);
      const result = results[fn];

      if (!result) {
        return Promise.reject(new Error(`unexpected ${fn}`));
      }

      return Promise.resolve(result(args));
    },
  };
}

const AT = "2026-10-06T09:00:00Z";

const TEMPLATE = {
  id: "t1",
  tenant: "o",
  scope: "tenant",
  type: "email",
  name: "Welcome",
  language: "en",
  settings: {},
  createdAt: AT,
  updatedAt: AT,
};

const VERSION = {
  id: "v1",
  template: "t1",
  version: 1,
  hash: "abc",
  createdAt: AT,
  body: {
    subject: "Hi {{ name }}",
    lines: ["{{ name }}", 3, "{{ ghost }}"],
    nested: { greeting: "<b>{{ name }}</b>" },
    count: 4,
  },
};

const DRAFT = { ...VERSION, id: "v2", version: 2, body: { subject: "Draft" } };

const catalog = defineMergeFields("customer", {
  name: { example: "Ada", description: "Customer name" },
  plan: {},
});

const email = defineTemplateType({ mergeFields: catalog });

describe("template variables and previews", () => {
  it("lists the catalog's fields and refuses unknown or catalog-less types", async () => {
    const fake = transport({});

    const templates = createTemplates({
      transport: fake,
      types: { email, plain: defineTemplateType({}) },
    });

    expect(await templates.variables({ type: "email" }).orThrow()).toEqual([
      { name: "name", example: "Ada", description: "Customer name" },
      { name: "plan" },
    ]);
    expect(await templates.variables({ type: "plain" }).orThrow()).toEqual([]);

    const unknown = await templates.variables({ type: "nope" });

    expect(!unknown.ok && unknown.error.hint).toBe("TEMPLATE_TYPE_UNKNOWN");
  });

  it("renders the published version with examples, values and the escape mode", async () => {
    const fake = transport({
      template_get: () => ({ ...TEMPLATE, published: VERSION, draft: DRAFT }),
    });

    const templates = createTemplates({ transport: fake, types: { email } });

    const preview = await templates
      .preview({ template: "t1", values: { name: "<Bo>" }, escape: "html" })
      .orThrow();

    expect(preview).toMatchObject({
      template: "t1",
      type: "email",
      version: 1,
      body: {
        subject: "Hi &lt;Bo&gt;",
        lines: ["&lt;Bo&gt;", 3, ""],
        nested: { greeting: "<b>&lt;Bo&gt;</b>" },
        count: 4,
      },
    });
    expect(preview.unknownFields).toEqual(["ghost"]);

    const example = await templates.preview({ template: "t1" }).orThrow();

    expect(example.body).toMatchObject({ subject: "Hi Ada" });
  });

  it("previews the draft, falls back between versions and handles no versions", async () => {
    let detail: Record<string, unknown> = {
      ...TEMPLATE,
      published: VERSION,
      draft: DRAFT,
    };

    const fake = transport({ template_get: () => detail });
    const templates = createTemplates({ transport: fake });

    const draft = await templates
      .preview({ template: "t1", draft: true })
      .orThrow();

    expect(draft).toMatchObject({ version: 2, body: { subject: "Draft" } });

    detail = { ...TEMPLATE, published: VERSION, draft: null };
    expect(
      (await templates.preview({ template: "t1", draft: true }).orThrow())
        .version,
    ).toBe(1);

    detail = { ...TEMPLATE, published: null, draft: DRAFT };
    expect(
      (await templates.preview({ template: "t1" }).orThrow()).version,
    ).toBe(2);

    detail = { ...TEMPLATE, published: null, draft: null };

    const empty = await templates.preview({ template: "t1" }).orThrow();

    expect(empty.version).toBeUndefined();
    expect(empty.body).toBeUndefined();
  });

  it("reports a template that cannot be read", async () => {
    const fake = transport({ template_get: () => null });
    const templates = createTemplates({ transport: fake });

    const preview = await templates.preview({ template: "nope" });

    expect(!preview.ok && preview.error.hint).toBe("TEMPLATE_NOT_FOUND");
    expect(await templates.get("nope").orThrow()).toBeUndefined();
  });
});

describe("template writes", () => {
  const project = defineTemplateType({
    settings: v.object({ color: v.string() }),
    body: v.object({ tasks: v.array(v.string()) }),
  });

  it("saves a template with defaults and with every optional value", async () => {
    const fake = transport({ save_template: () => TEMPLATE });
    const templates = createTemplates({ transport: fake, types: { project } });

    await templates
      .upsert({ organizationId: "o", type: "project", name: "N" })
      .orThrow();
    await templates
      .upsert({
        id: "t1",
        organizationId: "o",
        type: "project",
        language: "nl",
        settings: { color: "red" },
      })
      .orThrow();

    expect(fake.calls[0]?.[1]).toMatchObject({
      template_id: null,
      name: "N",
      language: null,
      settings: null,
    });
    expect(fake.calls[1]?.[1]).toMatchObject({
      template_id: "t1",
      name: null,
      language: "nl",
      settings: { color: "red" },
    });
  });

  it("rejects extra fields the schema refuses", async () => {
    const fake = transport({ save_template: () => TEMPLATE });

    const templates = createTemplates({
      transport: fake,
      fields: v.object({ tag: v.string() }),
    });

    const bad = await templates.upsert({
      organizationId: "o",
      type: "email",
      // SAFETY: deliberately invalid fields to exercise the refusal.
      fields: { tag: 1 } as unknown as { tag: string },
    });

    expect(bad.ok).toBe(false);
    expect(fake.calls).toHaveLength(0);
  });

  it("sets a default off, lists with a language and fork errors", async () => {
    const fake = transport({
      set_default_template: () => true,
      templates_list: () => [],
      fork_template: () => null,
    });

    const templates = createTemplates({ transport: fake });

    await templates.setDefault({ id: "t1", isDefault: false }).orThrow();
    await templates
      .list({ organizationId: "o", filter: { language: "nl" } })
      .orThrow();
    expect(fake.calls[0]?.[1]).toEqual({
      template_id: "t1",
      on_default: false,
    });
    expect(fake.calls[1]?.[1]).toEqual({
      tenant: "o",
      type: null,
      language: "nl",
    });
    expect(
      (await templates.fork({ source: "s", organizationId: "o" })).ok,
    ).toBe(false);
  });

  it("checks a version body against its template's type", async () => {
    const fake = transport({
      template_get: (args) =>
        args["template_id"] === "gone"
          ? null
          : {
              ...TEMPLATE,
              type: args["template_id"] === "loose" ? "other" : "project",
            },
      save_template_draft: () => VERSION,
    });

    const templates = createTemplates({
      transport: fake,
      types: { project, other: defineTemplateType({}) },
    });

    const missing = await templates.versions.upsert({
      template: "gone",
      body: {},
    });

    expect(!missing.ok && missing.error.kind).toBe("not_found");

    const loose = await templates.versions.upsert({
      template: "loose",
      body: { anything: true },
    });

    expect(loose.ok).toBe(true);

    const failing = createTemplates({
      transport: transport({
        template_get: () => {
          throw new Error("down");
        },
      }),
      types: { project },
    });

    expect(
      (await failing.versions.upsert({ template: "t1", body: {} })).ok,
    ).toBe(false);
  });

  it("syncs starters without settings or language", async () => {
    const fake = transport({ sync_templates: () => 1 });
    const templates = createTemplates({ transport: fake });

    await templates
      .sync([{ key: "k", type: "free", name: "Free", body: { a: 1 } }])
      .orThrow();
    await templates
      .sync([
        { key: "k2", type: "free", name: "Free", language: "fr", body: {} },
      ])
      .orThrow();
    expect(fake.calls[0]?.[1]).toEqual({
      starters: [
        { key: "k", type: "free", name: "Free", settings: {}, body: { a: 1 } },
      ],
    });
    expect(fake.calls[1]?.[1]).toMatchObject({
      starters: [{ language: "fr" }],
    });

    const strict = createTemplates({
      transport: fake,
      types: {
        project: defineTemplateType({ settings: v.object({ c: v.string() }) }),
      },
    });

    expect(
      (
        await strict.sync([
          {
            key: "k",
            type: "project",
            name: "P",
            body: {},
            settings: { c: 1 },
          },
        ])
      ).ok,
    ).toBe(false);
  });
});

describe("template apply edge cases", () => {
  const target = (workflows: unknown[] = []) => ({
    template: { ...TEMPLATE, type: "project", settings: { color: "blue" } },
    version: { ...VERSION, body: { tasks: ["a"] } },
    workflows,
  });

  const project = defineTemplateType({
    settings: v.object({ color: v.string() }),
    body: v.object({ tasks: v.array(v.string()) }),
    apply: () => ({ subject: { type: "project", id: "p1" } }),
  });

  const APPLICATION = {
    id: "a1",
    template: "t1",
    version: "v1",
    tenant: "o",
    subjectType: "project",
    subjectId: "p1",
    appliedAt: AT,
  };

  it("reports a settings or body the type refuses", async () => {
    const badSettings = createTemplates({
      transport: transport({
        template_apply_target: () => ({
          ...target(),
          template: { ...TEMPLATE, type: "project", settings: { color: 1 } },
        }),
      }),
      types: { project },
    });

    expect(
      (await badSettings.apply({ template: "t1", options: { into: "o" } })).ok,
    ).toBe(false);

    const badBody = createTemplates({
      transport: transport({
        template_apply_target: () => ({
          ...target(),
          version: { ...VERSION, body: { tasks: 1 } },
        }),
      }),
      types: { project },
    });

    expect(
      (await badBody.apply({ template: "t1", options: { into: "o" } })).ok,
    ).toBe(false);
  });

  it("passes values and a key to the handler and returns recording errors", async () => {
    const seen: unknown[] = [];

    const typed = defineTemplateType({
      apply: (call) => {
        seen.push({ values: call.values, key: call.key });

        return { subject: { type: "project", id: "p1" } };
      },
    });

    const fake = transport({
      template_apply_target: () => target(),
      record_template_application: () => null,
    });

    const templates = createTemplates({
      transport: fake,
      types: { project: typed },
    });

    const failed = await templates.apply({
      template: "t1",
      options: { into: "o", values: { a: 1 }, key: "k1" },
    });

    expect(failed.ok).toBe(false);
    expect(seen).toEqual([{ values: { a: 1 }, key: "k1" }]);
  });

  it("records a workflow that fails to start", async () => {
    const fake = transport({
      template_apply_target: () => target([{ definition: "d1" }]),
      record_template_application: () => APPLICATION,
    });

    const templates = createTemplates({
      transport: fake,
      types: { project },
      workflows: {
        run: () => AsyncResult.err(dbError("unexpected", "no engine")),
      },
    });

    const result = await templates
      .apply({ template: "t1", options: { into: "o" } })
      .orThrow();

    expect(result.runs[0]).toMatchObject({
      definition: "d1",
      error: { message: "no engine" },
    });
  });

  it("lists applications without a filter and runs hooks and a logger", async () => {
    const fake = transport({ template_applications_list: () => [] });
    let called = 0;

    const templates = createTemplates({
      transport: fake,
      logger: {
        error: () => undefined,
        warn: () => undefined,
        info: () => undefined,
        debug: () => undefined,
      },
      hooks: {
        remove: {
          before: () => {
            called += 1;

            return;
          },
        },
      },
    });

    await templates.applications.list({ organizationId: "o" }).orThrow();
    expect(fake.calls[0]?.[1]).toMatchObject({
      template_id: null,
      subject_type: null,
      subject_id: null,
    });
    expect(called).toBe(0);
  });
});
