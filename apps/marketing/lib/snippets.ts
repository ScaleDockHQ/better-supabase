export type Snippet = {
  readonly filename: string;
  readonly language: "ts" | "tsx" | "bash" | "sql";
  readonly code: string;
};
