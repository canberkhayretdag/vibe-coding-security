import { db } from "@/lib/db";
import { getSession } from "@/lib/session";

export async function POST(req: Request) {
  const session = await getSession();
  if (!session) return new Response("Unauthorized", { status: 401 });
  const { code } = await req.json();

  const coupon = await db.coupon.findUnique({ where: { code } });
  if (!coupon || coupon.used) return new Response("Invalid", { status: 400 });

  // Check and write are separate. 50 parallel requests all pass the check above.
  await db.user.update({
    where: { id: session.user.id },
    data: { credits: { increment: coupon.credits } },
  });
  await db.coupon.update({ where: { code }, data: { used: true } });

  return Response.json({ ok: true });
}
