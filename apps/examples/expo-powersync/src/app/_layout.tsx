import { Stack } from "expo-router";

import { useSync } from "../lib/sync";

export default function RootLayout() {
  useSync();
  return <Stack />;
}
