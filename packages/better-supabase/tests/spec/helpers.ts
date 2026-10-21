import type { StandardLike } from "../../src/spec/schemas.ts";

/** A Standard Schema that implements Standard JSON Schema with a fixed schema. */
export function standard(jsonSchema: Record<string, unknown>): StandardLike {
  return {
    "~standard": {
      version: 1,
      vendor: "test",
      validate: (value: unknown) => ({ value }),
      jsonSchema: { input: () => jsonSchema, output: () => jsonSchema },
    },
  };
}

/** A Standard Schema without Standard JSON Schema. */
export function opaque(): StandardLike {
  return {
    "~standard": {
      version: 1,
      vendor: "test",
      validate: (value: unknown) => ({ value }),
    },
  };
}

export function deepFreeze<T>(value: T): T {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value);

    for (const entry of Object.values(value)) {
      deepFreeze(entry);
    }
  }

  return value;
}

/** Every `$ref` value in a document. */
export function refsIn(value: unknown, out: string[] = []): string[] {
  if (Array.isArray(value)) {
    for (const item of value) {
      refsIn(item, out);
    }
  } else if (value && typeof value === "object") {
    for (const [key, item] of Object.entries(value)) {
      if (key === "$ref" && typeof item === "string") {
        out.push(item);
      } else {
        refsIn(item, out);
      }
    }
  }

  return out;
}
