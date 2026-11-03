import { MockTranscriptionModelV4 } from "ai/test";
import { describe, expect, it } from "vitest";

import { aiTranscriber } from "../../src/ai-sdk/transcriber.ts";

const input = {
  file: { id: "f1", filename: "a.mp3", mediaType: "audio/mpeg" },
  url: "https://x.test/a.mp3",
  read: async () => new Uint8Array([1, 2, 3]),
  language: "nl",
};

function model(
  segments: { text: string; startSecond: number; endSecond: number }[],
) {
  return new MockTranscriptionModelV4({
    modelId: "stt-1",
    doGenerate: async () => ({
      text: "hello world",
      segments,
      language: "en",
      durationInSeconds: 3,
      warnings: [],
      response: { timestamp: new Date(0), modelId: "stt-1", headers: {} },
    }),
  });
}

describe("aiTranscriber", () => {
  it("maps segments to milliseconds", async () => {
    const transcriber = aiTranscriber({
      model: model([
        { text: "hello", startSecond: 0, endSecond: 1.5 },
      ]) as never,
    });

    expect(transcriber.model).toBe("stt-1");
    expect(await transcriber.transcribe(input)).toEqual({
      segments: [{ startMs: 0, endMs: 1500, text: "hello" }],
      language: "en",
      durationSeconds: 3,
    });
  });

  it("falls back to one turn without segments", async () => {
    const result = await aiTranscriber({
      model: model([]) as never,
    }).transcribe(input);

    expect(result.segments).toEqual([
      { startMs: 0, endMs: 3000, text: "hello world" },
    ]);
  });
});
