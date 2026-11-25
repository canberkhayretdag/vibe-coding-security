import { db } from "@/lib/db";
import { hash } from "@/lib/hash";

export async function POST(req: Request) {
  const body = await req.json();
  // The whole body goes into the database, including "role" if the client sends it.
  const user = await db.user.create({
    data: { ...body, password: await hash(body.password) },
  });
  return Response.json({ id: user.id });
}
