type Json = Record<string, unknown>;

/** One query parameter of a paged list: its name, text and JSON Schema. */
export interface PageQueryParameter {
  readonly name: string;
  readonly description: string;
  readonly schema: Json;
}

/** The `after` or `page` parameter and `size` of a list, for the spec and the MCP tools alike. */
export function pageQuery(
  cursor: boolean,
  maxPageSize: number,
): readonly PageQueryParameter[] {
  return [
    cursor
      ? {
          name: "after",
          description:
            "`nextCursor` of the previous page. Leave it out for the first page.",
          schema: { type: "string" },
        }
      : {
          name: "page",
          description: "1-based page number.",
          schema: { type: "integer", minimum: 1, default: 1 },
        },
    {
      name: "size",
      description: "Page size.",
      schema: {
        type: "integer",
        minimum: 1,
        maximum: maxPageSize,
        default: 50,
      },
    },
  ];
}

/** The list input as one object schema, for tools that take a body. */
export function pageInputSchema(cursor: boolean, maxPageSize: number): Json {
  return {
    type: "object",
    properties: Object.fromEntries(
      pageQuery(cursor, maxPageSize).map((p) => [p.name, p.schema]),
    ),
    additionalProperties: false,
  };
}

/** The page a list answers with: `items` plus the cursor or the page counts. */
export function pageSchema(row: unknown, cursor: boolean): Json {
  const items = { type: "array", items: row };

  return cursor
    ? {
        type: "object",
        required: ["items", "nextCursor", "hasMore"],
        properties: {
          items,
          nextCursor: { type: ["string", "null"] },
          hasMore: { type: "boolean" },
        },
      }
    : {
        type: "object",
        required: ["items", "page"],
        properties: {
          items,
          page: {
            type: "object",
            required: ["number", "size", "total", "pages", "hasMore"],
            properties: {
              number: { type: "integer" },
              size: { type: "integer" },
              total: { type: ["integer", "null"] },
              pages: { type: ["integer", "null"] },
              hasMore: { type: "boolean" },
            },
          },
        },
      };
}
