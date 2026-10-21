import { Stack, useLocalSearchParams } from "expo-router";
import { View } from "react-native";

import { CommentThread } from "../../components/comment-thread";
import { TagInput } from "../../components/tag-input";

/**
 * IOS and Android: a customer's tags and comments, with the same hooks as the
 * Next.js example.
 */
export default function CustomerScreen() {
  const { id, name } = useLocalSearchParams<{ id: string; name?: string }>();

  return (
    <View style={{ flex: 1, gap: 16, padding: 16 }}>
      <Stack.Screen options={{ title: name ?? "Customer" }} />
      <TagInput customerId={id} />
      <CommentThread customerId={id} />
    </View>
  );
}
