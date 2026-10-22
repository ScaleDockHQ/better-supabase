import { describe, expect, it } from "vitest";

import type { AiFiles } from "../../../src/blocks/ai-files/types.ts";
import type {
  NoteTaker,
  Transcriber,
} from "../../../src/blocks/engagements/index.ts";
import type { Job } from "../../../src/blocks/jobs/types.ts";

import { createEngagements } from "../../../src/blocks/engagements/index.ts";
import {
  recordingOf,
  segmentOf,
} from "../../../src/blocks/engagements/recordings.ts";
import { DbException } from "../../../src/core/errors.ts";
import { AsyncResult } from "../../../src/core/result.ts";

function transport(
  results: Record<string, (args: Record<string, unknown>) => unknown>,
) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    call(_schema: string, fn: string, args: Record<string, unknown>) {
      calls.push([fn, args]);
      const result = results[fn];

      if (!result) {
        return Promise.reject(new Error(`unexpected ${fn}`));
      }

      return Promise.resolve(result(args));
    },
  };
}

const RECORDING = {
  id: "r1",
  organizationId: "o",
  engagementId: "e1",
  fileId: "f1",
  filename: "call.webm",
  mediaType: "audio/webm",
  status: "pending",
  language: "en",
  durationSeconds: null,
  error: null,
  model: null,
  segmentCount: 0,
  createdBy: "u1",
  createdAt: "2026-10-14T09:00:00Z",
  transcribedAt: null,
};

const TRANSCRIBED = {
  ...RECORDING,
  status: "transcribed",
  durationSeconds: 61,
  model: "stt-1",
  segmentCount: 2,
  transcribedAt: "2026-10-14T09:05:00Z",
};

const NOTES = {
  engagementId: "e1",
  organizationId: "o",
  summary: "Proposal by Friday",
  actionItems: [
    { text: "Send proposal", ownerId: "u1", dueAt: "2026-10-16T09:00:00Z" },
    { text: "Book a demo" },
  ],
  model: "notes-1",
  source: "ai",
  createdBy: "u1",
  createdAt: "2026-10-14T09:00:00Z",
  updatedAt: "2026-10-14T09:00:00Z",
};

const ENGAGEMENT = {
  id: "e1",
  tenant_id: "o",
  type: "call",
  title: "Intro call",
  body: null,
  outcome: null,
  owner_user_id: "u1",
  due_at: null,
  done_at: null,
  duration_seconds: null,
  external_ref: null,
  created_by: "u1",
  created_at: "2026-10-14T09:00:00Z",
  updated_at: "2026-10-14T09:00:00Z",
  subjects: [],
  overdue: false,
};

const SEGMENTS = [
  {
    position: 1,
    speaker: "Ann",
    speakerUserId: "u1",
    startMs: 0,
    endMs: 4000,
    text: "Hello",
    confidence: 0.9,
  },
  { position: 2, speaker: null, startMs: 4000, endMs: 9000, text: "Hi" },
];

const files = (fail = false) => {
  const reads: string[] = [];

  const value = {
    files: {
      sign: (file: string) =>
        fail
          ? AsyncResult.err({
              kind: "not_found",
              message: "gone",
              status: 404,
            } as never)
          : AsyncResult.ok(`https://files.test/${file}`),
      read: (file: string) => {
        reads.push(file);

        return AsyncResult.ok({ file: {}, data: new Uint8Array([1, 2]) });
      },
    },
  };

  // SAFETY: the engagements block only calls sign and read.
  return { reads, files: value as unknown as AiFiles };
};

const transcriber = (fail?: Error): Transcriber => ({
  apiVersion: 1,
  model: "stt-1",
  transcribe: async (input, options) => {
    if (fail) {
      throw fail;
    }

    const data = await input.read();

    return {
      language: input.language ?? "en",
      durationSeconds: data.length,
      segments: [
        {
          speaker: "Ann",
          startMs: 0,
          endMs: 4000,
          text: `${input.url} ${options?.signal ? "signal" : "none"}`,
          confidence: 0.9,
        },
        { startMs: 4000, endMs: 9000, text: "Hi" },
      ],
    };
  },
});

const job = (attempts: number): Job<{ readonly recordingId: string }> =>
  // SAFETY: the transcribe job only reads attempts and maxAttempts.
  ({ attempts, maxAttempts: 3 }) as unknown as Job<{
    readonly recordingId: string;
  }>;

