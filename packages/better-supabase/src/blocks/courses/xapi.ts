import type { Result } from "../../core/result.ts";

import { dbError } from "../../core/errors.ts";
import { err, ok } from "../../core/result.ts";

/** The `X-Experience-API-Version` the writer sends by default. */
export const XAPI_VERSION = "2.0.0";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** ADL verbs that a course produces. */
export const XAPI_VERBS = {
  attempted: "http://adlnet.gov/expapi/verbs/attempted",
  completed: "http://adlnet.gov/expapi/verbs/completed",
  experienced: "http://adlnet.gov/expapi/verbs/experienced",
  failed: "http://adlnet.gov/expapi/verbs/failed",
  initialized: "http://adlnet.gov/expapi/verbs/initialized",
  passed: "http://adlnet.gov/expapi/verbs/passed",
  progressed: "http://adlnet.gov/expapi/verbs/progressed",
  terminated: "http://adlnet.gov/expapi/verbs/terminated",
} as const;

export type XapiVerbName = keyof typeof XAPI_VERBS;

/** The activity type IRIs from the ADL vocabulary. */
export const XAPI_ACTIVITY_TYPES = {
  course: "http://adlnet.gov/expapi/activities/course",
  lesson: "http://adlnet.gov/expapi/activities/lesson",
  assessment: "http://adlnet.gov/expapi/activities/assessment",
  module: "http://adlnet.gov/expapi/activities/module",
} as const;

/**
 * The learner as an account actor. An account identifies the learner without
 * putting an email address into the LRS.
 */
export interface XapiAccount {
  /** The system the name belongs to, such as the app's origin. */
  readonly homePage: string;
  /** The user's id there. */
  readonly name: string;
  /** Shown in the LRS. */
  readonly displayName?: string;
}

export interface XapiActivity {
  /** An IRI that stays the same for this activity, such as a course URL. */
  readonly id: string;
  readonly type?: string;
  readonly name?: string;
  readonly description?: string;
  /** The language of `name` and `description`. Default `en`. */
  readonly language?: string;
}

export interface XapiResult {
  readonly completion?: boolean;
  readonly success?: boolean;
  /** 0 to 1. */
  readonly scoreScaled?: number;
  readonly scoreRaw?: number;
  readonly scoreMin?: number;
  readonly scoreMax?: number;
  /** Time spent, in seconds. */
  readonly durationSeconds?: number;
}

export interface XapiStatementInput {
  /** Default a random UUID. The LRS refuses a repeated id with other content. */
  readonly id?: string;
  readonly actor: XapiAccount;
  readonly verb: XapiVerbName | { readonly id: string; readonly name?: string };
  readonly object: XapiActivity;
  readonly result?: XapiResult;
  /** Parent activities, such as the course of a lesson. */
  readonly parents?: readonly XapiActivity[];
  /** When it happened. Default now. */
  readonly timestamp?: Date;
  /** Registration of the enrollment, a UUID. */
  readonly registration?: string;
  readonly extensions?: Readonly<Record<string, unknown>>;
}

/** An xAPI statement as the LRS takes it (IEEE 9274.1.1). */
export interface XapiStatement {
  readonly id: string;
  readonly actor: Readonly<Record<string, unknown>>;
  readonly verb: Readonly<Record<string, unknown>>;
  readonly object: Readonly<Record<string, unknown>>;
  readonly result?: Readonly<Record<string, unknown>>;
  readonly context?: Readonly<Record<string, unknown>>;
  readonly timestamp: string;
}

/** An ISO 8601 duration such as `PT90.5S`, as xAPI's `result.duration`. */
export function xapiDuration(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds < 0) {
    throw new RangeError("A duration is a non-negative number of seconds");
  }

  return `PT${Math.round(seconds * 100) / 100}S`;
}

function languageMap(
  language: string,
  value: string | undefined,
): Record<string, string> | undefined {
  return value === undefined ? undefined : { [language]: value };
}

