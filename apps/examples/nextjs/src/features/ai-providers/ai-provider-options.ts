/** The AI Gateway provider slugs the add form offers. */
export const PROVIDERS = ["anthropic", "openai", "google", "mistral"] as const;

export type Provider = (typeof PROVIDERS)[number];