describe("engagement recordings", () => {
  it("attaches a file and lists recordings", async () => {
    const t = transport({
      attach_engagement_recording: () => RECORDING,
      engagement_recordings: () => [RECORDING, TRANSCRIBED],
    });

    const engagements = createEngagements({ transport: t });

    const recording = await engagements
      .attachRecording("e1", "f1", { language: "en" })
      .orThrow();

    await engagements.attachRecording("e1", "f2").orThrow();
    const all = await engagements.recordings("e1").orThrow();

    expect(t.calls[0]).toEqual([
      "attach_engagement_recording",
      { engagement: "e1", file: "f1", language: "en" },
    ]);
    expect(t.calls[1]?.[1]).toMatchObject({ language: null });
    expect(recording).toMatchObject({
      id: "r1",
      status: "pending",
      segmentCount: 0,
    });
    expect(recording.durationSeconds).toBeUndefined();
    expect(all[1]?.transcribedAt?.toString()).toBe("2026-10-14T09:05:00Z");
    expect(all[1]?.durationSeconds).toBe(61);
  });

  it("pages a transcript and saves one", async () => {
    const t = transport({
      engagement_transcript: () => SEGMENTS,
      save_engagement_transcript: () => TRANSCRIBED,
    });

    const engagements = createEngagements({ transport: t });

    const segments = await engagements
      .transcript("r1", { after: 0, limit: 10 })
      .orThrow();

    await engagements.transcript("r1").orThrow();
    await engagements
      .saveTranscript("r1", {
        segments: [
          { speaker: "Ann", startMs: 0, endMs: 1, text: "Hi" },
          { startMs: 1, endMs: 2, text: "Yo", confidence: 0.5 },
        ],
      })
      .orThrow();

    expect(segments[0]).toMatchObject({ speaker: "Ann", confidence: 0.9 });
    expect(segments[1]?.speaker).toBeUndefined();
    expect(t.calls[0]?.[1]).toEqual({
      recording: "r1",
      after: 0,
      page_size: 10,
    });
    expect(t.calls[1]?.[1]).toEqual({
      recording: "r1",
      after: null,
      page_size: null,
    });
    expect(t.calls[2]?.[1]).toEqual({
      recording: "r1",
      segments: [
        { speaker: "Ann", startMs: 0, endMs: 1, text: "Hi" },
        { startMs: 1, endMs: 2, text: "Yo", confidence: 0.5 },
      ],
      attrs: { language: null, durationSeconds: null, model: null },
    });
  });

  it("transcribes through the files block on the service transport", async () => {
    const t = transport({});

    const service = transport({
      get_engagement_recording: () => RECORDING,
      save_engagement_transcript: () => TRANSCRIBED,
    });

    const store = files();

    const engagements = createEngagements({
      transport: t,
      service,
      files: store.files,
      transcriber: transcriber(),
    });

    const recording = await engagements
      .transcribe("r1", { signal: new AbortController().signal })
      .orThrow();

    await engagements.transcribe("r1").orThrow();

    expect(recording.status).toBe("transcribed");
    expect(store.reads).toEqual(["f1", "f1"]);
    expect(t.calls).toEqual([]);
    expect(service.calls[1]).toEqual([
      "save_engagement_transcript",
      {
        recording: "r1",
        segments: [
          {
            speaker: "Ann",
            startMs: 0,
            endMs: 4000,
            text: "https://files.test/f1 signal",
            confidence: 0.9,
          },
          { startMs: 4000, endMs: 9000, text: "Hi" },
        ],
        attrs: { language: "en", durationSeconds: 2, model: "stt-1" },
      },
    ]);
    expect(service.calls[3]?.[1]).toMatchObject({
      segments: [{ text: "https://files.test/f1 none" }, { text: "Hi" }],
    });
  });

  it("passes no language when the recording has none", async () => {
    const service = transport({
      get_engagement_recording: () => ({ ...RECORDING, language: null }),
      save_engagement_transcript: () => TRANSCRIBED,
    });

    const seen: (string | undefined)[] = [];

    const engagements = createEngagements({
      transport: service,
      files: files().files,
      transcriber: {
        model: "stt",
        transcribe: async (input) => {
          seen.push(input.language);

          return { segments: [] };
        },
      },
    });

    await engagements.transcribe("r1").orThrow();

    expect(seen).toEqual([undefined]);
  });

  it("refuses to transcribe without a transcriber, files or recording", async () => {
    const service = transport({ get_engagement_recording: () => null });

    const none = await createEngagements({ transport: service }).transcribe(
      "r1",
    );

    const noFiles = await createEngagements({
      transport: service,
      transcriber: transcriber(),
    }).transcribe("r1");

    const gone = await createEngagements({
      transport: service,
      files: files().files,
      transcriber: transcriber(),
    }).transcribe("r1");

    const unsigned = await createEngagements({
      transport: transport({ get_engagement_recording: () => RECORDING }),
      files: files(true).files,
      transcriber: transcriber(),
    }).transcribe("r1");

    expect(none.ok || none.error.hint).toBe("ENGAGEMENT_NO_TRANSCRIBER");
    expect(noFiles.ok || noFiles.error.hint).toBe("ENGAGEMENT_NO_FILES");
    expect(gone.ok || gone.error.hint).toBe("ENGAGEMENT_RECORDING_NOT_FOUND");
    expect(unsigned.ok || unsigned.error.kind).toBe("not_found");
  });

  it("turns a transcriber error into a result", async () => {
    const result = await createEngagements({
      transport: transport({ get_engagement_recording: () => RECORDING }),
      files: files().files,
      transcriber: transcriber(new Error("quota")),
    }).transcribe("r1");

    expect(result.ok).toBe(false);
    expect(result.ok || [result.error.kind, result.error.message]).toEqual([
      "unexpected",
      "quota",
    ]);
  });

  it("runs as a job and marks the recording failed on the last attempt", async () => {
    const service = transport({
      get_engagement_recording: () => RECORDING,
      save_engagement_transcript: () => TRANSCRIBED,
      fail_engagement_recording: () => true,
    });

    const working = createEngagements({
      transport: service,
      files: files().files,
      transcriber: transcriber(),
    }).transcribeJob();

    const failing = createEngagements({
      transport: service,
      files: files().files,
      transcriber: transcriber(new Error("down")),
    }).transcribeJob();

    const signal = new AbortController().signal;

    await working({ recordingId: "r1" }, job(1), signal);
    await expect(
      failing({ recordingId: "r1" }, job(1), signal),
    ).rejects.toBeInstanceOf(DbException);
    expect(service.calls.map(([fn]) => fn)).not.toContain(
      "fail_engagement_recording",
    );
    await expect(
      failing({ recordingId: "r1" }, job(3), signal),
    ).rejects.toBeInstanceOf(DbException);

    expect(service.calls.at(-1)).toEqual([
      "fail_engagement_recording",
      { recording: "r1", error: "down" },
    ]);
  });

  it("drains pending recordings and fails the ones that error", async () => {
    const service = transport({
      pending_engagement_recordings: () => ["r1", "r2"],
      get_engagement_recording: (args) =>
        args["recording"] === "r1" ? RECORDING : null,
      save_engagement_transcript: () => TRANSCRIBED,
      fail_engagement_recording: () => false,
    });

    const engagements = createEngagements({
      transport: service,
      files: files().files,
      transcriber: transcriber(),
    });

    const done = await engagements.drainRecordings({ batch: 5 }).orThrow();

    const aborted = await engagements
      .drainRecordings({ signal: AbortSignal.abort() })
      .orThrow();

    const signalled = await engagements
      .drainRecordings({ signal: new AbortController().signal })
      .orThrow();

    expect(done).toBe(1);
    expect(aborted).toBe(0);
    expect(signalled).toBe(1);
    expect(service.calls[0]).toEqual([
      "pending_engagement_recordings",
      { batch: 5 },
    ]);
    expect(service.calls).toContainEqual([
      "fail_engagement_recording",
      { recording: "r2", error: "no such recording" },
    ]);
  });

  it("reads nothing pending as an empty drain", async () => {
    const done = await createEngagements({
      transport: transport({ pending_engagement_recordings: () => null }),
    })
      .drainRecordings()
      .orThrow();

    expect(done).toBe(0);
  });
});

