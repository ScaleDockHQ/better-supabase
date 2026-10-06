export const TTL = {
  minute: 60,
  hour: 3600,
  day: 86_400,
  week: 604_800,
} as const;
export type TtlPreset = keyof typeof TTL;

export function ttlSeconds(ttl: number | TtlPreset | undefined): number {
  return typeof ttl === "number" ? ttl : TTL[ttl ?? "hour"];
}
