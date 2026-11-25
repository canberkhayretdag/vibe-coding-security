import { cookies } from "next/headers";
import { db } from "./db";

export async function getSession() {
  const id = cookies().get("session")?.value;
  if (!id) return null;
  return db.session.findUnique({ where: { id }, include: { user: true } });
}