function activityOf(activity: XapiActivity): Record<string, unknown> {
  const language = activity.language ?? "en";
  const name = languageMap(language, activity.name);
  const description = languageMap(language, activity.description);

  return {
    objectType: "Activity",
    id: activity.id,
    ...(name === undefined &&
    description === undefined &&
    activity.type === undefined
      ? {}
      : {
          definition: {
            ...(activity.type === undefined ? {} : { type: activity.type }),
            ...(name === undefined ? {} : { name }),
            ...(description === undefined ? {} : { description }),
          },
        }),
  };
}

function resultOf(result: XapiResult): Record<string, unknown> {
  const score = {
    ...(result.scoreScaled === undefined ? {} : { scaled: result.scoreScaled }),
    ...(result.scoreRaw === undefined ? {} : { raw: result.scoreRaw }),
    ...(result.scoreMin === undefined ? {} : { min: result.scoreMin }),
    ...(result.scoreMax === undefined ? {} : { max: result.scoreMax }),
  };

  return {
    ...(result.completion === undefined
      ? {}
      : { completion: result.completion }),
    ...(result.success === undefined ? {} : { success: result.success }),
    ...(Object.keys(score).length === 0 ? {} : { score }),
    ...(result.durationSeconds === undefined
      ? {}
      : { duration: xapiDuration(result.durationSeconds) }),
  };
}

function isIri(value: string): boolean {
  return /^[a-z][a-z0-9+.-]*:\S+$/i.test(value);
}

/**
 * Builds an xAPI statement and checks what the LRS would refuse: an IRI for the
 * verb and the activity, a UUID for the id and registration, a scaled score
 * between 0 and 1. Returns a `validation` error instead of throwing.
 */
export function xapiStatement(
  input: XapiStatementInput,
): Result<XapiStatement> {
  const verbId =
    typeof input.verb === "string" ? XAPI_VERBS[input.verb] : input.verb.id;

  const verbName =
    typeof input.verb === "string" ? input.verb : input.verb.name;

  const id = input.id ?? crypto.randomUUID();
  const issues: { message: string; path: string[] }[] = [];

  if (!UUID.test(id)) {
    issues.push({ message: "The statement id is not a UUID", path: ["id"] });
  }

  if (!isIri(verbId)) {
    issues.push({ message: "The verb id is not an IRI", path: ["verb", "id"] });
  }

  if (!isIri(input.object.id)) {
    issues.push({
      message: "The activity id is not an IRI",
      path: ["object", "id"],
    });
  }

  if (input.registration !== undefined && !UUID.test(input.registration)) {
    issues.push({
      message: "The registration is not a UUID",
      path: ["registration"],
    });
  }

  const scaled = input.result?.scoreScaled;

  if (scaled !== undefined && (scaled < 0 || scaled > 1)) {
    issues.push({
      message: "A scaled score is between 0 and 1",
      path: ["result", "scoreScaled"],
    });
  }

  if (input.actor.name === "" || !isIri(input.actor.homePage)) {
    issues.push({
      message: "An account needs a home page IRI and a name",
      path: ["actor"],
    });
  }

  if (issues.length > 0) {
    return err(
      dbError("validation", "The xAPI statement is not valid", { issues }),
    );
  }

  const parents = input.parents ?? [];

  const context = {
    ...(input.registration === undefined
      ? {}
      : { registration: input.registration }),
    ...(parents.length === 0
      ? {}
      : { contextActivities: { parent: parents.map(activityOf) } }),
    ...(input.extensions === undefined ? {} : { extensions: input.extensions }),
  };

  const result = input.result === undefined ? {} : resultOf(input.result);

  return ok({
    id,
    actor: {
      objectType: "Agent",
      account: { homePage: input.actor.homePage, name: input.actor.name },
      ...(input.actor.displayName === undefined
        ? {}
        : { name: input.actor.displayName }),
    },
    verb: {
      id: verbId,
      ...(verbName === undefined ? {} : { display: { en: verbName } }),
    },
    object: activityOf(input.object),
    ...(Object.keys(result).length === 0 ? {} : { result }),
    ...(Object.keys(context).length === 0 ? {} : { context }),
    timestamp: (input.timestamp ?? new Date()).toISOString(),
  });
}

