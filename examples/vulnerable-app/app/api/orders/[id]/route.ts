import { db } from "@/lib/db";

export async function GET(_req: Request, { params }: { params: { id: string } }) {
  // No session check, no owner check.
  const order = await db.order.findUnique({ where: { id: Number(params.id) } });
  return Response.json(order);
}
