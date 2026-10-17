import type {
  ModelOperation,
  ModelStep,
  ModelWorkflow,
} from "../spec/model.ts";
import type { WorkflowSource } from "../spec/options.ts";

import { pascal } from "../spec/schemas.ts";

type ModelStepParameter = NonNullable<ModelStep["parameters"]>[number];

const resourceOf = (
  operations: readonly ModelOperation[],
  table: string,
  operation: string,
): ModelOperation | undefined =>
  operations.find(
    (candidate) =>
      candidate.source.kind === "resource" &&
      candidate.source.table === table &&
      candidate.source.operation === operation,
  );

const tablesOf = (operations: readonly ModelOperation[]): string[] => [
  ...new Set(
    operations.flatMap((operation) =>
      operation.source.kind === "resource" ? [operation.source.table] : [],
    ),
  ),
];

const inputParameter = (parameter: {
  readonly name: string;
}): ModelStepParameter => ({
  name: parameter.name,
  in: "path",
  value: `$inputs.${parameter.name}`,
});

const pathParameter = (operation: ModelOperation): string | undefined =>
  operation.parameters.find((parameter) => parameter.in === "path")?.name;

export interface BuiltinWorkflowOptions {
  /** Only these tables; defaults to every resource that qualifies. */
  readonly tables?: readonly string[];
}

/**
 * One workflow per cursor-paginated list: read the first page, then the
 * next one from its `nextCursor` when `hasMore` is true. Repeat the second
 * step with its own `nextCursor` to walk the rest.
 */
export function paginationWorkflows(
  options: BuiltinWorkflowOptions = {},
): WorkflowSource {
  return (operations) =>
    tablesOf(operations)
      .filter((table) => !options.tables || options.tables.includes(table))
      .flatMap((table): ModelWorkflow[] => {
        const list = resourceOf(operations, table, "list");
        if (
          !list?.parameters.some(
            (parameter) =>
              parameter.name === "after" && parameter.in === "query",
          )
        ) {
          return [];
        }
        const name = pascal(table);
        return [
          {
            id: `paginate${name}`,
            summary: `Read ${table} page by page`,
            description:
              "Reads the first page, then the next one with the cursor the first page returned. Repeat `nextPage` with its own `nextCursor` until `hasMore` is false.",
            inputs: {
              type: "object",
              properties: {
                size: {
                  type: "integer",
                  minimum: 1,
                  description: "Page size.",
                },
              },
            },
            steps: [
              {
                id: "firstPage",
                operationId: list.id,
                parameters: [
                  { name: "size", in: "query", value: "$inputs.size" },
                ],
                successCriteria: [{ condition: "$statusCode == 200" }],
                outputs: {
                  items: "$response.body#/items",
                  nextCursor: "$response.body#/nextCursor",
                  hasMore: "$response.body#/hasMore",
                },
                onSuccess: [
                  {
                    name: "lastPage",
                    type: "end",
                    criteria: [
                      { condition: "$response.body#/hasMore == false" },
                    ],
                  },
                ],
              },
              {
                id: "nextPage",
                operationId: list.id,
                parameters: [
                  { name: "size", in: "query", value: "$inputs.size" },
                  {
                    name: "after",
                    in: "query",
                    value: "$steps.firstPage.outputs.nextCursor",
                  },
                ],
                successCriteria: [{ condition: "$statusCode == 200" }],
                outputs: {
                  items: "$response.body#/items",
                  nextCursor: "$response.body#/nextCursor",
                  hasMore: "$response.body#/hasMore",
                },
              },
            ],
            outputs: {
              firstPage: "$steps.firstPage.outputs.items",
              nextCursor: "$steps.nextPage.outputs.nextCursor",
            },
          },
        ];
      });
}

