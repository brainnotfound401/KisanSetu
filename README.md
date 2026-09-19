# KisanSetu

A direct farmer-to-buyer agricultural marketplace built for SIH 2026, Problem Statement 26033 (Ministry of Consumer Affairs, Food and Public Distribution). Built solo in a 48-hour internal hackathon at Bennett University.

**Live demo:** https://kisan-setu-sih26.netlify.app

---

## The Problem

Produce typically passes through 3-4 middlemen before reaching a consumer. Each takes a margin. None of them grew the crop or took on the weather risk. Farmers keep a small share of what buyers actually pay, and buyers still pay inflated prices, because there is no trusted direct channel.

## What This Is

A working full-stack marketplace, not a mockup. Real Postgres database with row-level security, a real Stripe payment flow, a self-trained machine learning model running in the browser, and real geolocation-based delivery pricing.

Five roles, each with its own dashboard: **Farmer/FPO**, **Consumer**, **Bulk Buyer** (restaurants, hotels, schools, hospitals), **Transporter**, **Admin**.

---

## Core Features

### Marketplace
Farmers list produce with category, grade, quantity and price. Buyers search and filter by crop, category, location, price and grade.

### Real distance-based delivery pricing (consumer)
Not a flat rate. The Haversine formula computes actual distance between real GPS coordinates. 0-7 km is standard rate, 7-10 km adds a transparent per-km surcharge, beyond 10 km the farmer is still shown but clearly marked "Out of reach" rather than silently hidden. Price shown in the browser is never trusted: an Edge Function recomputes it server-side from the real stored coordinates before Stripe is ever called.

### Separate bulk delivery pricing engine
A completely independent formula for B2B buyers:

```
finalDeliveryFee = max(minimumFee, (basePrice + distanceKm x costPerKm) x tripsRequired + farmerHandlingCost x numberOfFarmers)
```

Cost per kilogram genuinely drops as order size grows. Verified against 8 exact test scenarios during development (see commit history / build notes).

### State vs interstate bulk procurement
Bulk buyers pick Within-State (25 kg minimum) or Interstate (75 kg minimum) sourcing. The system validates this against the farmer's and buyer's actual registered states and blocks contradictory selections (for example, choosing "interstate" for a farmer who is actually in the same state).

### Group delivery
Orders heading to the same 5 km radius get batched into a single delivery run, cheaper but slightly delayed. Full state machine: waiting -> group formed -> scheduled -> in transit -> delivered. Grouping distance and route length are computed with a real Haversine SQL function, not string matching.

### Self-delivery incentive
Farmers who deliver personally instead of using platform logistics receive a computed platform-fee discount based on the actual delivery cost saved, credited through a SECURITY DEFINER database function so it cannot be self-granted or faked by a client request.

### FasalIQ - a genuinely trained model
A Random Forest classifier (40 trees), trained offline in Python with scikit-learn on a 2,200-sample, 22-crop dataset (Nitrogen, Phosphorus, Potassium, temperature, humidity, pH, rainfall as features). 99.3% accuracy on a real held-out test set. Exported and re-implemented as a JavaScript inference engine that runs directly in the browser, verified to produce identical predictions to the original Python model on the same test cases.

### Farmer trust system
A computed trust score from real order and review data, an admin-reviewed FSSAI verification workflow (deliberately human-reviewed rather than faking a non-existent government API), and a review system enforced at the database level: a review can only be inserted if the database confirms the reviewer actually completed that specific order.

### Real interactive delivery tracking
Leaflet plus OpenStreetMap tiles plus OSRM for actual road routing. Shows farmer pickup point, buyer delivery point and a genuine driving-distance ETA, with a straight-line fallback if the routing service is briefly unreachable.

### Multi-language support
Fully translated UI, not machine-placeholder text, in English, Hindi, Bengali, Telugu, Marathi and Tamil, plus a matching on-screen virtual keyboard in each script.

### Security
Row level security on every table. Money-affecting fields (trust score inputs, self-delivery discounts, platform fees) are protected by database triggers so they can only be written by trusted server-side functions, never by a direct client update.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Vanilla HTML/CSS/JavaScript, single-file app (`index.html`) |
| Backend | Supabase (Postgres, Auth, Storage, Edge Functions) |
| Payments | Stripe Checkout |
| Maps and routing | Leaflet.js, OpenStreetMap, OSRM, Nominatim |
| AI/ML | Self-trained Random Forest, Python/scikit-learn -> JavaScript inference |
| Hosting | Netlify |

No frontend framework. No build step. `index.html` is the entire client application, including an embedded copy of Leaflet so the map works without depending on a CDN at runtime.

---

## Repository Structure

```
.
├── index.html                                  # Entire frontend application
├── supabase/
│   ├── schema.sql                              # Full schema: tables, enums, RLS policies,
│   │                                            # functions, triggers (reconstructed from
│   │                                            # live introspection of the deployed database)
│   └── functions/
│       ├── create-checkout-session/index.ts     # Stripe Checkout creation + authoritative
│       │                                        # server-side price recomputation
│       └── stripe-webhook/index.ts              # Payment confirmation, stock decrement
└── README.md
```

---

## Running This Yourself

1. Create a Supabase project.
2. Run `supabase/schema.sql` against it (SQL editor or CLI).
3. Deploy both Edge Functions under `supabase/functions/`.
4. Set Edge Function secrets: `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `SITE_URL`.
5. Register a Stripe webhook endpoint pointing at your deployed `stripe-webhook` function, subscribed to `checkout.session.completed`.
6. In `index.html`, update the `SUPABASE_URL` and publishable key constants near the top of the `<script>` block to match your project.
7. Serve `index.html` as a static file (Netlify, Vercel, or anything that serves a single HTML file).

---

## Honest Limitations

This was built in 48 hours and some things are deliberately simplified rather than faked as more complete than they are:

- **FSSAI verification is admin-reviewed, not API-verified.** No public FSSAI verification API exists, so a farmer's submission goes into an admin queue rather than pretending to auto-verify against a government system that isn't actually being called.
- **Interstate bulk delivery is still capped at the same 10 km radius as local delivery.** There is no real long-haul logistics system built. The UI says this explicitly rather than implying full interstate coverage.
- **Group delivery uses admin-triggered demo controls** (create nearby orders, form group, schedule, advance stop) to make the batching logic demonstrable without needing many concurrent real users placing orders in the same 5 km radius during a demo.
- **Delivery ETA is a computed estimate** (real road-routing distance and duration from OSRM, or a distance/speed fallback), not live GPS tracking of a physical vehicle.

---

## License

Built for SIH 2026 Internal Hackathon, Bennett University. Not currently licensed for reuse.
