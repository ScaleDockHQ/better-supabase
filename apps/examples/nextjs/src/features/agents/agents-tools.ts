/**
 * The tools the assistant ships with, so the access matrix lists them before
 * any call.
 */
export const BUILT_IN_TOOLS = ["searchKnowledge", "memory", "runCode"] as const;

/** What a tool does when the model calls it. */
export const TOOL_POLICIES = ["auto", "ask", "deny"] as const;

export type ToolPolicyChoice = (typeof TOOL_POLICIES)[number];

/**
 * Starting points for an agent: the instructions, the tools it may call and the
 * prompts the chat offers before the first message.
 */
export const PLAYBOOKS = [
  {
    id: "support-triage",
    name: "Support triage",
    instructions:
      "You triage incoming support requests. Search the knowledge base first, answer when the article settles it, and otherwise summarize the request for a human with the customer, the product area and the urgency.",
    tools: ["searchKnowledge"],
    starters: ["Triage the latest request", "Which articles cover refunds?"],
  },
  {
    id: "research",
    name: "Research assistant",
    instructions:
      "You research a question across the knowledge base and your memory. Cite the document behind every claim and say what you could not find.",
    tools: ["searchKnowledge", "memory"],
    starters: ["Summarize what we know about our biggest customer"],
  },
  {
    id: "sales-follow-up",
    name: "Sales follow-up",
    instructions:
      "You draft follow-ups for open deals. Use the memory for what the customer cares about, keep each draft under 120 words and never send anything yourself.",
    tools: ["memory"],
    starters: ["Draft a follow-up for the stalled deals"],
  },
] as const;

export type Playbook = (typeof PLAYBOOKS)[number];
