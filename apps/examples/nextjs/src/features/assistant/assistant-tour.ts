import { createChat } from "@shadcn/helpers/ai-sdk";

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null;

/**
 * What the user picked in the `askQuestions` tool, as the continuation reads
 * it.
 */
const directionOf = (output: unknown): string => {
  if (!isRecord(output) || !isRecord(output["answers"])) {
    return "the first option";
  }

  const answer = output["answers"]["direction"];

  return typeof answer === "string" ? answer : "the first option";
};

/**
 * A scripted conversation for the tour: reasoning, a tool call with its trace,
 * a cited source, a tool that waits for approval and clarifying questions. No
 * model runs, so the tour works without an AI Gateway key and a test can read
 * every turn with `tour().get()`.
 */
export function assistantTour() {
  return createChat()
    .user("What should we ship first?")
    .assistant(({ writer }) => {
      writer.reasoning("The launch checklist ranks billing above onboarding.");

      writer
        .tool("searchKnowledge", { input: { query: "launch checklist" } })
        .sleep(600)
        .output({ hits: 2 });

      writer.sourceDocument({
        sourceId: "launch-checklist",
        mediaType: "text/markdown",
        title: "Launch checklist",
      });

      writer.text(
        "Ship the billing page first. The checklist puts it ahead of onboarding because every trial needs it to convert.",
      );
    })
    .user("Archive the old drafts.")
    .assistant(({ writer }) => {
      writer.text("This archives 3 drafts. Approve?");

      writer.tool("archiveDrafts", {
        input: { count: 3 },
        needsApproval: true,
        output: { archived: 3 },
      });
    })
    .assistant(({ writer, toolCall }) => {
      writer.text(
        toolCall?.approved
          ? "Archived 3 drafts."
          : "Okay, the drafts stay where they are.",
      );
    })
    .user("Help me plan the rollout.")
    .assistant(({ writer }) => {
      writer.tool("askQuestions", {
        dynamic: true,
        input: {
          questions: [
            {
              name: "direction",
              title: "Where should the rollout start?",
              description: "Pick the audience that sees it first.",
              choices: ["Internal team", "Beta customers", "Everyone"],
            },
          ],
        },
      });
    })
    .assistant(({ writer, toolCall }) => {
      writer.text(
        `Starting with ${directionOf(toolCall?.output)}. I will draft the checklist next.`,
      );
    });
}
