/** Whether `keys` are in ascending order. */
export function isSorted(keys: readonly string[]): boolean {
  return keys.every(
    (key, index) => index === 0 || keys[index - 1]!.localeCompare(key) <= 0,
  );
}
