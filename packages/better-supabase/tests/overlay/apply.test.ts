import { beforeAll, describe, expect, it } from "vitest";

import type {
  JsonPathEngine,
  Overlay,
  Overlay10,
  Overlay11,
  Overlay12,
} from "../../src/overlay/index.ts";

import {
  applyOverlay,
  applyOverlays,
  loadJsonPath,
} from "../../src/overlay/index.ts";

let jsonpath: JsonPathEngine;

beforeAll(async () => {
  jsonpath = await loadJsonPath();
});

const info = { title: "Test", version: "1.0.0" };

const base = () => ({
  openapi: "3.1.2",
  info: { title: "CRM", version: "1.0.0" },
  tags: [{ name: "customers" }],
  paths: {
    "/customers": {
      get: {
        operationId: "listCustomers",
        summary: "List",
        tags: ["customers"],
        parameters: [{ name: "limit", in: "query" }],
      },
      post: { operationId: "createCustomer", "x-internal": true },
    },
    "/orders": {
      get: { operationId: "listOrders", summary: "Orders", tags: ["orders"] },
    },
  },
});

const overlay11 = (actions: Overlay11["actions"]): Overlay11 => ({
  overlay: "1.1.0",
  info,
  actions,
});

describe("applyOverlay", () => {
  it("merges an object update into every selected object", () => {
    const { document, diagnostics } = applyOverlay(
      base(),
      overlay11([
        {
          target: "$.paths.*.get",
          update: { "x-audited": true, summary: "Changed" },
        },
      ]),
      { jsonpath },
    );

    expect(diagnostics).toEqual([]);
    expect(document.paths["/customers"].get).toMatchObject({
      "x-audited": true,
      summary: "Changed",
      operationId: "listCustomers",
    });
    expect(document.paths["/orders"].get).toMatchObject({
      "x-audited": true,
      summary: "Changed",
    });
  });

  it("merges recursively: arrays concatenate, objects merge, primitives replace", () => {
    const { document, diagnostics } = applyOverlay(
      base(),
      overlay11([
        {
          target: "$.paths['/customers'].get",
          update: {
            tags: ["crm"],
            parameters: [{ name: "cursor", in: "query" }],
            summary: "New",
          },
        },
        { target: "$.info", update: { contact: { name: "A" } } },
        { target: "$.info", update: { contact: { email: "a@b.c" } } },
      ]),
      { jsonpath },
    );

    expect(diagnostics).toEqual([]);
    const get = document.paths["/customers"].get;
    expect(get.tags).toEqual(["customers", "crm"]);
    expect(get.parameters.map((p) => p.name)).toEqual(["limit", "cursor"]);
    expect(get.summary).toBe("New");
    expect(document.info).toEqual({
      title: "CRM",
      version: "1.0.0",
      contact: { name: "A", email: "a@b.c" },
    });
  });

  it("concatenates an array and appends an object or primitive to arrays", () => {
    const { document } = applyOverlay(
      base(),
      overlay11([
        { target: "$.tags", update: [{ name: "a" }, { name: "b" }] },
        { target: "$.tags", update: { name: "c" } },
        { target: "$.paths.*.get.tags", update: "all" },
      ]),
      { jsonpath },
    );

    expect(document.tags.map((t) => t.name)).toEqual([
      "customers",
      "a",
      "b",
      "c",
    ]);
    expect(document.paths["/orders"].get.tags).toEqual(["orders", "all"]);
  });

  it("replaces selected primitives, including array items and the root", () => {
    const { document } = applyOverlay(
      base(),
      overlay11([
        { target: "$.paths.*.get.summary", update: "Same" },
        { target: "$.paths['/orders'].get.tags[0]", update: "sales" },
      ]),
      { jsonpath },
    );

    expect(document.paths["/customers"].get.summary).toBe("Same");
    expect(document.paths["/orders"].get).toMatchObject({
      summary: "Same",
      tags: ["sales"],
    });
    expect(
      applyOverlay("a", overlay11([{ target: "$", update: "b" }]), {
        jsonpath,
      }).document,
    ).toBe("b");
  });

  it("removes selected members and array items, highest index first", () => {
    const { document, diagnostics } = applyOverlay(
      { ...base(), list: [0, 1, 2, 3, 4] },
      overlay11([
        { target: "$.paths.*[?@['x-internal'] == true]", remove: true },
        { target: "$.list[?@ == 1 || @ == 3]", remove: true },
        { target: "$.info.title", remove: true, update: "ignored" },
      ]),
      { jsonpath },
    );

    expect(diagnostics).toEqual([]);
    expect(Object.keys(document.paths["/customers"])).toEqual(["get"]);
    expect(document.list).toEqual([0, 2, 4]);
    expect(document.info).toEqual({ version: "1.0.0" });
  });

  it("lets a later action re-create what an earlier one removed", () => {
    const { document } = applyOverlay(
      base(),
      overlay11([
        { target: "$.tags", remove: true },
        { target: "$", update: { tags: [{ name: "fresh" }] } },
      ]),
      { jsonpath },
    );

    expect(document.tags).toEqual([{ name: "fresh" }]);
  });

  it("rejects removing the root", () => {
    const { document, diagnostics } = applyOverlay(
      base(),
      overlay11([{ target: "$", remove: true }]),
      { jsonpath },
    );

    expect(document).toEqual(base());
    expect(diagnostics).toEqual([
      expect.objectContaining({
        code: "overlay-invalid-action",
        severity: "error",
        pointer: "/actions/0",
      }),
    ]);
  });

  it("copies the value of a single source node (1.1)", () => {
    const { document, diagnostics } = applyOverlay(
      base(),
      overlay11([
        {
          target: "$.paths['/orders'].get",
          copy: "$.paths['/customers'].get.parameters",
          description: "array copied into an object is a conflict",
        },
        {
          target: "$.paths['/orders'].get.tags",
          copy: "$.paths['/customers'].get.tags",
        },
        { target: "$.paths['/orders']", copy: "$.paths['/customers']" },
      ]),
      { jsonpath },
    );

    expect(diagnostics).toEqual([
      expect.objectContaining({
        code: "overlay-merge-conflict",
        pointer: "/actions/0",
      }),
    ]);
    expect(document.paths["/orders"].get.tags).toEqual([
      "orders",
      "customers",
      "customers",
    ]);
    expect(document.paths["/orders"]).toHaveProperty("post.operationId");
  });

  it("prefers update over copy", () => {
    const { document } = applyOverlay(
      base(),
      overlay11([
        { target: "$.info", update: { a: 1 }, copy: "$.paths['/orders']" },
      ]),
      { jsonpath },
    );

    expect(document.info).toEqual({ title: "CRM", version: "1.0.0", a: 1 });
  });

  it("reports a copy source that selects zero or several nodes", () => {
    const { diagnostics } = applyOverlay(
      base(),
      overlay11([
        { target: "$.info", copy: "$.missing" },
        { target: "$.info", copy: "$.paths.*" },
        { target: "$.info", copy: "$[" },
      ]),
      { jsonpath },
    );

    expect(diagnostics.map((d) => [d.code, d.pointer])).toEqual([
      ["overlay-copy-source", "/actions/0"],
      ["overlay-copy-source", "/actions/1"],
      ["overlay-invalid-target", "/actions/2"],
    ]);
    expect(diagnostics[2]?.message).toContain("copy source");
  });

  it("rejects copy in Overlay 1.0", () => {
    const overlay: Overlay = {
      overlay: "1.0.0",
      info,
      actions: [
        { target: "$.info", copy: "$.paths" } as Overlay10["actions"][number],
      ],
    };

    const { document, diagnostics } = applyOverlay(base(), overlay, {
      jsonpath,
    });

    expect(document).toEqual(base());
    expect(diagnostics).toEqual([
      expect.objectContaining({
        code: "overlay-version-feature",
        severity: "error",
      }),
    ]);
  });

  it("applies Overlay 1.0 updates and removals, and accepts patch versions", () => {
    const overlay: Overlay10 = {
      overlay: "1.0.0",
      info,
      actions: [
        { target: "$.info", update: { "x-v": 1 } },
        { target: "$.tags", remove: true },
      ],
    };

    const { document, diagnostics } = applyOverlay(base(), overlay, {
      jsonpath,
    });

    expect(diagnostics).toEqual([]);
    expect(document.info).toHaveProperty("x-v", 1);
    expect(document).not.toHaveProperty("tags");
    // SAFETY: the type lists x.y.0 versions; tooling ignores the patch (Overlay § 4.1).
    const patched = { ...overlay, overlay: "1.0.3" } as unknown as Overlay;
    expect(applyOverlay(base(), patched, { jsonpath }).diagnostics).toEqual([]);
  });

  it("reports targets that select nothing, unless allowed", () => {
    const actions: Overlay11["actions"] = [
      { target: "$.paths['/gone'].get", update: { summary: "x" } },
      {
        target: "$.paths['/gone']",
        remove: true,
        "x-better-supabase-allow-empty": true,
      },
    ];

    const strict = applyOverlay(base(), overlay11(actions), { jsonpath });
    expect(strict.diagnostics).toEqual([
      {
        code: "overlay-no-match",
        severity: "error",
        message: expect.stringContaining("$.paths['/gone'].get"),
        pointer: "/actions/0",
      },
    ]);

    const lenient = applyOverlay(base(), overlay11(actions), {
      jsonpath,
      allowEmpty: true,
    });

    expect(lenient.diagnostics).toEqual([]);
  });

  it("reports invalid targets and keeps going", () => {
    const { document, diagnostics } = applyOverlay(
      base(),
      overlay11([
        { target: "paths", update: {} },
        { target: "$.info", update: { ok: true } },
      ]),
      { jsonpath },
    );

    expect(diagnostics.map((d) => d.code)).toEqual(["overlay-invalid-target"]);
    expect(document.info).toHaveProperty("ok", true);
  });

  it("reports engine errors that are not Error instances", () => {
    const throwing: JsonPathEngine = {
      paths: () => {
        // oxlint-disable-next-line typescript/only-throw-error -- an engine may throw anything
        throw "boom";
      },
    };

    const { diagnostics } = applyOverlay(
      {},
      overlay11([{ target: "$", update: {} }]),
      { jsonpath: throwing },
    );

    expect(diagnostics[0]?.message).toContain("boom");
  });

  it("reports malformed paths from the engine", () => {
    const broken: JsonPathEngine = { paths: () => ["$.a"] };

    const { diagnostics } = applyOverlay(
      { a: {} },
      overlay11([{ target: "$.a", update: {} }]),
      { jsonpath: broken },
    );

    expect(diagnostics.map((d) => d.code)).toEqual(["overlay-invalid-target"]);
  });

  it("reports mixed target kinds and merge conflicts", () => {
    const { diagnostics, document } = applyOverlay(
      base(),
      overlay11([
        { target: "$.paths['/orders'].get.*", update: "x" },
        { target: "$.info", update: "x" },
        { target: "$.info", update: ["x"] },
        { target: "$.openapi", update: { a: 1 } },
        { target: "$.openapi", update: [1] },
        { target: "$.paths['/customers']", update: { get: { tags: "x" } } },
      ]),
      { jsonpath },
    );

    expect(diagnostics.map((d) => [d.code, d.pointer])).toEqual([
      ["overlay-mixed-targets", "/actions/0"],
      ["overlay-merge-conflict", "/actions/1"],
      ["overlay-merge-conflict", "/actions/2"],
      ["overlay-merge-conflict", "/actions/3"],
      ["overlay-merge-conflict", "/actions/4"],
      ["overlay-merge-conflict", "/actions/5"],
    ]);
    expect(diagnostics[5]?.message).toContain("/paths/~1customers/get/tags");
    expect(document.openapi).toBe("3.1.2");
  });

  it("warns about an action that changes nothing and reports malformed entries", () => {
    const overlay = {
      overlay: "1.1.0",
      info,
      actions: [{ target: "$.info" }, "nope", { update: {} }],
    };

    // SAFETY: the test feeds a malformed overlay on purpose.
    const malformed = overlay as unknown as Overlay;
    const { diagnostics } = applyOverlay(base(), malformed, { jsonpath });
    expect(diagnostics.map((d) => [d.code, d.severity, d.pointer])).toEqual([
      ["overlay-empty-action", "warning", "/actions/0"],
      ["overlay-invalid-action", "error", "/actions/1"],
      ["overlay-invalid-action", "error", "/actions/2"],
    ]);
  });

  it("rejects unsupported versions and a missing actions array", () => {
    // SAFETY: the test feeds malformed overlays on purpose.
    const wrongVersion = {
      overlay: "2.0.0",
      info,
      actions: [],
    } as unknown as Overlay;

    // SAFETY: as above.
    const noActions = { overlay: "1.1.0", info } as unknown as Overlay;
    expect(
      applyOverlay(base(), wrongVersion, { jsonpath }).diagnostics,
    ).toEqual([
      expect.objectContaining({
        code: "overlay-version-unsupported",
        pointer: "/overlay",
      }),
    ]);
    expect(applyOverlay(base(), noActions, { jsonpath }).diagnostics).toEqual([
      expect.objectContaining({
        code: "overlay-invalid-action",
        pointer: "/actions",
      }),
    ]);
  });

  it("never changes its inputs and gives the same result every time", () => {
    const input = base();
    const snapshot = structuredClone(input);
    const update = { tags: ["new"] };

    const overlay = overlay11([
      { target: "$.paths.*.get", update },
      { target: "$.tags", remove: true },
    ]);

    const first = applyOverlay(input, overlay, { jsonpath });
    const second = applyOverlay(input, overlay, { jsonpath });
    expect(input).toEqual(snapshot);
    expect(update).toEqual({ tags: ["new"] });
    expect(JSON.stringify(first.document)).toBe(
      JSON.stringify(second.document),
    );
    // Each target gets its own copy of the update value.
    first.document.paths["/customers"].get.tags.push("mutated");
    expect(first.document.paths["/orders"].get.tags).toEqual(["orders", "new"]);
  });

  it("calls the engine once per target", () => {
    let calls = 0;

    const counting: JsonPathEngine = {
      paths: (doc, expression) => {
        calls++;

        return jsonpath.paths(doc, expression);
      },
    };

    applyOverlay(
      base(),
      overlay11([
        { target: "$.paths.*.get", update: { a: 1 } },
        { target: "$.info", copy: "$.paths['/orders'].get" },
      ]),
      { jsonpath: counting },
    );
    expect(calls).toBe(3);
  });
});

