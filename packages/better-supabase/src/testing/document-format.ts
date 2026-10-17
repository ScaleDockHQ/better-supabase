import type {
  AnyDocumentFormat,
  DocumentFormat,
  SpecDiagnostic,
  VersionOf,
} from "../spec/format.ts";
import type { ApiModel, JsonSchema } from "../spec/model.ts";
import type { StandardLike } from "../spec/schemas.ts";

import { buildApiModel } from "../spec/build.ts";
import {
  type ConformanceReport,
  conform,
  expect,
  frozenCopy,
  same,
} from "./conformance.ts";

export interface TestDocumentFormatOptions<V extends string = string> {
  /**
   * The model to lower. Defaults to a small model with a route, a stream,
   * a webhook, a Realtime channel and a workflow.
   */
  readonly model?: ApiModel;
  /** The versions to lower. Defaults to every version the format lists. */
  readonly versions?: readonly V[];
}

const STATUSES: ReadonlySet<string> = new Set(["stable", "legacy", "preview"]);
const SEVERITIES: ReadonlySet<string> = new Set(["error", "warning", "info"]);
const CODE = /^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/;

const jsonSchema = (schema: JsonSchema): StandardLike => ({
  "~standard": {
    version: 1,
    vendor: "better-supabase-conformance",
    validate: (value: unknown) => ({ value }),
    jsonSchema: { input: () => schema, output: () => schema },
  },
});

function sampleModel(): ApiModel {
  const customer = {
    type: "object",
    required: ["id", "name"],
    properties: {
      id: { type: "string", format: "uuid" },
      name: { type: "string" },
      note: { type: ["string", "null"] },
    },
  };

  return buildApiModel(
    {
      meta: {
        version: 1,
        casing: "camel",
        tables: {},
        enums: {},
        functions: {},
      },
    },
    {
      info: { title: "Conformance", version: "1.0.0" },
      servers: [{ url: "https://api.test", name: "test" }],
      tags: [{ name: "customers", summary: "Customers" }],
      basePath: "/api",
      routes: [
        {
          method: "get",
          path: "/customers/{id}",
          operationId: "getCustomer",
          tags: ["customers"],
          output: jsonSchema(customer),
        },
        {
          method: "post",
          path: "/customers",
          operationId: "createCustomer",
          tags: ["customers"],
          input: jsonSchema(customer),
          output: jsonSchema(customer),
          status: 201,
        },
        {
          method: "get",
          path: "/customers/changes",
          operationId: "streamCustomerChanges",
          stream: { item: jsonSchema(customer) },
        },
      ],
      webhooks: [
        {
          id: "customer.created",
          payload: customer,
          standardWebhooks: true,
        },
      ],
      realtimeUrl: "wss://abc.supabase.co/realtime/v1/websocket",
      messages: {
        customerChanged: { id: "customerChanged", payload: customer },
      },
      channels: [
        {
          id: "customers",
          address: "bs:t:public.customers",
          protocol: "ws",
          messages: ["customerChanged"],
          operations: [{ id: "onCustomerChanged", action: "receive" }],
        },
      ],
      workflows: [
        {
          id: "createThenGet",
          steps: [
            {
              id: "create",
              operationId: "createCustomer",
              outputs: { id: "$response.body#/id" },
            },
            {
              id: "get",
              operationId: "getCustomer",
              parameters: [
                { name: "id", in: "path", value: "$steps.create.outputs.id" },
              ],
            },
          ],
        },
      ],
      security: ["bearer"],
    },
  ).model;
}

function isPlainJson(value: unknown): boolean {
  if (
    value === null ||
    typeof value === "string" ||
    typeof value === "boolean"
  ) {
    return true;
  }

  if (typeof value === "number") {
    return Number.isFinite(value);
  }

  if (Array.isArray(value)) {
    return value.every(isPlainJson);
  }

  if (typeof value !== "object") {
    return false;
  }

  const prototype: unknown = Object.getPrototypeOf(value);

  if (prototype !== Object.prototype && prototype !== null) {
    return false;
  }

  return Object.values(value).every(
    (entry) => entry !== undefined && isPlainJson(entry),
  );
}

function diagnosticProblem(diagnostic: SpecDiagnostic): string | undefined {
  if (typeof diagnostic.code !== "string" || !CODE.test(diagnostic.code)) {
    return `the code ${JSON.stringify(diagnostic.code)} is not kebab-case`;
  }

  const severity: unknown = diagnostic.severity;

  if (typeof severity !== "string" || !SEVERITIES.has(severity)) {
    return `${diagnostic.code} has the severity ${String(severity)}`;
  }

  if (typeof diagnostic.message !== "string" || diagnostic.message === "") {
    return `${diagnostic.code} has no message`;
  }

  if (
    diagnostic.pointer !== undefined &&
    !/^(?:\/|$)/.test(diagnostic.pointer)
  ) {
    return `${diagnostic.code} has the pointer ${diagnostic.pointer}, which is not a JSON Pointer`;
  }

  return undefined;
}

/**
 * Proves a `DocumentFormat` targets API v1, lists versions with pins and a
 * known status, defaults to a version it lists that is not a preview, and,
 * for every version: lowers the model without mutating it (also when the
 * model is frozen), renders the same document twice, renders plain JSON or
 * text, reports diagnostics with a kebab-case code, a severity and a
 * message, finds no error in its own output with `lint`, and names a bare,
 * stable file.
 */
