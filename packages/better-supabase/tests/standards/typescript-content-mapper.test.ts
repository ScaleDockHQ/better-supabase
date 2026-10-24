import { PassThrough } from "node:stream";
import { describe, expect, it } from "vitest";

import type { LoadedProject } from "../../src/mapper/project.ts";

import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import { encodeFrame, frameReader, serve } from "../../src/mapper/rpc.ts";
import { mapperHandlers } from "../../src/mapper/server.ts";

// TypeScript 7.1's content mapper protocol: JSON-RPC 2.0 framed with a
// Content-Length header over stdio, the methods initialize, openProject,
// transform and closeProject, and a protocol version the mapper answers with.
const PROJECT: LoadedProject = {
  text: "export type A = 1;\n",
  file: "/app/src/schema.bsb",
  configIdentity: "identity",
  watchedFiles: ["/app/better-supabase.config.ts"],
  diagnostics: [],
  optionDiagnostics: [],
};

/** Sends each request to a served mapper and collects the framed responses. */
async function session(
  requests: readonly Record<string, unknown>[],
): Promise<Record<string, unknown>[]> {
  const input = new PassThrough();
  const output = new PassThrough();
  const responses: Record<string, unknown>[] = [];

  output.on(
    "data",
    frameReader((message) => {
      // SAFETY: the mapper answers every request with a JSON-RPC object.
      responses.push(message as Record<string, unknown>);
    }),
  );

  serve(
    mapperHandlers({ load: () => Promise.resolve(PROJECT) }),
    input,
    output,
  );

  for (const request of requests) {
    const answered = responses.length + (request["id"] === undefined ? 0 : 1);
    input.write(encodeFrame({ jsonrpc: "2.0", ...request }));

    await expect.poll(() => responses.length).toBe(answered);
  }

  input.end();

  return responses;
}

describe("TypeScript content mapper protocol", () => {
  it("answers SPEC_PINS.typescriptContentMapper when tsc offers no version", async () => {
    const [initialize] = await session([
      {
        id: 1,
        method: "initialize",
        params: { positionEncodings: ["utf-16"] },
      },
    ]);

    expect(initialize).toEqual({
      jsonrpc: "2.0",
      id: 1,
      result: {
        protocolVersion: Number(SPEC_PINS.typescriptContentMapper),
        positionEncoding: "utf-16",
        diagnosticSource: "BS",
      },
    });
  });

  it("runs a session of framed requests", async () => {
    const responses = await session([
      {
        id: 1,
        method: "initialize",
        params: { positionEncodings: ["utf-16"] },
      },
      {
        id: 2,
        method: "openProject",
        params: { configFileName: "/app/tsconfig.json", projectHandle: "h" },
      },
      {
        id: 3,
        method: "transform",
        params: {
          fileName: "/app/src/schema.bsb",
          content: "",
          projectHandle: "h",
        },
      },
      { id: 4, method: "closeProject", params: { projectHandle: "h" } },
      { id: 5, method: "unknownMethod" },
    ]);

    expect(responses.map((response) => response["id"])).toEqual([
      1, 2, 3, 4, 5,
    ]);
    expect(responses[1]).toMatchObject({
      result: {
        configIdentity: "identity",
        watchedFiles: ["/app/better-supabase.config.ts"],
        optionDiagnostics: [],
      },
    });
    expect(responses[2]).toMatchObject({
      result: { extension: ".ts", text: PROJECT.text, diagnostics: [] },
    });
    expect(responses[3]).toMatchObject({ result: null });
    expect(responses[4]).toMatchObject({ error: { code: -32_603 } });
  });
});
