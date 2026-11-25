import Stripe from "stripe";
import { getSession } from "@/lib/session";

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!);

export async function POST(req: Request) {
  const session = await getSession();
  if (!session) return new Response("Unauthorized", { status: 401 });

  const { productName, price, quantity } = await req.json();

  const checkout = await stripe.checkout.sessions.create({
    mode: "payment",
    line_items: [
      {
        price_data: { currency: "usd", product_data: { name: productName }, unit_amount: price },
        quantity,
      },
    ],
    success_url: `${process.env.APP_URL}/checkout/success?order=${session.user.id}`,
    cancel_url: `${process.env.APP_URL}/cart`,
  });

  return Response.json({ url: checkout.url });
}