describe("reusable actions (1.2)", () => {
  const overlay12: Overlay12 = {
    overlay: "1.2.0",
    $self: "https://example.com/public.overlay.yaml",
    info,
    components: {
      actions: {
        audited: {
          description: "Marks an operation as audited",
          fields: { update: { "x-audited": true }, description: "shared" },
        },
        "drop/internal": { fields: { remove: true } },
        stray: {
          fields: { target: "$.nope", update: { stray: true } } as never,
        },
      },
    },
    actions: [
      { $ref: "#/components/actions/audited", target: "$.paths.*.get" },
      {
        $ref: "#/components/actions/audited",
        target: "$.info",
        update: { "x-audited": "overridden" },
      },
      {
        $ref: "#/components/actions/drop~1internal",
        target: "$.paths.*.post",
      },
    ],
  };

  it("expands references, with the reference's fields on top", () => {
    const { document, diagnostics } = applyOverlay(base(), overlay12, {
      jsonpath,
    });

    expect(diagnostics).toEqual([]);
    expect(document.paths["/customers"].get).toHaveProperty("x-audited", true);
    expect(document.paths["/orders"].get).toHaveProperty("x-audited", true);
    expect(document.info).toHaveProperty("x-audited", "overridden");
    expect(document.paths["/customers"]).not.toHaveProperty("post");
  });

  it("ignores a target inside reusable fields, with a warning", () => {
    const { document, diagnostics } = applyOverlay(
      base(),
      {
        ...overlay12,
        actions: [{ $ref: "#/components/actions/stray", target: "$.info" }],
      },
      { jsonpath },
    );

    expect(diagnostics.map((d) => [d.code, d.severity])).toEqual([
      ["overlay-invalid-action", "warning"],
    ]);
    expect(document.info).toHaveProperty("stray", true);
  });

  it("reports references that do not resolve", () => {
    const actions = [
      { $ref: "#/components/actions/missing", target: "$.info" },
      { $ref: "#/elsewhere", target: "$.info" },
    ];

    // SAFETY: the second reference is malformed on purpose.
    const malformed = { ...overlay12, actions } as unknown as Overlay12;
    const { diagnostics } = applyOverlay(base(), malformed, { jsonpath });
    expect(diagnostics.map((d) => [d.code, d.pointer])).toEqual([
      ["overlay-ref-unresolved", "/actions/0"],
      ["overlay-ref-unresolved", "/actions/1"],
    ]);
    const { components: _, ...withoutComponents } = overlay12;
    expect(
      applyOverlay(base(), withoutComponents, { jsonpath }).diagnostics.map(
        (d) => d.code,
      ),
    ).toEqual([
      "overlay-ref-unresolved",
      "overlay-ref-unresolved",
      "overlay-ref-unresolved",
    ]);
  });

  it("reports a reference whose target is missing", () => {
    const actions = [{ $ref: "#/components/actions/audited" }];
    // SAFETY: the reference has no target on purpose.
    const malformed = { ...overlay12, actions } as unknown as Overlay12;
    expect(
      applyOverlay(base(), malformed, { jsonpath }).diagnostics.map(
        (d) => d.code,
      ),
    ).toEqual(["overlay-invalid-action"]);
  });

  it("expands references in a 1.1 overlay, with a warning", () => {
    // SAFETY: a 1.1 overlay that uses a 1.2 feature, on purpose.
    const mixed = { ...overlay12, overlay: "1.1.0" } as unknown as Overlay;

    const { document, diagnostics } = applyOverlay(base(), mixed, {
      jsonpath,
    });

    expect(diagnostics.map((d) => [d.code, d.severity])).toEqual([
      ["overlay-version-feature", "warning"],
      ["overlay-version-feature", "warning"],
      ["overlay-version-feature", "warning"],
    ]);
    expect(document.info).toHaveProperty("x-audited", "overridden");
  });
});

describe("applyOverlays", () => {
  it("applies overlays in order with pointers per overlay", () => {
    const { document, diagnostics } = applyOverlays(
      base(),
      [
        overlay11([{ target: "$.info", update: { step: 1 } }]),
        overlay11([
          { target: "$.info.step", update: 2 },
          { target: "$.nothing", remove: true },
        ]),
      ],
      { jsonpath },
    );

    expect(document.info).toHaveProperty("step", 2);
    expect(diagnostics).toEqual([
      expect.objectContaining({
        code: "overlay-no-match",
        pointer: "/1/actions/1",
      }),
    ]);
  });

  it("returns an equal copy for an empty list", () => {
    const input = base();
    const { document } = applyOverlays(input, [], { jsonpath });
    expect(document).toEqual(input);
    expect(document).not.toBe(input);
  });
});
