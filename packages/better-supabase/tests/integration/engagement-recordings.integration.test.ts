import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type {
  NoteTaker,
  Transcriber,
} from "../../src/blocks/activities/index.ts";
import type { AiFiles } from "../../src/blocks/ai-files/types.ts";
import type { Result } from "../../src/core/result.ts";
import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { createActivities } from "../../src/blocks/activities/index.ts";
import { createContacts } from "../../src/blocks/contacts/index.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { AsyncResult } from "../../src/core/result.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const layout: BlockSqlLayout = {
  subjects: withBlockSubjects({}, ["contacts"], {}),
  modules: { activities: { options: { recordings: true } } },
};

const MODULES = [
  "organizations",
  "outbox",
  "subjects",
  "contacts",
  "ai-files",
  "activities",
];

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

// SAFETY: the engagements block only signs and reads files.
const files = {
  files: {
    sign: (file: string) => AsyncResult.ok(`https://files.test/${file}`),
    read: (file: string) =>
      AsyncResult.ok({ file: { id: file }, data: new Uint8Array(3) }),
  },
} as unknown as AiFiles;

const transcriber: Transcriber = {
  apiVersion: 1,
  model: "stt-test",
  transcribe: async (input) => ({
    language: input.language ?? "en",
    durationSeconds: (await input.read()).length,
    segments: [
      { speaker: "Rep", startMs: 0, endMs: 3000, text: "Thanks for joining." },
      {
        speaker: "Buyer",
        startMs: 3000,
        endMs: 8000,
        text: "Send the proposal by Friday.",
        confidence: 0.82,
      },
    ],
  }),
};

const noteTaker: NoteTaker = {
  apiVersion: 1,
  model: "notes-test",
  summarize: async (input) => ({
    summary: `${input.transcript.length} turns: ${input.transcript
      .map((segment) => segment.text)
      .join(" ")}`,
    actionItems: [{ text: "Send the proposal" }],
  }),
};

describe.skipIf(!live)("engagement recordings", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("transcribes recordings and writes notes for teammates to read", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const rep = await s.user("rep");
      const stranger = await s.user("stranger");
      await s.install(MODULES, layout);
      const org = await s.organization(owner, { member: rep });
      await s.organization(stranger);
      const transport = sqlTransport(s.sql);

      const engagements = createActivities({
        transport,
        files,
        transcriber,
        noteTaker,
      });

      await s.asRole(rep);

      const acme = await createContacts({ transport })
        .saveCompany(org, { name: "Acme" })
        .orThrow();

      const call = await engagements
        .log(org, { type: "call", title: "Discovery call" }, [
          { type: "company", id: acme.id },
        ])
        .orThrow();

      await s.service();

      const file = async (userId: string, status = "ready") => {
        const [row] = await s.rows<{ id: string }>(
          `insert into better_supabase.ai_files (organization_id, owner_id, bucket, filename, media_type, byte_size, status)
           values ($1, $2, 'ai-files', 'call.webm', 'audio/webm', 3, $3) returning id`,
          [org, userId, status],
        );

        return row!.id;
      };

      const mine = await file(rep.id);
      const second = await file(rep.id);
      const pending = await file(rep.id, "pending");
      const owners = await file(owner.id);

      await s.asRole(rep);

      const recording = await engagements
        .attachRecording(call.id, mine, { language: "en" })
        .orThrow();

      expect(recording).toMatchObject({
        engagementId: call.id,
        fileId: mine,
        filename: "call.webm",
        mediaType: "audio/webm",
        status: "pending",
        language: "en",
        segmentCount: 0,
      });
      expect(hint(await engagements.attachRecording(call.id, mine))).toBe(
        "ACTIVITY_RECORDING_EXISTS",
      );
      expect(hint(await engagements.attachRecording(call.id, pending))).toBe(
        "AI_FILE_NOT_FOUND",
      );
      expect(hint(await engagements.attachRecording(call.id, owners))).toBe(
        "AI_FILE_NOT_FOUND",
      );

      const invalid = await engagements.saveTranscript(recording.id, {
        segments: [{ startMs: 5, endMs: 1, text: "backwards" }],
      });

      expect(hint(invalid)).toBe("ACTIVITY_TRANSCRIPT_INVALID");

      await s.service();
      const transcribed = await engagements.transcribe(recording.id).orThrow();
      expect(transcribed).toMatchObject({
        status: "transcribed",
        model: "stt-test",
        durationSeconds: 3,
        segmentCount: 2,
      });
      expect(
        await s.value<boolean>(
          "better_supabase.fail_activity_recording($1, 'late')",
          [recording.id],
        ),
      ).toBe(false);

      await s.asRole(owner);

      const transcript = await engagements
        .transcript(recording.id, { limit: 1 })
        .orThrow();

      expect(transcript).toEqual([
        {
          position: 1,
          speaker: "Rep",
          startMs: 0,
          endMs: 3000,
          text: "Thanks for joining.",
        },
      ]);
      expect(
        await engagements.transcript(recording.id, { after: 1 }).orThrow(),
      ).toMatchObject([{ position: 2, confidence: 0.82 }]);

      await s.asRole(rep);
      const notes = await engagements.summarize(call.id).orThrow();
      expect(notes).toMatchObject({
        source: "ai",
        model: "notes-test",
        summary: "2 turns: Thanks for joining. Send the proposal by Friday.",
        actionItems: [{ text: "Send the proposal" }],
      });

      const edited = await engagements
        .saveNotes(call.id, { summary: "Proposal due Friday." })
        .orThrow();

      expect(edited).toMatchObject({ source: "member", actionItems: [] });
      expect(edited.model).toBeUndefined();
      expect(hint(await engagements.saveNotes(call.id, { summary: "" }))).toBe(
        "ACTIVITY_NOTES_INVALID",
      );

      await s.asRole(stranger);
      expect(await engagements.recordings(call.id).orThrow()).toEqual([]);
      expect(await engagements.notes(call.id).orThrow()).toBeUndefined();
      expect(await engagements.transcript(recording.id).orThrow()).toEqual([]);
      expect(hint(await engagements.attachRecording(call.id, mine))).toBe(
        "ACTIVITY_NOT_FOUND",
      );
      expect(hint(await engagements.saveNotes(call.id, { summary: "x" }))).toBe(
        "ACTIVITY_NOT_FOUND",
      );

      await s.asRole(rep);
      await engagements.attachRecording(call.id, second).orThrow();
      await s.service();
      expect(await engagements.drainRecordings().orThrow()).toBe(1);
      expect(await engagements.drainRecordings().orThrow()).toBe(0);
      expect(
        await s.value<string[]>(
          `(select array_agg(type order by type) from better_supabase.outbox_events
           where type like 'engagement.%' and payload ->> 'engagementId' = $1)`,
          [call.id],
        ),
      ).toEqual([
        "engagement.logged",
        "engagement.recorded",
        "engagement.recorded",
        "engagement.summarized",
        "engagement.summarized",
        "engagement.transcribed",
        "engagement.transcribed",
      ]);

      await s.asRole(owner);
      const all = await engagements.recordings(call.id).orThrow();
      expect(all.map((item) => item.status)).toEqual([
        "transcribed",
        "transcribed",
      ]);
      expect((await engagements.notes(call.id).orThrow())?.summary).toBe(
        "Proposal due Friday.",
      );
    } finally {
      await s.close();
    }
  });
});
