import { db } from "@/lib/db";

export default async function Success({ searchParams }: { searchParams: { order: string } }) {
  // Anyone who opens this URL becomes Pro. There is no webhook.
  await db.user.update({ where: { id: searchParams.order }, data: { plan: "pro" } });
  return <h1>Thanks! You are Pro now.</h1>;
}
