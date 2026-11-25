export function Comment({ author, body }: { author: string; body: string }) {
  return (
    <div>
      <strong>{author}</strong>
      <div dangerouslySetInnerHTML={{ __html: body }} />
    </div>
  );
}
