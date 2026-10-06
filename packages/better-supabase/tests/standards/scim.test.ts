import { readFile } from "node:fs/promises";
import { describe, expect, it } from "vitest";

import type { ScimAttribute } from "../../src/blocks/sso/index.ts";

import { parseScimFilter, scimHandler } from "../../src/blocks/sso/index.ts";
import {
  GROUP_ATTRIBUTES,
  resourceTypes,
  schemas,
  serviceProviderConfig,
  USER_ATTRIBUTES,
} from "../../src/blocks/sso/scim-schema.ts";
import { AsyncResult, ok } from "../../src/core/result.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";

const folder = new URL("schemas/", import.meta.url);

/** The RFC text without page breaks: running headers, footers and form feeds. */
async function rfc(number: 7643 | 7644): Promise<string[]> {
  const text = await readFile(new URL(`rfc${number}.txt`, folder), "utf8");
  const title =
    number === 7643 ? "SCIM Core Schema" : "SCIM Protocol Specification";
  return text
    .replaceAll("\f", "")
    .split("\n")
    .filter(
      (line) =>
        !/^Hunt, et al\.\s+Standards Track\s+\[Page \d+\]$/.test(line) &&
        !new RegExp(`^RFC ${number}\\s+${title}\\s+September 2015$`).test(line),
    );
}

interface RfcAttribute {
  readonly name: string;
  readonly type: string;
  readonly multiValued: boolean;
  readonly required: boolean;
  readonly caseExact?: boolean;
  readonly mutability: string;
  readonly returned: string;
  readonly uniqueness?: string;
  readonly canonicalValues?: readonly string[];
  readonly referenceTypes?: readonly string[];
  readonly subAttributes?: readonly RfcAttribute[];
}

interface RfcSchema {
  readonly id: string;
  readonly attributes: readonly RfcAttribute[];
}

/** The JSON array after a §8.7 heading; strings that wrap across lines join with spaces. */
async function section(heading: string): Promise<RfcSchema[]> {
  const lines = await rfc(7643);
  const start = lines.findIndex((line) => line.startsWith(heading));
  const open = lines.findIndex((line, index) => index > start && line === "[");
  const close = lines.findIndex((line, index) => index > open && line === "]");
  return JSON.parse(lines.slice(open, close + 1).join(" ")) as RfcSchema[];
}

const resources = await section("8.7.1.  Resource Schema Representation");
const providers = await section(
  "8.7.2.  Service Provider Schema Representation",
);
const schemaOf = (list: readonly RfcSchema[], id: string): RfcSchema =>
  list.find((schema) => schema.id === id)!;

function compare(
  ours: readonly ScimAttribute[],
  theirs: readonly RfcAttribute[],
  where: string,
): string[] {
  const problems: string[] = [];
  for (const attribute of ours) {
    const path = `${where}.${attribute.name}`;
    const rfcAttribute = theirs.find(
      (candidate) => candidate.name === attribute.name,
    );
    if (!rfcAttribute) {
      problems.push(`${path} is not in RFC 7643`);
      continue;
    }
    for (const key of [
      "type",
      "multiValued",
      "caseExact",
      "mutability",
      "returned",
      "uniqueness",
      "referenceTypes",
    ] as const) {
      if (
        key in rfcAttribute &&
        JSON.stringify(attribute[key]) !== JSON.stringify(rfcAttribute[key])
      ) {
        problems.push(
          `${path}.${key} is ${JSON.stringify(attribute[key])}, RFC 7643 says ${JSON.stringify(rfcAttribute[key])}`,
        );
      }
    }
    if (rfcAttribute.required && !attribute.required) {
      problems.push(`${path} is required in RFC 7643`);
    }
    for (const value of attribute.canonicalValues ?? []) {
      if (!rfcAttribute.canonicalValues?.includes(value)) {
        problems.push(
          `${path} lists canonical value ${value} that RFC 7643 lacks`,
        );
      }
    }
    if (attribute.subAttributes) {
      problems.push(
        ...compare(
          attribute.subAttributes,
          rfcAttribute.subAttributes ?? [],
          path,
        ),
      );
    }
  }
  return problems;
}

