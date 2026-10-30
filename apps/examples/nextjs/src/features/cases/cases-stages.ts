/** The open stages every case kind's pipeline starts with, in board order. */
export const OPEN_STAGES = [
  "reported",
  "investigating",
  "acting",
  "verifying",
] as const;

export type OpenStage = (typeof OPEN_STAGES)[number];

const OPEN = new Set<string>(OPEN_STAGES);

export const isOpenStage = (key: string): key is OpenStage => OPEN.has(key);
