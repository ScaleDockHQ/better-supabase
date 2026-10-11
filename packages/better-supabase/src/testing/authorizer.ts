import type { RequestContext } from "../core/plugin.ts";

import {
  type AuthorizationOutcome,
  type AuthorizationRequest,
  type Authorizer,
  checkPermission,
  defineAuthorizer,
  requestOf,
} from "../core/authorizer.ts";
import {
  type ConformanceReport,
  conform,
  expect,
  frozenCopy,
  same,
} from "./conformance.ts";
import { hasName } from "./kits/executor.ts";

export interface TestAuthorizerOptions<Ref> {
  /** Permission references to check; give at least one. */
  readonly permissions: readonly Ref[];
  /** A permission the authorizer grants for `context`, checked end to end. */
  readonly granted?: {
    readonly permission: Ref;
    readonly context: RequestContext;
  };
  /** A permission reference the authorizer doesn't know; it must never be granted. */
  readonly unknown?: Ref;
}

const OUTCOMES = new Set(["granted", "denied", "approval-required"]);

const isOutcome = (value: unknown): value is AuthorizationOutcome =>
  typeof value === "object" &&
  value !== null &&
  "outcome" in value &&
  typeof value.outcome === "string" &&
  OUTCOMES.has(value.outcome);

/** Input that claims a privileged caller; the subject must decide, never this. */
const FORGED = {
  subject: { type: "service", id: "service" },
  actor: { id: "service", kind: "service", role: "service_role" },
  role: "service_role",
  user_id: "00000000-0000-4000-8000-000000000000",
  memberships: [{ tenant: "conformance", role: "owner" }],
  claims: {
    role: "service_role",
    user_role: "admin",
    roles: ["admin"],
    memberships: [{ tenant: "conformance", role: "owner" }],
  },
};

/**
 * Proves an `Authorizer` targets API v1, keys every permission to the same
 * string each time (and after a JSON round trip, so references are plain
 * JSON), answers every request with a known outcome without mutating it,
 * keeps the request order in `evaluations`, decides from the subject rather
 * than the input (forged roles, claims and memberships in the resource
 * properties or the context never turn a denial into a grant), never grants an unknown permission, and grants
 * `options.granted` through `checkPermission`.
 */