/** The statement for a learner who finished a lesson. */
export function xapiLessonCompleted(input: {
  readonly actor: XapiAccount;
  readonly lesson: XapiActivity;
  readonly course: XapiActivity;
  readonly durationSeconds?: number;
  readonly timestamp?: Date;
}): Result<XapiStatement> {
  return xapiStatement({
    actor: input.actor,
    verb: "completed",
    object: { type: XAPI_ACTIVITY_TYPES.lesson, ...input.lesson },
    result: {
      completion: true,
      ...(input.durationSeconds === undefined
        ? {}
        : { durationSeconds: input.durationSeconds }),
    },
    parents: [{ type: XAPI_ACTIVITY_TYPES.course, ...input.course }],
    ...(input.timestamp === undefined ? {} : { timestamp: input.timestamp }),
  });
}

/** The statement for a quiz attempt: `passed` or `failed` with a scaled score. */
export function xapiQuizResult(input: {
  readonly actor: XapiAccount;
  readonly quiz: XapiActivity;
  readonly course: XapiActivity;
  /** 0 to 1. */
  readonly scoreScaled: number;
  readonly passed: boolean;
  readonly timestamp?: Date;
}): Result<XapiStatement> {
  return xapiStatement({
    actor: input.actor,
    verb: input.passed ? "passed" : "failed",
    object: { type: XAPI_ACTIVITY_TYPES.assessment, ...input.quiz },
    result: {
      success: input.passed,
      completion: true,
      scoreScaled: input.scoreScaled,
    },
    parents: [{ type: XAPI_ACTIVITY_TYPES.course, ...input.course }],
    ...(input.timestamp === undefined ? {} : { timestamp: input.timestamp }),
  });
}

/** The statement for a learner who finished a course. */
export function xapiCourseCompleted(input: {
  readonly actor: XapiAccount;
  readonly course: XapiActivity;
  readonly timestamp?: Date;
}): Result<XapiStatement> {
  return xapiStatement({
    actor: input.actor,
    verb: "completed",
    object: { type: XAPI_ACTIVITY_TYPES.course, ...input.course },
    result: { completion: true },
    ...(input.timestamp === undefined ? {} : { timestamp: input.timestamp }),
  });
}

/** An LRS the writer posts to. Bundle no credentials: pass them in. */
export interface XapiLrs {
  /** The LRS endpoint, such as `https://lrs.example.com/xapi`. */
  readonly endpoint: string;
  /** Request headers, usually `authorization`. */
  readonly headers: () => Promise<Readonly<Record<string, string>>>;
  readonly fetch?: typeof fetch;
  /** Default `XAPI_VERSION`. */
  readonly version?: string;
}

/**
 * Posts statements to an LRS in one request. The LRS answers with the ids it
 * stored; a statement that was sent before (same id and content) is accepted
 * again, so a retry is safe. A non-2xx answer is an `unexpected` error that
 * carries the status in `code`.
 */
export async function sendXapiStatements(
  lrs: XapiLrs,
  statements: readonly XapiStatement[],
): Promise<Result<readonly string[]>> {
  if (statements.length === 0) {
    return ok([]);
  }

  const send = lrs.fetch ?? fetch;

  const response = await send(
    `${lrs.endpoint.replace(/\/+$/, "")}/statements`,
    {
      method: "POST",
      headers: {
        ...(await lrs.headers()),
        "content-type": "application/json",
        "x-experience-api-version": lrs.version ?? XAPI_VERSION,
      },
      body: JSON.stringify(statements),
    },
  );

  if (!response.ok) {
    return err(
      dbError("unexpected", `The LRS answered ${response.status}`, {
        code: String(response.status),
      }),
    );
  }

  const body: unknown = await response.json().catch(() => []);

  return ok(
    Array.isArray(body)
      ? body.filter((id): id is string => typeof id === "string")
      : statements.map((statement) => statement.id),
  );
}
