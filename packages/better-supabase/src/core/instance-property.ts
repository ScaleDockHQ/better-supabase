/** `lead-scoring` as `leadScoring`: the property an instance key gets. */
export function instanceProperty(key: string): string {
  return key.replaceAll(/[-_]([a-z0-9])/g, (_, c: string) => c.toUpperCase());
}
