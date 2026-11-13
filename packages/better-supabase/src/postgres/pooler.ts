/** True for a Supabase transaction-pooler URL (port 6543), which has no LISTEN. */
export function usesTransactionPooler(
  connectionString: string | undefined,
): boolean {
  if (connectionString === undefined) {
    return false;
  }

  try {
    return new URL(connectionString).port === "6543";
  } catch {
    return false;
  }
}
