import { describe, expect, it } from "vitest";

import type { GeneratorMetadata } from "../../../src/config/generator-metadata.ts";

import {
  compositeFields,
  resolveColumnType,
} from "../../../src/cli/gen/composites.ts";

type TypeEntry = GeneratorMetadata["types"][number];

const text: TypeEntry = {
  id: 25,
  name: "text",
  schema: "pg_catalog",
  format: "text",
  enums: [],
  attributes: [],
  comment: null,
  type_relation_id: null,
};

const address: TypeEntry = {
  id: 9001,
  name: "address",
  schema: "public",
  format: "address",
  enums: [],
  attributes: [{ name: "city", type_id: 25 }],
  comment: null,
  type_relation_id: null,
};

describe("resolveColumnType", () => {
  it("resolves a domain to its base type, not null and CHECK bounds", () => {
    expect(
      resolveColumnType(
        { name: "score", udt: "score", typeSchema: "public", isArray: false },
        {
          schema: "public",
          name: "score",
          baseType: "int4",
          baseSchema: "pg_catalog",
          notNull: false,
          checks: ["CHECK ((VALUE >= 0))", "CHECK ((VALUE IS NOT NULL))"],
        },
        [],
      ),
    ).toEqual({
      type: "int4",
      array: false,
      notNull: true,
      bounds: { minimum: 0 },
    });
  });

  it("treats an array domain base as an array of the element", () => {
    expect(
      resolveColumnType(
        { name: "tags", udt: "tag_list", typeSchema: "public", isArray: false },
        {
          schema: "public",
          name: "tag_list",
          baseType: "_text",
          baseSchema: "pg_catalog",
          notNull: false,
        },
        [],
      ).array,
    ).toBe(true);
  });
});

describe("compositeFields", () => {
  it("reads attributes, and skips a type it has already entered", () => {
    const loop: TypeEntry = {
      ...address,
      attributes: [
        { name: "city", type_id: 25 },
        { name: "self", type_id: 9001 },
      ],
    };

    expect(compositeFields([loop, text], "public", "address")).toEqual({
      city: { db: "city", type: "text", nullable: true },
      self: { db: "self", type: "address", nullable: true },
    });
  });
});
