export type ShareLinkFeedOptions = {
  readonly visibility?: "access" | "public";
  readonly pastDays?: number;
  readonly futureDays?: number;
  readonly limit?: number;
  readonly single?: boolean;
};