describe("recording rows", () => {
  it("reads missing counts and offsets as zero", () => {
    const { segmentCount: _count, ...rest } = RECORDING;

    expect(recordingOf(rest).segmentCount).toBe(0);
    expect(segmentOf({ text: "Hi" })).toEqual({
      position: 0,
      startMs: 0,
      endMs: 0,
      text: "Hi",
    });
  });
});

describe("engagement notes", () => {
  it("reads and saves a member's notes", async () => {
    const t = transport({
      engagement_notes: (args) => (args["engagement"] === "e1" ? NOTES : null),
      save_engagement_notes: () => ({
        ...NOTES,
        source: "member",
        model: null,
        actionItems: [],
      }),
    });

    const engagements = createEngagements({ transport: t });
    const due = Temporal.Instant.from("2026-10-16T09:00:00Z");

    const notes = (await engagements.notes("e1").orThrow())!;
    const none = await engagements.notes("e2").orThrow();

    const saved = await engagements
      .saveNotes("e1", {
        summary: "Short",
        actionItems: [{ text: "Call back", ownerId: "u1", dueAt: due }],
      })
      .orThrow();

    await engagements.saveNotes("e1", { summary: "Only" }).orThrow();

    expect(notes.actionItems[0]?.dueAt?.equals(due)).toBe(true);
    expect(notes.actionItems[1]).toEqual({ text: "Book a demo" });
    expect(notes.source).toBe("ai");
    expect(none).toBeUndefined();
    expect(saved).toMatchObject({ source: "member", actionItems: [] });
    expect(saved.model).toBeUndefined();
    expect(t.calls[2]?.[1]).toEqual({
      engagement: "e1",
      notes: {
        summary: "Short",
        actionItems: [
          { text: "Call back", ownerId: "u1", dueAt: "2026-10-16T09:00:00Z" },
        ],
        source: "member",
      },
    });
    expect(t.calls[3]?.[1]).toEqual({
      engagement: "e1",
      notes: { summary: "Only", actionItems: [], source: "member" },
    });
  });

  it("summarizes the transcripts with the note taker", async () => {
    const t = transport({
      engagement_with_transcripts: () => ({
        engagement: ENGAGEMENT,
        segments: SEGMENTS.map((segment) => ({
          ...segment,
          recordingId: "r1",
        })),
      }),
      save_engagement_notes: () => NOTES,
    });

    const inputs: unknown[] = [];

    const noteTaker: NoteTaker = {
      apiVersion: 1,
      model: "notes-1",
      summarize: async (input, options) => {
        inputs.push([input, options?.signal !== undefined]);

        return { summary: "Proposal by Friday" };
      },
    };

    const engagements = createEngagements({ transport: t, noteTaker });

    const notes = await engagements
      .summarize("e1", { signal: new AbortController().signal })
      .orThrow();

    await engagements.summarize("e1").orThrow();

    expect(notes.summary).toBe("Proposal by Friday");
    expect(inputs[0]).toMatchObject([
      {
        engagement: { id: "e1", title: "Intro call" },
        transcript: [
          { recordingId: "r1", position: 1, speaker: "Ann" },
          { recordingId: "r1", position: 2, text: "Hi" },
        ],
      },
      true,
    ]);
    expect(inputs[1]).toMatchObject([{}, false]);
    expect(t.calls[1]).toEqual([
      "save_engagement_notes",
      {
        engagement: "e1",
        notes: {
          summary: "Proposal by Friday",
          actionItems: [],
          source: "ai",
          model: "notes-1",
        },
      },
    ]);
  });

  it("refuses to summarize without a note taker or engagement", async () => {
    const t = transport({ engagement_with_transcripts: () => null });

    const none = await createEngagements({ transport: t }).summarize("e1");

    const gone = await createEngagements({
      transport: t,
      noteTaker: { model: "m", summarize: async () => ({ summary: "x" }) },
    }).summarize("e1");

    const broken = await createEngagements({
      transport: transport({
        engagement_with_transcripts: () => ({
          engagement: ENGAGEMENT,
          segments: [],
        }),
      }),
      noteTaker: {
        model: "m",
        summarize: () => Promise.reject(new Error("model down")),
      },
    }).summarize("e1");

    expect(none.ok || none.error.hint).toBe("ENGAGEMENT_NO_NOTE_TAKER");
    expect(gone.ok || gone.error.hint).toBe("ENGAGEMENT_NOT_FOUND");
    expect(broken.ok || broken.error.hint).toBe("ENGAGEMENT_SUMMARIZE_FAILED");
  });

  it("refuses a transcriber or note taker on another API version", () => {
    expect(() =>
      createEngagements({
        transport: transport({}),
        // SAFETY: an API version this release does not know.
        transcriber: { apiVersion: 2 } as unknown as Transcriber,
      }),
    ).toThrow(/API 2/);
  });
});
