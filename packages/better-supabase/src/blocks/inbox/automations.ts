import type { DefaultAutomation } from "../../core/automation.ts";

/**
 * Opens a task for each conversation the inbox opens, through the tasks block's
 * `tasks.from_conversation` action. Ships when tasks is installed.
 */
export const CONVERSATION_TO_TASK: DefaultAutomation = {
  key: "inbox.conversation_to_task",
  name: "Open a task for each new conversation",
  description:
    "Creates a task from the conversation's subject and preview, assigned to the conversation's assignee and linked created_from the conversation.",
  trigger: "inbox_conversation.opened",
  subjectType: "inbox_conversation",
  actions: [{ kind: "tasks.from_conversation" }],
  requires: ["tasks"],
};

/** The automations the inbox block ships. */
export const INBOX_AUTOMATIONS: readonly DefaultAutomation[] = [
  CONVERSATION_TO_TASK,
];