/** One workflow per resource with `create` and `get`: create a row, then read it back by its key. */
export function createThenGetWorkflows(
  options: BuiltinWorkflowOptions = {},
): WorkflowSource {
  return (operations) =>
    tablesOf(operations)
      .filter((table) => !options.tables || options.tables.includes(table))
      .flatMap((table): ModelWorkflow[] => {
        const create = resourceOf(operations, table, "create");
        const get = resourceOf(operations, table, "get");
        const key = get ? pathParameter(get) : undefined;
        if (!create || !get || key === undefined) {
          return [];
        }
        const name = pascal(table);
        return [
          {
            id: `createThenGet${name}`,
            summary: `Create a ${table} row, then read it back`,
            inputs: {
              type: "object",
              required: ["row"],
              properties: {
                row: { type: "object", description: "The row to insert." },
              },
            },
            steps: [
              {
                id: "create",
                operationId: create.id,
                requestBody: { payload: "$inputs.row" },
                successCriteria: [{ condition: "$statusCode == 201" }],
                outputs: { key: `$response.body#/${key}` },
              },
              {
                id: "get",
                operationId: get.id,
                parameters: [
                  { name: key, in: "path", value: "$steps.create.outputs.key" },
                ],
                successCriteria: [{ condition: "$statusCode == 200" }],
                outputs: { row: "$response.body" },
              },
            ],
            outputs: { row: "$steps.get.outputs.row" },
          },
        ];
      });
}

export interface AuthWorkflowOptions {
  /** The operationId to call once signed in. */
  readonly call: string;
  /** The sign-in operationId: it takes `email` and `password` and returns a token. Defaults to `signIn`. */
  readonly signIn?: string;
  /** JSON Pointer to the access token in the sign-in response. Defaults to `/access_token`. */
  readonly tokenPointer?: string;
  /** Defaults to `signInThen<Call>`. */
  readonly id?: string;
}

/**
 * Sign in, then call an operation with the access token as a bearer
 * token. A 403 Problem Details answer with code `APPROVAL_REQUIRED` ends the
 * workflow (the `approvalRequired` failure action), so a client can wait for
 * the approval instead of retrying.
 */
export function authWorkflow(options: AuthWorkflowOptions): WorkflowSource {
  const signIn = options.signIn ?? "signIn";
  const pointer = options.tokenPointer ?? "/access_token";
  return (operations) => {
    const call = operations.find((operation) => operation.id === options.call);
    const pathParameters =
      call?.parameters.filter((parameter) => parameter.in === "path") ?? [];
    return [
      {
        id: options.id ?? `signInThen${pascal(options.call)}`,
        summary: `Sign in, then call ${options.call}`,
        inputs: {
          type: "object",
          required: ["email", "password", ...pathParameters.map((p) => p.name)],
          properties: {
            email: { type: "string", format: "email" },
            password: { type: "string", format: "password" },
            ...Object.fromEntries(
              pathParameters.map((parameter) => [
                parameter.name,
                { type: "string" },
              ]),
            ),
          },
        },
        steps: [
          {
            id: "signIn",
            operationId: signIn,
            requestBody: {
              payload: { email: "$inputs.email", password: "$inputs.password" },
            },
            successCriteria: [{ condition: "$statusCode == 200" }],
            outputs: { accessToken: `$response.body#${pointer}` },
          },
          {
            id: "call",
            operationId: options.call,
            parameters: [
              {
                name: "Authorization",
                in: "header",
                value: "Bearer {$steps.signIn.outputs.accessToken}",
              },
              ...pathParameters.map(inputParameter),
            ],
            outputs: { body: "$response.body" },
            onFailure: [
              {
                name: "approvalRequired",
                type: "end",
                criteria: [
                  { condition: "$statusCode == 403" },
                  {
                    context: "$response.body",
                    condition: "$.code == 'APPROVAL_REQUIRED'",
                    type: "jsonpath",
                  },
                ],
              },
            ],
          },
        ],
        outputs: { body: "$steps.call.outputs.body" },
      },
    ];
  };
}
