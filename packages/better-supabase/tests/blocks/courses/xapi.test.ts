import { describe, expect, it, vi } from "vitest";

import {
  sendXapiStatements,
  XAPI_VERBS,
  XAPI_VERSION,
  xapiCourseCompleted,
  xapiDuration,
  xapiLessonCompleted,
  xapiQuizResult,
  xapiStatement,
} from "../../../src/blocks/courses/xapi.ts";

const actor = { homePage: "https://app.example", name: "u-1" };
const course = { id: "https://app.example/courses/1", name: "Algebra" };

describe("xAPI statements", () => {
  it("writes a lesson completion with its parent course", () => {
    const result = xapiLessonCompleted({
      actor,
      lesson: { id: "https://app.example/lessons/2", name: "Fractions" },
      course,
      durationSeconds: 90.456,
      timestamp: new Date("2026-10-01T10:00:00Z"),
    });

    expect(result.ok).toBe(true);

    const data = result.ok ? result.data : undefined;

    expect(data?.verb["id"]).toBe(XAPI_VERBS.completed);
    expect(data?.result).toEqual({ completion: true, duration: "PT90.46S" });
    expect(data?.timestamp).toBe("2026-10-01T10:00:00.000Z");
    expect(JSON.stringify(data?.actor)).not.toContain("mailto");
  });

  it("picks passed or failed for a quiz and checks the score", () => {
    const quiz = { id: "https://app.example/quizzes/1" };

    const passed = xapiQuizResult({
      actor,
      quiz,
      course,
      scoreScaled: 0.9,
      passed: true,
    });

    const failed = xapiQuizResult({
      actor,
      quiz,
      course,
      scoreScaled: 0.2,
      passed: false,
    });

    const bad = xapiQuizResult({
      actor,
      quiz,
      course,
      scoreScaled: 1.5,
      passed: true,
    });

    expect(passed.ok && passed.data.verb["id"]).toBe(XAPI_VERBS.passed);
    expect(failed.ok && failed.data.verb["id"]).toBe(XAPI_VERBS.failed);
    expect(bad.ok).toBe(false);
  });

  it("refuses ids that are not IRIs or UUIDs", () => {
    const result = xapiStatement({
      id: "nope",
      actor,
      verb: { id: "completed" },
      object: { id: "course-1" },
      registration: "x",
    });

    expect(result.ok).toBe(false);

    const error = result.ok ? undefined : result.error;

    expect(error?.kind === "validation" ? error.issues : []).toHaveLength(4);
  });

  it("writes a course completion", () => {
    expect(xapiCourseCompleted({ actor, course }).ok).toBe(true);
  });

  it("rejects a negative duration", () => {
    expect(() => xapiDuration(-1)).toThrow(RangeError);
  });
});

describe("sendXapiStatements", () => {
  const statement = xapiCourseCompleted({ actor, course });

  it("posts the batch with the version header", async () => {
    if (!statement.ok) {
      throw new Error("statement");
    }

    const fetcher = vi.fn(async () =>
      Response.json([statement.data.id], { status: 200 }),
    );

    const result = await sendXapiStatements(
      {
        endpoint: "https://lrs.example/xapi/",
        headers: async () => ({ authorization: "Basic abc" }),
        fetch: fetcher,
      },
      [statement.data],
    );

    expect(result.ok && result.data).toEqual([statement.data.id]);

    const [url, init] = fetcher.mock.calls[0] as unknown as [
      string,
      RequestInit,
    ];

    expect(url).toBe("https://lrs.example/xapi/statements");
    expect(new Headers(init.headers).get("x-experience-api-version")).toBe(
      XAPI_VERSION,
    );
  });

  it("returns an error for a failed LRS and sends nothing for no statements", async () => {
    if (!statement.ok) {
      throw new Error("statement");
    }

    const fetcher = vi.fn(async () => new Response("no", { status: 403 }));

    const lrs = {
      endpoint: "https://lrs.example/xapi",
      headers: async () => ({}),
      fetch: fetcher as unknown as typeof fetch,
    };

    const failed = await sendXapiStatements(lrs, [statement.data]);

    expect(failed.ok).toBe(false);
    expect((await sendXapiStatements(lrs, [])).ok).toBe(true);
    expect(fetcher).toHaveBeenCalledOnce();
  });
});