export function testDocumentFormat<F extends AnyDocumentFormat>(
  format: F,
  options: TestDocumentFormatOptions<VersionOf<F>> = {},
): Promise<ConformanceReport> {
  const subject: DocumentFormat = format;
  const id: unknown = subject.id;
  const defaultVersion: unknown = subject.defaultVersion;

  const versions: readonly string[] =
    options.versions ?? Object.keys(subject.versions);

  let model: ApiModel | undefined;
  const modelOf = (): ApiModel => (model ??= options.model ?? sampleModel());

  const lower = (
    version: string,
    input: ApiModel,
  ): { readonly document: unknown; readonly diagnostics: SpecDiagnostic[] } => {
    const diagnostics: SpecDiagnostic[] = [];

    const document = subject.lower(input, version, {
      report: (diagnostic) => {
        diagnostics.push(diagnostic);
      },
    });

    return { document, diagnostics };
  };

  return conform(`DocumentFormat "${String(id)}"`, [
    [
      "targets API v1 with an id",
      () => {
        const version: unknown = subject.apiVersion;
        expect(version === 1, `apiVersion is ${String(version)}`);
        expect(
          typeof id === "string" && id.length > 0,
          "id must be a non-empty string",
        );
      },
    ],
    [
      "lists versions with a pin and a known status",
      () => {
        const listed = Object.entries(subject.versions);
        expect(listed.length > 0, "versions lists no version");

        for (const [version, entry] of listed) {
          const status: unknown = entry.status;
          expect(
            typeof entry.pin === "string" && entry.pin.length > 0,
            `version ${version} has no pin`,
          );
          expect(
            typeof status === "string" && STATUSES.has(status),
            `version ${version} has the status ${String(status)}`,
          );
        }

        for (const version of versions) {
          expect(
            Object.hasOwn(subject.versions, version),
            `options.versions names ${version}, which the format does not list`,
          );
        }
      },
    ],
    [
      "defaults to a listed version that is not a preview",
      () => {
        const entry = Object.hasOwn(subject.versions, subject.defaultVersion)
          ? subject.versions[subject.defaultVersion]
          : undefined;

        expect(
          entry !== undefined,
          `the default version ${String(defaultVersion)} is not in versions`,
        );
        expect(
          entry.status !== "preview",
          `the default version ${String(defaultVersion)} is a preview`,
        );
      },
    ],
    [
      "lowers every version without mutating the model",
      () => {
        const original = modelOf();
        const before = JSON.stringify(original);

        for (const version of versions) {
          lower(version, original);
          expect(
            JSON.stringify(original) === before,
            `lower(model, "${version}") changed the model`,
          );
          lower(version, frozenCopy(original));
        }
      },
    ],
    [
      "renders the same document twice",
      () => {
        for (const version of versions) {
          const first = lower(version, structuredClone(modelOf()));
          const second = lower(version, structuredClone(modelOf()));
          expect(
            same(first.document, second.document),
            `lower(model, "${version}") is not deterministic`,
          );
          expect(
            same(first.diagnostics, second.diagnostics),
            `lower(model, "${version}") reports different diagnostics each time`,
          );
        }
      },
    ],
    [
      "renders plain JSON or text",
      () => {
        for (const version of versions) {
          const { document } = lower(version, modelOf());
          expect(
            typeof document === "string" ||
              (typeof document === "object" &&
                document !== null &&
                isPlainJson(document)),
            `lower(model, "${version}") returned something other than a JSON object or a string`,
          );
        }
      },
    ],
    [
      "reports diagnostics with a code, a severity and a message",
      () => {
        for (const version of versions) {
          const { document, diagnostics } = lower(version, modelOf());
          const linted = subject.lint?.(document, version) ?? [];

          for (const diagnostic of [...diagnostics, ...linted]) {
            const problem = diagnosticProblem(diagnostic);
            expect(problem === undefined, `${version}: ${problem ?? ""}`);
          }
        }
      },
    ],
    subject.lint !== undefined && [
      "finds no error in its own output",
      () => {
        for (const version of versions) {
          const { document, diagnostics } = lower(version, modelOf());

          if (
            diagnostics.some((diagnostic) => diagnostic.severity === "error")
          ) {
            continue;
          }

          const errors = (subject.lint?.(document, version) ?? []).filter(
            (diagnostic) => diagnostic.severity === "error",
          );

          expect(
            errors.length === 0,
            `lint(lower(model, "${version}")) reports ${errors
              .map((error) => error.code)
              .join(", ")}`,
          );
        }
      },
    ],
    [
      "names a bare, stable file per version",
      () => {
        for (const version of versions) {
          const name: unknown = subject.fileName(version);
          expect(
            typeof name === "string" && /^[^/\\]+\.[A-Za-z0-9]+$/.test(name),
            `fileName("${version}") is ${JSON.stringify(name)}, not a file name with an extension`,
          );
          expect(
            subject.fileName(version) === name,
            `fileName("${version}") changes between calls`,
          );
        }
      },
    ],
  ]);
}