/** Required attributes of an RFC 7643 §8.7.2 schema that `doc` lacks, with sub-attributes. */
function missing(
  doc: Record<string, unknown>,
  attributes: readonly RfcAttribute[],
  where: string,
): string[] {
  const problems: string[] = [];
  for (const attribute of attributes) {
    const value = doc[attribute.name];
    if (value === undefined) {
      if (attribute.required) problems.push(`${where}.${attribute.name}`);
      continue;
    }
    if (attribute.type === "complex" && attribute.subAttributes) {
      // RFC 7643 §8.7.2 marks schemaExtensions single-valued; §6 makes it a list.
      const items = Array.isArray(value)
        ? (value as Record<string, unknown>[])
        : [value as Record<string, unknown>];
      for (const item of items) {
        problems.push(
          ...missing(
            item,
            attribute.subAttributes,
            `${where}.${attribute.name}`,
          ),
        );
      }
    }
    if (attribute.type === "boolean" && typeof value !== "boolean") {
      problems.push(`${where}.${attribute.name} is not a boolean`);
    }
    if (attribute.type === "integer" && !Number.isInteger(value)) {
      problems.push(`${where}.${attribute.name} is not an integer`);
    }
  }
  return problems;
}

describe("SCIM 2.0 (RFC 7643, RFC 7644)", () => {
  it("pins SCIM 2.0", () => {
    expect(SPEC_PINS.scim).toBe("2.0");
  });

  it("declares User and Group attributes with the characteristics of RFC 7643 §8.7.1", () => {
    expect(
      compare(
        USER_ATTRIBUTES,
        schemaOf(resources, "urn:ietf:params:scim:schemas:core:2.0:User")
          .attributes,
        "User",
      ),
    ).toEqual([]);
    expect(
      compare(
        GROUP_ATTRIBUTES,
        schemaOf(resources, "urn:ietf:params:scim:schemas:core:2.0:Group")
          .attributes,
        "Group",
      ),
    ).toEqual([]);
  });

  it("serves discovery documents with every attribute RFC 7643 §8.7.2 requires", () => {
    const base = "https://app.test/scim/v2";
    const config = schemaOf(
      providers,
      "urn:ietf:params:scim:schemas:core:2.0:ServiceProviderConfig",
    );
    expect(
      missing(
        serviceProviderConfig(base, { maxResults: 100 }),
        config.attributes,
        "ServiceProviderConfig",
      ),
    ).toEqual([]);
    const resourceType = schemaOf(
      providers,
      "urn:ietf:params:scim:schemas:core:2.0:ResourceType",
    );
    for (const doc of resourceTypes(base)) {
      expect(missing(doc, resourceType.attributes, "ResourceType")).toEqual([]);
    }
    const schema = schemaOf(
      providers,
      "urn:ietf:params:scim:schemas:core:2.0:Schema",
    );
    for (const doc of schemas(base)) {
      expect(missing(doc, schema.attributes, String(doc["id"]))).toEqual([]);
    }
  });

  it("parses every example filter of RFC 7644 §3.4.2.2", async () => {
    const lines = await rfc(7644);
    const start = lines.findIndex((line) =>
      line.includes("The following are examples of valid filters."),
    );
    const end = lines.findIndex(
      (line, index) =>
        index > start && line.includes("Figure 2: Example Filters"),
    );
    const filters = lines
      .slice(start + 1, end)
      .join("\n")
      .split(/\n\s*\n/)
      .map((block) => block.replaceAll(/\s+/g, " ").trim())
      .filter((block) => block.startsWith("filter="))
      .map((block) => block.slice("filter=".length).trim());
    expect(filters).toHaveLength(17);
    for (const filter of filters) {
      expect(() => parseScimFilter(filter)).not.toThrow();
    }
  });

  it("answers errors and lists with the RFC 7644 message shapes", async () => {
    const handler = scimHandler({
      transport: { call: () => Promise.resolve([]) },
      keys: {
        verify: () =>
          AsyncResult.from(async () =>
            ok({
              status: "ok" as const,
              key: {
                id: "k",
                organizationId: "org",
                userId: undefined,
                name: "idp",
                prefix: "bs",
                publicId: "p",
                scopes: ["scim"],
              } as never,
            }),
          ),
      },
    });
    const headers = { authorization: "Bearer t" };
    const list = await handler(
      new Request("https://app.test/Users", { headers }),
    );
    expect(list.headers.get("content-type")).toBe("application/scim+json");
    expect(await list.json()).toEqual({
      schemas: ["urn:ietf:params:scim:api:messages:2.0:ListResponse"],
      totalResults: 0,
      startIndex: 1,
      itemsPerPage: 0,
      Resources: [],
    });
    const error = await handler(
      new Request(
        `https://app.test/Users?filter=${encodeURIComponent("userName zz 1")}`,
        { headers },
      ),
    );
    expect(error.status).toBe(400);
    const body = (await error.json()) as Record<string, unknown>;
    expect(body).toMatchObject({
      schemas: ["urn:ietf:params:scim:api:messages:2.0:Error"],
      status: "400",
      scimType: "invalidFilter",
    });
    expect(typeof body["detail"]).toBe("string");
  });
});
