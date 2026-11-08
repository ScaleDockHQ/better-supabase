import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { describe, expect, it, vi } from "vitest";

import type {
  JobPort,
  WorkerJob,
  WorkerResult,
} from "../../../src/cli/generators/worker.ts";
import type { GeneratorInput } from "../../../src/config/index.ts";

import { runJob, serve } from "../../../src/cli/generators/worker.ts";
import { notAGenerator, throwsText } from "./fixtures/delayed.ts";

const fixture = pathToFileURL(
  join(import.meta.dirname, "fixtures/delayed.ts"),
).href;

const input = { meta: { tables: {} } } as unknown as GeneratorInput;

const job = (extra: Partial<WorkerJob> = {}): WorkerJob => ({
  id: 3,
  name: "delayed-a",
  version: "1.0.0",
  module: { specifier: fixture, export: "delayed" },
  options: { id: "a" },
  ...extra,
});

describe("the generator worker's job", () => {
  it("builds the generator from its module and returns its files", async () => {
    const result = await runJob(job(), input);

    expect(result).toEqual({
      id: 3,
      ok: true,
      files: [
        {
          path: "out/a.json",
          contents: JSON.stringify({ id: "a", meta: { tables: {} } }),
        },
      ],
    });
  });

  it("returns the message of a generator that throws", async () => {
    const result = await runJob(
      job({ options: { id: "a", fail: "no good" } }),
      input,
    );

    expect(result).toEqual({ id: 3, ok: false, error: "no good" });
  });

  it("names a module that does not export the function", async () => {
    const result = await runJob(
      job({ module: { specifier: fixture, export: "missing" } }),
      input,
    );

    expect(result).toMatchObject({ ok: false });
    expect(JSON.stringify(result)).toContain(
      'does not export a function named \\"missing\\"',
    );
  });

  it("has fixtures that are what their names say", () => {
    expect(Object.keys(notAGenerator())).toEqual([]);
    expect(() => throwsText().generate(input)).toThrow("plain text");
  });

  it("names an export that does not build a generator", async () => {
    const result = await runJob(
      job({ module: { specifier: fixture, export: "notAGenerator" } }),
      input,
    );

    expect(JSON.stringify(result)).toContain("did not return a generator");
  });

  it("refuses a generator built under another name or version", async () => {
    const renamed = await runJob(job({ name: "other" }), input);
    const aged = await runJob(job({ version: "9.9.9" }), input);

    expect(JSON.stringify(renamed)).toContain('not \\"other\\" 1.0.0');
    expect(JSON.stringify(aged)).toContain('not \\"delayed-a\\" 9.9.9');
  });

  it("reports a module that can't be imported", async () => {
    const result = await runJob(
      job({ module: { specifier: "file:///nowhere/x.js", export: "x" } }),
      input,
    );

    expect(result).toMatchObject({ id: 3, ok: false });
  });

  it("reports a thrown value that is not an error as text", async () => {
    const result = await runJob(
      job({ module: { specifier: fixture, export: "throwsText" } }),
      input,
    );

    expect(result).toEqual({ id: 3, ok: false, error: "plain text" });
  });

  it("answers every job posted to its port", async () => {
    const listeners: ((posted: WorkerJob) => void)[] = [];
    const answers: WorkerResult[] = [];

    const port: JobPort = {
      on: (_event, listener) => {
        listeners.push(listener);
      },
      postMessage: (result) => {
        answers.push(result);
      },
    };

    serve(port, input);
    listeners[0]?.(job({ id: 0 }));
    listeners[0]?.(job({ id: 1, options: { id: "b" }, name: "delayed-b" }));

    await vi.waitFor(() => {
      expect(answers).toHaveLength(2);
    });

    expect(
      answers.map((answer) => answer.id).toSorted((a, b) => a - b),
    ).toEqual([0, 1]);
    expect(answers.every((answer) => answer.ok)).toBe(true);
  });
});
