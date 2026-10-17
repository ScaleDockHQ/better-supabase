// #region recipe:comment-thread
import { useComments } from "better-supabase/blocks/comments/react";
import { tenantOf, useAuth } from "better-supabase/react";
import { useState } from "react";
import {
  ActivityIndicator,
  Button,
  FlatList,
  Text,
  TextInput,
  View,
} from "react-native";

import { API_SCHEMA } from "../lib/blocks";

/** A customer's comments, oldest first, with a box to add one. */
export function CommentThread({ customerId }: { readonly customerId: string }) {
  const organizationId = tenantOf(useAuth());
  const [body, setBody] = useState("");
  const [pending, setPending] = useState(false);

  const { comments, error, add } = useComments({
    organizationId,
    subjectType: "customer",
    subjectId: customerId,
    schema: API_SCHEMA,
  });

  const submit = async () => {
    const text = body.trim();

    if (!text) {
      return;
    }

    setPending(true);

    if ((await add(text)).ok) {
      setBody("");
    }

    setPending(false);
  };

  if (comments === undefined) {
    return <ActivityIndicator />;
  }

  return (
    <View style={{ flex: 1, gap: 12 }}>
      <FlatList
        data={comments.filter((comment) => !comment.deletedAt)}
        keyExtractor={(comment) => comment.id}
        ListEmptyComponent={<Text>No comments yet.</Text>}
        renderItem={({ item }) => (
          <View style={{ paddingVertical: 8 }}>
            <Text style={{ color: "#737373", fontSize: 12 }}>
              {item.createdAt.toLocaleString()}
            </Text>
            <Text>{item.body}</Text>
          </View>
        )}
      />
      {error ? <Text style={{ color: "#b91c1c" }}>{error.message}</Text> : null}
      <TextInput
        value={body}
        onChangeText={setBody}
        placeholder="Write a comment"
        multiline
        maxLength={4000}
        style={{ borderWidth: 1, borderRadius: 8, padding: 8, minHeight: 64 }}
      />
      <Button
        title="Comment"
        disabled={pending || !body.trim()}
        onPress={() => void submit()}
      />
    </View>
  );
}
// #endregion recipe:comment-thread
