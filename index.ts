import { createClient } from 'jsr:@supabase/supabase-js@2';

const STRIPE_WEBHOOK_SECRET = Deno.env.get('STRIPE_WEBHOOK_SECRET');
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

async function verifyStripeSignature(payload: string, sigHeader: string, secret: string): Promise<boolean> {
  const parts = Object.fromEntries(sigHeader.split(',').map((p) => p.split('=')));
  const signedPayload = parts.t + '.' + payload;
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sigBuf = await crypto.subtle.sign('HMAC', key, enc.encode(signedPayload));
  const expected = Array.from(new Uint8Array(sigBuf)).map((b) => b.toString(16).padStart(2, '0')).join('');
  return expected === parts.v1;
}

Deno.serve(async (req: Request) => {
  try {
    const payload = await req.text();
    const sig = req.headers.get('stripe-signature');

    if (STRIPE_WEBHOOK_SECRET) {
      if (!sig) return new Response('Missing signature', { status: 400 });
      const valid = await verifyStripeSignature(payload, sig, STRIPE_WEBHOOK_SECRET);
      if (!valid) return new Response('Invalid signature', { status: 400 });
    }

    const event = JSON.parse(payload);
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    if (event.type === 'checkout.session.completed') {
      const session = event.data.object;
      const orderId = session.client_reference_id || session.metadata?.order_id;
      if (orderId) {
        // Idempotency guard: skip if this order was already marked paid (Stripe can retry webhooks)
        const { data: existing } = await supabase.from('orders').select('id, quantity, listing_id, payment_status').eq('id', orderId).single();
        if (existing && existing.payment_status !== 'paid') {
          await supabase.from('orders').update({
            payment_status: 'paid',
            stripe_payment_intent_id: session.payment_intent || null,
          }).eq('id', orderId);

          // Decrement stock on the listing, and mark it sold out if this cleared the remainder
          const { data: listing } = await supabase.from('produce_listings').select('id, quantity').eq('id', existing.listing_id).single();
          if (listing) {
            const remaining = Number(listing.quantity) - Number(existing.quantity);
            await supabase.from('produce_listings').update({
              quantity: remaining > 0 ? remaining : 0,
              status: remaining > 0 ? 'available' : 'sold_out',
            }).eq('id', existing.listing_id);
          }
        }
      }
    }

    return new Response(JSON.stringify({ received: true }), { headers: { 'Content-Type': 'application/json' } });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 400 });
  }
});
