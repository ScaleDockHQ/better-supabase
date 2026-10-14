import { describe, expect, it } from "vitest";

import {
  composeTemplateEmail,
  defineMergeFields,
  mergeFieldsIn,
  renderMergeFields,
} from "../../../src/blocks/templates/index.ts";

describe("renderMergeFields", () => {
  it("replaces fields, reading dotted names as a key first and then a path", () => {
    expect(
      renderMergeFields("Hi {{ customer.name }}, {{total}} due {{ due }}", {
        customer: { name: "Ada" },
        total: 120,
        due: Temporal.PlainDate.from("2026-11-01"),
      }),
    ).toBe("Hi Ada, 120 due 2026-11-01");
    expect(
      renderMergeFields("{{ customer.name }}", {
        "customer.name": "Flat",
        customer: { name: "Nested" },
      }),
    ).toBe("Flat");
  });

  it("escapes for HTML with {{ }} and leaves {{{ }}} raw", () => {
    const values = { name: `<b>"Ada" & 'co'</b>`, link: "<a href='/x'>x</a>" };
    expect(
      renderMergeFields("{{ name }} {{{ link }}}", values, { escape: "html" }),
    ).toBe(
      "&lt;b&gt;&quot;Ada&quot; &amp; &#39;co&#39;&lt;/b&gt; <a href='/x'>x</a>",
    );
    expect(renderMergeFields("{{ name }}", values)).toBe(values.name);
  });

  it("renders a missing field as empty, or keeps it", () => {
    expect(renderMergeFields("a{{ x }}b", {})).toBe("ab");
    expect(
      renderMergeFields("a{{ x }}b", { x: null }, { missing: "keep" }),
    ).toBe("a{{ x }}b");
  });

  it("formats arrays, objects and dates, and takes a custom format", () => {
    expect(
      renderMergeFields("{{ a }}|{{ o }}|{{ d }}", {
        a: ["x", 2],
        o: { k: 1 },
        d: new Date("2026-01-02T03:04:05Z"),
      }),
    ).toBe(`x, 2|{"k":1}|2026-01-02T03:04:05.000Z`);
    expect(
      renderMergeFields(
        "{{ total }}",
        { total: 1250 },
        { format: (value, name) => `${name}=${String(value)}` },
      ),
    ).toBe("total=1250");
  });

  it("does not read inherited properties", () => {
    expect(
      renderMergeFields("{{ toString }}{{ a.constructor }}", { a: {} }),
    ).toBe("");
  });
});

describe("defineMergeFields", () => {
  const invoice = defineMergeFields("invoice", {
    "customer.name": { label: "Customer", example: "Ada" },
    total: { label: "Total" },
  });

  it("lists names, unknown fields and examples", () => {
    expect(invoice.names).toEqual(["customer.name", "total"]);
    expect(mergeFieldsIn("{{ total }} {{{ x }}} {{ total }}")).toEqual([
      "total",
      "x",
    ]);
    expect(invoice.unknown("{{ total }} {{ nope }}")).toEqual(["nope"]);
    expect(invoice.examples()).toEqual({ "customer.name": "Ada" });
    expect(invoice.render("{{ total }}", { total: 3 })).toBe("3");
  });

  it("rejects names a template can't write", () => {
    expect(() => defineMergeFields("x", { "bad name": {} })).toThrow(
      /not a merge field name/,
    );
  });
});

describe("composeTemplateEmail", () => {
  it("renders the subject and text as text and the HTML escaped", () => {
    expect(
      composeTemplateEmail(
        {
          subject: "Invoice for {{ name }}",
          text: "Hi {{ name }}",
          html: "<p>Hi {{ name }}</p>",
        },
        { name: "A&B" },
        { category: "notification", templateKey: "invoice-v1" },
      ),
    ).toEqual({
      subject: "Invoice for A&B",
      text: "Hi A&B",
      html: "<p>Hi A&amp;B</p>",
      category: "notification",
      templateKey: "invoice-v1",
    });
  });
});
