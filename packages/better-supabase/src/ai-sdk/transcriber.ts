import { transcribe } from "ai";

import type {
  Transcriber,
  TranscriberInput,
} from "../blocks/activities/index.ts";

type TranscriptionModel = Parameters<typeof transcribe>[0]["model"];

export interface AiTranscriberOptions {
  readonly model: TranscriptionModel;
  /** The name stored with the transcript. Defaults to the model's id. */
  readonly name?: string;
  readonly providerOptions?: Parameters<
    typeof transcribe
  >[0]["providerOptions"];
}

const MS = 1000;

/**
 * A `Transcriber` for the activities block over the AI SDK's `transcribe`.
 * Segments become speaker turns without a speaker label; a provider that
 * returns no segments gives one turn that covers the whole recording.
 */
export function aiTranscriber(options: AiTranscriberOptions): Transcriber {
  const { model } = options;

  const name =
    options.name ?? (typeof model === "string" ? model : model.modelId);

  return {
    apiVersion: 1,
    model: name,
    transcribe: async (input: TranscriberInput, call) => {
      const audio = await input.read();

      const result = await transcribe({
        model,
        audio,
        ...(options.providerOptions === undefined
          ? {}
          : { providerOptions: options.providerOptions }),
        ...(call?.signal === undefined ? {} : { abortSignal: call.signal }),
      });

      const duration = result.durationInSeconds;

      const segments =
        result.segments.length > 0
          ? result.segments.map((segment) => ({
              startMs: Math.round(segment.startSecond * MS),
              endMs: Math.round(segment.endSecond * MS),
              text: segment.text,
            }))
          : [
              {
                startMs: 0,
                endMs: Math.round((duration ?? 0) * MS),
                text: result.text,
              },
            ];

      const language = result.language ?? input.language;

      return {
        segments,
        ...(language === undefined ? {} : { language }),
        ...(duration === undefined ? {} : { durationSeconds: duration }),
      };
    },
  };
}