export function testAuthorizer<Ref>(
  authorizer: Authorizer<Ref>,
  options: TestAuthorizerOptions<Ref>,
): Promise<ConformanceReport> {
  const { subject, context } = requestOf(undefined);
  const requestFor = (
    action: Ref,
    id: string,
    properties?: Readonly<Record<string, unknown>>,
  ): AuthorizationRequest<Ref> => ({
    subject,
    action,
    resource: {
      type: "conformance",
      id,
      ...(properties ? { properties } : {}),
    },
    context,
  });
  const requests = options.permissions.flatMap((permission) =>
    ["a", "b", "c"].map((id) => requestFor(permission, id)),
  );
  return conform(`Authorizer "${authorizer.name}"`, [
    hasName(authorizer),
    [
      "targets API v1",
      () => {
        const version: unknown = authorizer.apiVersion;
        expect(version === 1, `apiVersion is ${String(version)}`);
        expect(
          options.permissions.length > 0,
          "options.permissions lists no permission to check",
        );
      },
    ],
    [
      "keys every permission stably, as plain JSON",
      () => {
        for (const permission of options.permissions) {
          const key = authorizer.key(permission);
          expect(
            typeof key === "string" && key.length > 0,
            "key() must return a non-empty string",
          );
          expect(
            authorizer.key(permission) === key,
            `key() gave two keys for ${key}`,
          );
          // SAFETY: the round trip of a plain JSON reference is the same reference.
          const copy = JSON.parse(JSON.stringify(permission)) as Ref;
          expect(
            same(copy, permission) && authorizer.key(copy) === key,
            `the reference for ${key} is not plain JSON`,
          );
        }
      },
    ],
    [
      "answers every request with a known outcome, without mutating it",
      async () => {
        for (const request of requests) {
          const outcome = await authorizer.evaluate(frozenCopy(request));
          expect(
            isOutcome(outcome),
            `evaluate() gave no known outcome for ${authorizer.key(request.action)}`,
          );
        }
      },
    ],
    authorizer.evaluations !== undefined && [
      "keeps the request order in evaluations",
      async () => {
        const evaluations = authorizer.evaluations!.bind(authorizer);
        const single = await Promise.all(
          requests.map((request) =>
            Promise.resolve(authorizer.evaluate(request)),
          ),
        );
        const batch = await evaluations(frozenCopy(requests));
        expect(
          batch.length === requests.length,
          `evaluations() gave ${batch.length} outcomes for ${requests.length} requests`,
        );
        expect(
          same(
            batch.map((outcome) => outcome.outcome),
            single.map((outcome) => outcome.outcome),
          ),
          "evaluations() disagrees with evaluate() for the same requests",
        );
        const reversed = await evaluations(frozenCopy(requests.toReversed()));
        expect(
          same(
            reversed.toReversed().map((outcome) => outcome.outcome),
            batch.map((outcome) => outcome.outcome),
          ),
          "evaluations() does not keep the request order",
        );
      },
    ],
    [
      "decides from the subject, never from the input",
      async () => {
        for (const permission of options.permissions) {
          const plain = await authorizer.evaluate(requestFor(permission, "a"));
          const forgedResource = await authorizer.evaluate(
            requestFor(permission, "a", FORGED),
          );
          const forgedContext = await authorizer.evaluate({
            ...requestFor(permission, "a"),
            context: { ...context, ...FORGED },
          });
          for (const forged of [forgedResource, forgedContext]) {
            expect(
              forged.outcome !== "granted" || plain.outcome === "granted",
              `input claiming a service caller was granted ${authorizer.key(permission)}`,
            );
          }
        }
      },
    ],
    options.unknown !== undefined && [
      "never grants an unknown permission",
      async () => {
        const checked = await checkPermission({
          authorizer,
          permission: options.unknown!,
          resource: { type: "conformance" },
          context: options.granted?.context,
        });
        expect(!checked.ok, "an unknown permission was granted");
      },
    ],
    options.granted !== undefined && [
      "grants the granted permission through checkPermission",
      async () => {
        const checked = await checkPermission({
          authorizer,
          permission: options.granted!.permission,
          resource: { type: "conformance" },
          context: options.granted!.context,
        });
        expect(
          checked.ok,
          checked.ok
            ? ""
            : `the permission was refused: ${checked.error.message}`,
        );
      },
    ],
  ]);
}

export interface StaticAuthorizerOptions<Ref extends string> {
  /**
   * Permissions per role. The role is the subject's `role` property (the
   * Postgres role: `authenticated`, `service_role`), or its type (`anon`).
   */
  readonly roles?: Readonly<Record<string, readonly Ref[]>>;
  /** Permissions per subject id, on top of the role's. */
  readonly grants?: Readonly<Record<string, readonly Ref[]>>;
  /** Permissions that answer `approval-required` with the approval id `approval:<permission>`. */
  readonly approvals?: readonly Ref[];
}

/**
 * An in-memory `Authorizer` for tests and examples: permissions come from
 * the subject's `role` and id only, never from the request's resource or
 * context, and it ignores `subject.properties.claims`.
 */
export function staticAuthorizer<Ref extends string>(
  options: StaticAuthorizerOptions<Ref>,
): Authorizer<Ref> {
  const approvals = new Set<string>(options.approvals ?? []);
  const evaluate = (
    request: AuthorizationRequest<Ref>,
  ): AuthorizationOutcome => {
    const { subject, action } = request;
    if (approvals.has(action))
      return {
        outcome: "approval-required",
        approval: { id: `approval:${action}` },
      };
    const role = subject.properties?.["role"];
    const granted = [
      ...(options.roles?.[typeof role === "string" ? role : subject.type] ??
        []),
      ...(options.grants?.[subject.id] ?? []),
    ];
    return granted.includes(action)
      ? { outcome: "granted" }
      : { outcome: "denied", reason: `Permission ${action} is required` };
  };
  return defineAuthorizer<Ref>({
    name: "static",
    key: (ref) => ref,
    evaluate,
    evaluations: (requests) => Promise.resolve(requests.map(evaluate)),
  });
}
