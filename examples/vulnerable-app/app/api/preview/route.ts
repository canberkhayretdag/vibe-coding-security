export async function GET(req: Request) {
  const url = new URL(req.url).searchParams.get("url")!;
  // Fetches any URL, including http://169.254.169.254/ and http://localhost.
  const res = await fetch(url);
  return new Response(await res.text());
}
