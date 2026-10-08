import type { WorkflowStepInfo } from "better-supabase/blocks/workflow-builder";

/** The steps the canvas offers; `steps.sync()` writes them to the library. */
export const stepLibrary: readonly WorkflowStepInfo[] = [
  {
    name: "notify.member",
    title: "Notify the member",
    description: "Sends the member who started the run a notification.",
    inputSchema: {
      type: "object",
      properties: { title: { type: "string", maxLength: 200 } },
      required: ["title"],
    },
  },
  {
    name: "text.summarize",
    title: "Summarize text",
    description: "Counts the words and sentences of the input's text.",
    outputSchema: {
      type: "object",
      properties: {
        words: { type: "number" },
        sentences: { type: "number" },
      },
    },
  },
  {
    name: "slack.post",
    title: "Post to Slack",
    description: "Posts a message with a Slack bot token from a credential.",
    inputSchema: {
      type: "object",
      properties: {
        credential: { type: "string" },
        channel: { type: "string" },
        text: { type: "string" },
      },
      required: ["credential", "channel", "text"],
    },
    credentialKind: "slack",
  },
];
