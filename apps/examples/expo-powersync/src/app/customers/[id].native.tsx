import { Stack, useLocalSearchParams } from "expo-router";
import { View } from "react-native";

import { CommentThread } from "../../components/comment-thread";

/** iOS and Android: a customer's comments, with the same hook as the Next.js example. */
export default function CustomerScreen() {
  const { id, name } = useLocalSearchParams<{ id: string; name?: string }>();
  return (
    <View style={{ flex: 1, padding: 16 }}>
      <Stack.Screen options={{ title: name ?? "Customer" }} />
      <CommentThread customerId={id} />
    </View>
  );
}
