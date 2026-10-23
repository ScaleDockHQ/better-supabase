import { Stack, useLocalSearchParams } from "expo-router";
import { Text, View } from "react-native";

import { CommentThread } from "../../components/comment-thread";
import { TagInput } from "../../components/tag-input";
import { useCustomer } from "../../lib/supabase/hooks";

/**
 * IOS and Android: the customer from the device database, and its tags and
 * comments with the same hooks as the Next.js example.
 */
export default function CustomerScreen() {
  const { id, name } = useLocalSearchParams<{ id: string; name?: string }>();
  const customer = useCustomer(id);

  return (
    <View style={{ flex: 1, gap: 16, padding: 16 }}>
      <Stack.Screen
        options={{ title: customer.data?.name ?? name ?? "Customer" }}
      />
      {customer.data ? <Text>{customer.data.status}</Text> : null}
      <TagInput customerId={id} />
      <CommentThread customerId={id} />
    </View>
  );
}
