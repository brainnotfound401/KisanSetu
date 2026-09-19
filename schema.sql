-- =====================================================================
-- KisanSetu — Database Schema
-- Reconstructed from the live Supabase project via information_schema /
-- pg_catalog introspection, so this reflects the actual deployed state,
-- not a hand-maintained migration history.
-- =====================================================================

-- ---------- ENUM TYPES ----------
create type public.user_role as enum ('farmer_fpo', 'consumer', 'bulk_buyer', 'transporter', 'admin');
create type public.listing_status as enum ('available', 'sold_out', 'expired');
create type public.quality_grade as enum ('A', 'B', 'C');
create type public.order_status as enum (
  'requested', 'accepted', 'rejected', 'pickup_scheduled', 'in_transit', 'delivered', 'cancelled',
  'waiting_for_group', 'group_created', 'group_scheduled', 'out_for_delivery'
);
create type public.pickup_status as enum ('pending', 'assigned', 'in_transit', 'completed');
create type public.fssai_status as enum ('NOT_PROVIDED', 'PENDING', 'VERIFIED', 'FAILED');
create type public.delivery_group_status as enum ('forming', 'scheduled', 'in_transit', 'completed');

-- ---------- TABLES ----------

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  role user_role not null default 'consumer',
  phone text,
  location text,
  verified boolean not null default false,
  created_at timestamptz not null default now(),
  preferred_language text not null default 'en',
  language_chosen boolean not null default false,
  role_confirmed boolean not null default true,
  aadhaar_doc_path text,
  avatar_path text,
  latitude double precision,
  longitude double precision,
  farmer_id_code text,
  farm_size text,
  crops_grown text,
  farming_experience_years integer,
  fssai_number text,
  fssai_status fssai_status not null default 'NOT_PROVIDED',
  fssai_submitted_at timestamptz,
  fssai_verified_at timestamptz,
  self_delivery_total_savings numeric not null default 0,
  self_delivery_count integer not null default 0
);

create table public.produce_listings (
  id uuid primary key default gen_random_uuid(),
  farmer_id uuid not null references public.profiles(id),
  crop_name text not null,
  category text,
  quantity numeric not null,
  unit text not null default 'kg',
  expected_price numeric not null,
  location text,
  harvest_date date,
  available_from date,
  quality_grade quality_grade,
  min_order_qty numeric,
  photo_url text,
  status listing_status not null default 'available',
  created_at timestamptz not null default now(),
  latitude double precision,
  longitude double precision,
  state text
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.produce_listings(id),
  buyer_id uuid not null references public.profiles(id),
  quantity numeric not null,
  agreed_price numeric,
  status order_status not null default 'requested',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  payment_status text not null default 'unpaid',
  stripe_checkout_session_id text,
  stripe_payment_intent_id text,
  distance_km numeric,
  delivery_charge numeric,
  delivery_method text not null default 'direct' check (delivery_method in ('direct','group')),
  delivery_group_id uuid,
  stop_sequence integer,
  delivery_lat double precision,
  delivery_lng double precision,
  delivery_choice_made boolean not null default false,
  delivery_mode text not null default 'platform' check (delivery_mode in ('platform','self_delivery')),
  platform_fee_amount numeric,
  self_delivery_discount_amount numeric,
  net_platform_fee numeric,
  procurement_type text check (procurement_type in ('within-state','interstate')),
  buyer_state text,
  farmer_state text,
  is_bulk_order boolean not null default false,
  minimum_required_weight numeric
);

create table public.pickups (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id),
  transporter_id uuid references public.profiles(id),
  pickup_point text,
  route text,
  eta timestamptz,
  transport_cost numeric,
  status pickup_status not null default 'pending',
  created_at timestamptz not null default now()
);

create table public.demand_forecast (
  id uuid primary key default gen_random_uuid(),
  crop_name text not null,
  location text not null,
  period text not null,
  predicted_demand numeric not null,
  recommendation text,
  created_at timestamptz not null default now()
);

create table public.farms (
  id uuid primary key default gen_random_uuid(),
  farmer_id uuid not null references public.profiles(id),
  name text not null,
  location text,
  land_size numeric,
  land_unit text not null default 'acres',
  soil_type text,
  irrigation_availability text,
  previous_crops text,
  current_crop text,
  sowing_date date,
  expected_harvest_date date,
  soil_test_info text,
  irrigation_info text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  latitude double precision,
  longitude double precision,
  soil_n numeric,
  soil_p numeric,
  soil_k numeric,
  soil_ph numeric,
  last_recommended_crop text,
  last_recommendation_confidence numeric,
  last_recommendation_at timestamptz
);

create table public.crop_scans (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id),
  farmer_id uuid not null references public.profiles(id),
  image_path text,
  possible_issue text,
  confidence integer,
  observed text,
  recommended_checks text,
  next_steps text,
  health_score integer,
  created_at timestamptz not null default now()
);

create table public.farm_history (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id),
  farmer_id uuid not null references public.profiles(id),
  season_label text,
  crop text,
  sowing_date date,
  harvest_date date,
  yield_estimate text,
  actual_yield text,
  diseases_detected text,
  pest_incidents text,
  notes text,
  created_at timestamptz not null default now()
);

create table public.expert_requests (
  id uuid primary key default gen_random_uuid(),
  farmer_id uuid not null references public.profiles(id),
  farm_id uuid references public.farms(id),
  scan_id uuid references public.crop_scans(id),
  message text not null,
  status text not null default 'open',
  created_at timestamptz not null default now()
);

create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.orders(id),
  farmer_id uuid not null references public.profiles(id),
  buyer_id uuid not null references public.profiles(id),
  rating smallint not null,
  quality_rating smallint,
  comment text,
  created_at timestamptz not null default now()
);

create table public.delivery_groups (
  id uuid primary key default gen_random_uuid(),
  group_code text not null unique,
  centroid_lat double precision not null,
  centroid_lng double precision not null,
  status delivery_group_status not null default 'forming',
  scheduled_at timestamptz,
  route_distance_km numeric,
  current_stop integer not null default 0,
  created_at timestamptz not null default now()
);

-- Deferred FK: orders.delivery_group_id couldn't reference this table until it existed.
alter table public.orders add constraint orders_delivery_group_id_fkey foreign key (delivery_group_id) references public.delivery_groups(id);

create table public.bulk_buyer_profiles (
  id uuid primary key references public.profiles(id) on delete cascade,
  org_name text not null,
  org_type text not null,
  org_type_other text,
  purposes text[] not null default '{}',
  purpose_other text,
  requirement_description text,
  contact_name text,
  contact_designation text,
  contact_designation_other text,
  contact_mobile text,
  contact_email text,
  address_building text,
  address_street text,
  address_city text,
  address_district text,
  address_state text,
  address_pincode text,
  delivery_same_as_org boolean not null default true,
  delivery_building text,
  delivery_street text,
  delivery_city text,
  delivery_district text,
  delivery_state text,
  delivery_pincode text,
  delivery_lat double precision,
  delivery_lng double precision,
  purchase_categories text[] not null default '{}',
  expected_order_volume text,
  purchase_frequency text,
  delivery_frequency text,
  preferred_delivery_time text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.bulk_buyer_products (
  id uuid primary key default gen_random_uuid(),
  bulk_buyer_id uuid not null references public.bulk_buyer_profiles(id) on delete cascade,
  product_name text not null,
  typical_quantity text,
  frequency text,
  created_at timestamptz not null default now()
);

-- ---------- STORAGE BUCKETS ----------
-- verification-docs: private, 5MB limit, jpg/png/pdf — Aadhaar/FSSAI documents
-- avatars: public, 2MB limit, jpg/png/webp — profile pictures

-- =====================================================================
-- FUNCTIONS
-- All privileged operations (fee calculation, verification, group-delivery
-- state machine) run as SECURITY DEFINER functions with explicit auth
-- checks inside — never trusting RLS alone for money-related logic.
-- =====================================================================

create or replace function public.is_admin(uid uuid)
 returns boolean
 language sql stable security definer
 set search_path to 'public'
as $function$
  select exists(select 1 from public.profiles where id = uid and role = 'admin');
$function$;

create or replace function public.handle_new_user()
 returns trigger
 language plpgsql security definer
 set search_path to 'public'
as $function$
begin
  insert into public.profiles (id, full_name, role, phone, preferred_language, role_confirmed)
  values (
    new.id,
    new.raw_user_meta_data->>'full_name',
    coalesce((new.raw_user_meta_data->>'role')::public.user_role, 'consumer'),
    new.raw_user_meta_data->>'phone',
    coalesce(new.raw_user_meta_data->>'preferred_language', 'en'),
    (new.raw_user_meta_data->>'role') is not null
  );
  return new;
end;
$function$;

create or replace function public.assign_farmer_id()
 returns trigger
 language plpgsql security definer
 set search_path to 'public'
as $function$
declare
  new_code text;
begin
  if new.role = 'farmer_fpo' and new.farmer_id_code is null then
    loop
      new_code := 'KS-FRM-' || lpad(floor(random() * 100000)::text, 5, '0');
      exit when not exists (select 1 from public.profiles where farmer_id_code = new_code);
    end loop;
    new.farmer_id_code := new_code;
  end if;
  return new;
end;
$function$;

create or replace function public.protect_sensitive_profile_fields()
 returns trigger
 language plpgsql security definer
 set search_path to 'public'
as $function$
begin
  -- A trusted server-side RPC (e.g. confirm_self_delivery) sets this local flag right before
  -- writing aggregate/earned fields it computed itself -- this is NOT settable by ordinary
  -- client requests, only by our own SECURITY DEFINER functions.
  if current_setting('kisansetu.trusted_rpc', true) = 'true' then
    return new;
  end if;

  if public.is_admin(auth.uid()) then
    return new;
  end if;

  if new.verified is distinct from old.verified and new.verified = true then
    raise exception 'Only an admin can grant account verification.';
  end if;
  if new.role is distinct from old.role then
    raise exception 'Role cannot be changed directly.';
  end if;
  if new.farmer_id_code is distinct from old.farmer_id_code then
    raise exception 'Farmer ID cannot be changed directly.';
  end if;
  if new.fssai_verified_at is distinct from old.fssai_verified_at then
    raise exception 'Only an admin can set the FSSAI verification date.';
  end if;
  if new.fssai_status is distinct from old.fssai_status and new.fssai_status <> 'PENDING' then
    raise exception 'Only an admin can verify or reject FSSAI status.';
  end if;
  if new.self_delivery_total_savings is distinct from old.self_delivery_total_savings then
    raise exception 'Self-delivery savings can only be credited by the system.';
  end if;
  if new.self_delivery_count is distinct from old.self_delivery_count then
    raise exception 'Self-delivery count can only be updated by the system.';
  end if;

  return new;
end;
$function$;

create or replace function public.protect_order_fee_fields()
 returns trigger
 language plpgsql security definer
 set search_path to 'public'
as $function$
begin
  if current_setting('kisansetu.trusted_rpc', true) = 'true' then
    return new;
  end if;
  if public.is_admin(auth.uid()) then
    return new;
  end if;
  if new.platform_fee_amount is distinct from old.platform_fee_amount then
    raise exception 'Platform fee can only be computed by the system.';
  end if;
  if new.self_delivery_discount_amount is distinct from old.self_delivery_discount_amount then
    raise exception 'Self-delivery discount can only be computed by the system.';
  end if;
  if new.net_platform_fee is distinct from old.net_platform_fee then
    raise exception 'Net platform fee can only be computed by the system.';
  end if;
  return new;
end;
$function$;

create or replace function public.haversine_km(lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision)
 returns double precision
 language sql immutable
 set search_path to 'public'
as $function$
  select 6371 * 2 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)
  ));
$function$;

create or replace function public.is_order_assigned_transporter(p_order_id uuid, p_uid uuid)
 returns boolean
 language sql stable security definer
 set search_path to 'public'
as $function$
  select exists (select 1 from pickups where order_id = p_order_id and transporter_id = p_uid);
$function$;

create or replace function public.is_order_buyer_or_farmer(p_order_id uuid, p_uid uuid)
 returns boolean
 language sql stable security definer
 set search_path to 'public'
as $function$
  select exists (
    select 1 from orders o join produce_listings pl on pl.id = o.listing_id
    where o.id = p_order_id and (o.buyer_id = p_uid or pl.farmer_id = p_uid)
  );
$function$;

create or replace function public.get_group_delivery_info(p_order_id uuid)
 returns jsonb
 language plpgsql security definer
 set search_path to 'public'
as $function$
declare
  v_group_id uuid;
  v_my_stop int;
  v_group record;
  v_result jsonb;
begin
  if not exists (
    select 1 from orders o
    join produce_listings pl on pl.id = o.listing_id
    where o.id = p_order_id
      and (o.buyer_id = auth.uid() or pl.farmer_id = auth.uid() or public.is_admin(auth.uid()))
  ) then
    raise exception 'Not authorized to view this order''s delivery info';
  end if;

  select delivery_group_id, stop_sequence into v_group_id, v_my_stop from orders where id = p_order_id;
  if v_group_id is null then
    return jsonb_build_object('grouped', false);
  end if;

  select * into v_group from delivery_groups where id = v_group_id;

  -- Stops carry ONLY coordinates + stop_sequence + status (needed to draw the route and mark
  -- progress on a map) -- never buyer_id, name, phone, or address text, even for the map view.
  select jsonb_build_object(
    'grouped', true,
    'group_code', v_group.group_code,
    'status', v_group.status,
    'scheduled_at', v_group.scheduled_at,
    'route_distance_km', v_group.route_distance_km,
    'current_stop', v_group.current_stop,
    'my_stop_sequence', v_my_stop,
    'order_count', (select count(*) from orders where delivery_group_id = v_group_id),
    'pickup_points', (
      select coalesce(jsonb_agg(distinct jsonb_build_object('lat', pl.latitude, 'lng', pl.longitude)), '[]'::jsonb)
      from orders o join produce_listings pl on pl.id = o.listing_id
      where o.delivery_group_id = v_group_id and pl.latitude is not null and pl.longitude is not null
    ),
    'stops', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'stop_sequence', o.stop_sequence, 'status', o.status,
        'lat', coalesce(o.delivery_lat, p.latitude), 'lng', coalesce(o.delivery_lng, p.longitude)
      ) order by o.stop_sequence), '[]'::jsonb)
      from orders o join profiles p on p.id = o.buyer_id where o.delivery_group_id = v_group_id
    )
  ) into v_result;

  return v_result;
end;
$function$;

create or replace function public.form_delivery_group(p_order_id uuid)
 returns jsonb
 language plpgsql security definer
 set search_path to 'public'
as $function$
declare
  v_radius_km constant double precision := 5.0;
  v_min_orders constant int := 2;
  v_buyer_id uuid;
  v_my_lat double precision;
  v_my_lng double precision;
  v_compatible_ids uuid[];
  v_group_id uuid;
  v_group_code text;
  v_count int;
  v_avg_lat double precision;
  v_avg_lng double precision;
begin
  select buyer_id into v_buyer_id from orders where id = p_order_id;
  if v_buyer_id is null or v_buyer_id <> auth.uid() then
    raise exception 'Not authorized to form a group for this order';
  end if;

  select coalesce(o.delivery_lat, p.latitude), coalesce(o.delivery_lng, p.longitude)
  into v_my_lat, v_my_lng
  from orders o join profiles p on p.id = o.buyer_id
  where o.id = p_order_id and o.delivery_method = 'group' and o.status = 'waiting_for_group' and o.delivery_group_id is null;

  if v_my_lat is null or v_my_lng is null then
    return jsonb_build_object('grouped', false, 'reason', 'not_eligible_or_missing_location');
  end if;

  select array_agg(o.id) into v_compatible_ids
  from orders o
  join profiles p on p.id = o.buyer_id
  where o.delivery_method = 'group'
    and o.status = 'waiting_for_group'
    and o.delivery_group_id is null
    and o.id <> p_order_id
    and coalesce(o.delivery_lat, p.latitude) is not null and coalesce(o.delivery_lng, p.longitude) is not null
    and public.haversine_km(v_my_lat, v_my_lng, coalesce(o.delivery_lat, p.latitude), coalesce(o.delivery_lng, p.longitude)) <= v_radius_km;

  v_count := coalesce(array_length(v_compatible_ids, 1), 0) + 1;

  if v_count < v_min_orders then
    return jsonb_build_object('grouped', false, 'reason', 'waiting_for_more_orders', 'compatible_found', v_count - 1);
  end if;

  v_group_code := 'GD-' || lpad(floor(random() * 10000)::text, 4, '0');

  select avg(coalesce(o.delivery_lat, p.latitude)), avg(coalesce(o.delivery_lng, p.longitude))
  into v_avg_lat, v_avg_lng
  from orders o join profiles p on p.id = o.buyer_id
  where o.id = any(v_compatible_ids) or o.id = p_order_id;

  insert into delivery_groups (group_code, centroid_lat, centroid_lng, status)
  values (v_group_code, v_avg_lat, v_avg_lng, 'forming')
  returning id into v_group_id;

  update orders set delivery_group_id = v_group_id, status = 'group_created',
    stop_sequence = sub.rn
  from (
    select id, row_number() over (order by created_at) as rn
    from orders where id = any(v_compatible_ids) or id = p_order_id
  ) sub
  where orders.id = sub.id;

  return jsonb_build_object('grouped', true, 'group_id', v_group_id, 'group_code', v_group_code, 'order_count', v_count);
end;
$function$;

create or replace function public.schedule_delivery_group(p_group_id uuid)
 returns jsonb
 language plpgsql security definer
 set search_path to 'public'
as $function$
declare
  v_route_km double precision;
  v_scheduled_at timestamptz;
  v_now timestamptz := now();
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'Only an admin can schedule a delivery group (demo control)';
  end if;

  select coalesce(sum(public.haversine_km(a.lat, a.lng, b.lat, b.lng)), 0)
  into v_route_km
  from (
    select o.stop_sequence as seq, coalesce(o.delivery_lat, p.latitude) as lat, coalesce(o.delivery_lng, p.longitude) as lng
    from orders o join profiles p on p.id = o.buyer_id
    where o.delivery_group_id = p_group_id
  ) a
  join (
    select o.stop_sequence as seq, coalesce(o.delivery_lat, p.latitude) as lat, coalesce(o.delivery_lng, p.longitude) as lng
    from orders o join profiles p on p.id = o.buyer_id
    where o.delivery_group_id = p_group_id
  ) b on b.seq = a.seq + 1;

  -- Dynamic scheduling: an earlier same-day evening slot if there's still time to consolidate more
  -- orders today, otherwise the next morning -- not always the same fixed delay.
  if extract(hour from v_now) < 14 then
    v_scheduled_at := date_trunc('day', v_now) + interval '20 hours';
  else
    v_scheduled_at := date_trunc('day', v_now) + interval '1 day' + interval '11 hours 30 minutes';
  end if;

  update delivery_groups
  set status = 'scheduled', scheduled_at = v_scheduled_at, route_distance_km = round(v_route_km::numeric, 1)
  where id = p_group_id;

  update orders set status = 'group_scheduled' where delivery_group_id = p_group_id;

  return jsonb_build_object('scheduled_at', v_scheduled_at, 'route_distance_km', round(v_route_km::numeric, 1));
end;
$function$;

create or replace function public.start_group_delivery(p_group_id uuid)
 returns void
 language plpgsql security definer
 set search_path to 'public'
as $function$
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'Only an admin can start a delivery group (demo control)';
  end if;
  update delivery_groups set status = 'in_transit', current_stop = 1 where id = p_group_id;
  update orders set status = 'out_for_delivery' where delivery_group_id = p_group_id;
end;
$function$;

create or replace function public.advance_group_stop(p_group_id uuid)
 returns jsonb
 language plpgsql security definer
 set search_path to 'public'
as $function$
declare
  v_current_stop int;
  v_max_stop int;
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'Only an admin can advance a delivery group (demo control)';
  end if;

  select current_stop into v_current_stop from delivery_groups where id = p_group_id;
  select max(stop_sequence) into v_max_stop from orders where delivery_group_id = p_group_id;

  -- Mark the stop the vehicle is currently AT as delivered, THEN move to the next one.
  update orders set status = 'delivered' where delivery_group_id = p_group_id and stop_sequence = v_current_stop;

  if v_current_stop >= v_max_stop then
    update delivery_groups set status = 'completed' where id = p_group_id;
    return jsonb_build_object('current_stop', v_current_stop, 'completed', true);
  else
    update delivery_groups set current_stop = v_current_stop + 1 where id = p_group_id;
    return jsonb_build_object('current_stop', v_current_stop + 1, 'completed', false);
  end if;
end;
$function$;

create or replace function public.complete_group_delivery(p_group_id uuid)
 returns void
 language plpgsql security definer
 set search_path to 'public'
as $function$
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'Only an admin can complete a delivery group (demo control)';
  end if;
  update orders set status = 'delivered' where delivery_group_id = p_group_id;
  update delivery_groups set status = 'completed', current_stop = (select max(stop_sequence) from orders where delivery_group_id = p_group_id) where id = p_group_id;
end;
$function$;

create or replace function public.create_demo_nearby_orders(p_buyer_id uuid, p_listing_id uuid, p_anchor_lat double precision, p_anchor_lng double precision)
 returns jsonb
 language plpgsql security definer
 set search_path to 'public'
as $function$
declare
  v_price numeric;
  v_created uuid[];
  v_offsets double precision[][] := array[
    array[0.0, 0.0],
    array[0.018, 0.0],
    array[0.0, 0.036],
    array[0.108, 0.0]
  ];
  i int;
  v_new_id uuid;
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'Only an admin can create demo orders (demo control)';
  end if;

  select expected_price into v_price from produce_listings where id = p_listing_id;
  if v_price is null then
    raise exception 'Listing not found';
  end if;

  for i in 1..array_length(v_offsets, 1) loop
    insert into orders (listing_id, buyer_id, quantity, agreed_price, status, payment_status, delivery_method, delivery_lat, delivery_lng)
    values (
      p_listing_id, p_buyer_id, 1, v_price, 'waiting_for_group', 'paid', 'group',
      p_anchor_lat + v_offsets[i][1], p_anchor_lng + v_offsets[i][2]
    )
    returning id into v_new_id;
    v_created := array_append(v_created, v_new_id);
  end loop;

  return jsonb_build_object('created_order_ids', v_created);
end;
$function$;

create or replace function public.self_delivery_config()
 returns jsonb
 language sql immutable
 set search_path to 'public'
as $function$
  select jsonb_build_object('platform_fee_rate', 0.05, 'delivery_savings_share', 0.5);
$function$;

create or replace function public.confirm_self_delivery(p_order_id uuid)
 returns jsonb
 language plpgsql security definer
 set search_path to 'public'
as $function$
declare
  v_farmer_id uuid;
  v_status public.order_status;
  v_payment_status text;
  v_quantity numeric;
  v_price numeric;
  v_delivery_charge numeric;
  v_order_value numeric;
  v_platform_fee numeric;
  v_discount numeric;
  v_net_fee numeric;
  v_cfg jsonb := public.self_delivery_config();
begin
  select pl.farmer_id, o.status, o.payment_status, o.quantity, pl.expected_price, o.delivery_charge
  into v_farmer_id, v_status, v_payment_status, v_quantity, v_price, v_delivery_charge
  from orders o join produce_listings pl on pl.id = o.listing_id
  where o.id = p_order_id;

  if v_farmer_id is null then
    raise exception 'Order not found';
  end if;
  if v_farmer_id <> auth.uid() then
    raise exception 'Not authorized to confirm self-delivery for this order';
  end if;
  if v_payment_status <> 'paid' then
    raise exception 'Order must be paid before confirming delivery';
  end if;
  if v_status = 'delivered' then
    raise exception 'This order has already been marked delivered';
  end if;

  v_order_value := v_quantity * v_price;
  v_platform_fee := round((v_order_value * (v_cfg->>'platform_fee_rate')::numeric)::numeric, 2);
  v_discount := round((coalesce(v_delivery_charge, 0) * (v_cfg->>'delivery_savings_share')::numeric)::numeric, 2);
  v_net_fee := greatest(0, v_platform_fee - v_discount);

  perform set_config('kisansetu.trusted_rpc', 'true', true);

  update orders set
    delivery_mode = 'self_delivery',
    status = 'delivered',
    platform_fee_amount = v_platform_fee,
    self_delivery_discount_amount = v_discount,
    net_platform_fee = v_net_fee
  where id = p_order_id;

  update profiles set
    self_delivery_total_savings = self_delivery_total_savings + v_discount,
    self_delivery_count = self_delivery_count + 1
  where id = auth.uid();

  return jsonb_build_object(
    'order_value', v_order_value, 'platform_fee', v_platform_fee,
    'discount', v_discount, 'net_fee', v_net_fee
  );
end;
$function$;

-- ---------- TRIGGERS ----------
create trigger on_auth_user_created after insert on auth.users
  for each row execute procedure public.handle_new_user();

create trigger assign_farmer_id_trigger before insert or update on public.profiles
  for each row execute procedure public.assign_farmer_id();

create trigger protect_sensitive_profile_fields_trigger before update on public.profiles
  for each row execute procedure public.protect_sensitive_profile_fields();

create trigger protect_order_fee_fields_trigger before update on public.orders
  for each row execute procedure public.protect_order_fee_fields();

-- =====================================================================
-- ROW LEVEL SECURITY
-- Enabled on every table. Policies below exactly as deployed.
-- =====================================================================

alter table public.profiles enable row level security;
alter table public.produce_listings enable row level security;
alter table public.orders enable row level security;
alter table public.pickups enable row level security;
alter table public.demand_forecast enable row level security;
alter table public.farms enable row level security;
alter table public.crop_scans enable row level security;
alter table public.farm_history enable row level security;
alter table public.expert_requests enable row level security;
alter table public.reviews enable row level security;
alter table public.delivery_groups enable row level security;
alter table public.bulk_buyer_profiles enable row level security;
alter table public.bulk_buyer_products enable row level security;

CREATE POLICY "profiles are viewable by everyone" ON public.profiles FOR SELECT USING (true);
CREATE POLICY "users can update their own profile" ON public.profiles FOR UPDATE USING ((auth.uid() = id));
CREATE POLICY "admins can update any profile" ON public.profiles FOR UPDATE USING (is_admin(auth.uid()));

CREATE POLICY "listings are viewable by everyone" ON public.produce_listings FOR SELECT USING (true);
CREATE POLICY "farmers can insert their own listings" ON public.produce_listings FOR INSERT WITH CHECK ((auth.uid() = farmer_id));
CREATE POLICY "farmers can update their own listings" ON public.produce_listings FOR UPDATE USING ((auth.uid() = farmer_id));
CREATE POLICY "farmers can delete their own listings" ON public.produce_listings FOR DELETE USING ((auth.uid() = farmer_id));

CREATE POLICY "orders visible to buyer, farmer, or assigned transporter" ON public.orders FOR SELECT USING (
  (auth.uid() = buyer_id) OR
  (auth.uid() IN (SELECT farmer_id FROM produce_listings WHERE id = orders.listing_id)) OR
  is_order_assigned_transporter(id, auth.uid())
);
CREATE POLICY "buyers can create orders" ON public.orders FOR INSERT WITH CHECK ((auth.uid() = buyer_id));
CREATE POLICY "buyer, farmer, or assigned transporter can update order status" ON public.orders FOR UPDATE USING (
  (auth.uid() = buyer_id) OR
  (auth.uid() IN (SELECT farmer_id FROM produce_listings WHERE id = orders.listing_id)) OR
  is_order_assigned_transporter(id, auth.uid())
);

CREATE POLICY "pickups visible to involved parties" ON public.pickups FOR SELECT USING (
  (auth.uid() = transporter_id) OR is_order_buyer_or_farmer(order_id, auth.uid())
);
CREATE POLICY "pending pickups are visible as open jobs" ON public.pickups FOR SELECT USING (status = 'pending');
CREATE POLICY "farmer can schedule pickup for own order" ON public.pickups FOR INSERT WITH CHECK (
  auth.uid() IN (SELECT pl.farmer_id FROM orders o JOIN produce_listings pl ON pl.id = o.listing_id WHERE o.id = pickups.order_id)
);
CREATE POLICY "transporter can claim a pending pickup" ON public.pickups FOR UPDATE USING (status = 'pending') WITH CHECK (transporter_id = auth.uid());
CREATE POLICY "transporter can update assigned pickup" ON public.pickups FOR UPDATE USING (auth.uid() = transporter_id);

CREATE POLICY "forecast is viewable by everyone" ON public.demand_forecast FOR SELECT USING (true);

CREATE POLICY "farmer manages own farms" ON public.farms FOR ALL USING (auth.uid() = farmer_id) WITH CHECK (auth.uid() = farmer_id);
CREATE POLICY "admins can view all farms" ON public.farms FOR SELECT USING (is_admin(auth.uid()));

CREATE POLICY "farmer manages own scans" ON public.crop_scans FOR ALL USING (auth.uid() = farmer_id) WITH CHECK (auth.uid() = farmer_id);
CREATE POLICY "admins can view all scans" ON public.crop_scans FOR SELECT USING (is_admin(auth.uid()));

CREATE POLICY "farmer manages own farm history" ON public.farm_history FOR ALL USING (auth.uid() = farmer_id) WITH CHECK (auth.uid() = farmer_id);
CREATE POLICY "admins can view all farm history" ON public.farm_history FOR SELECT USING (is_admin(auth.uid()));

CREATE POLICY "farmer manages own expert requests" ON public.expert_requests FOR ALL USING (auth.uid() = farmer_id) WITH CHECK (auth.uid() = farmer_id);
CREATE POLICY "admins can view and update expert requests" ON public.expert_requests FOR SELECT USING (is_admin(auth.uid()));
CREATE POLICY "admins can update expert request status" ON public.expert_requests FOR UPDATE USING (is_admin(auth.uid()));

CREATE POLICY "reviews are publicly viewable" ON public.reviews FOR SELECT USING (true);
CREATE POLICY "buyer can review their own delivered order once" ON public.reviews FOR INSERT WITH CHECK (
  (auth.uid() = buyer_id) AND EXISTS (
    SELECT 1 FROM orders o WHERE o.id = reviews.order_id AND o.buyer_id = auth.uid() AND o.status = 'delivered'
  )
);

CREATE POLICY "group visible to members or admin" ON public.delivery_groups FOR SELECT USING (
  is_admin(auth.uid()) OR id IN (
    SELECT delivery_group_id FROM orders
    WHERE delivery_group_id IS NOT NULL
      AND (buyer_id = auth.uid() OR auth.uid() IN (SELECT farmer_id FROM produce_listings WHERE id = orders.listing_id))
  )
);
CREATE POLICY "admin manages delivery groups" ON public.delivery_groups FOR ALL USING (is_admin(auth.uid())) WITH CHECK (is_admin(auth.uid()));

CREATE POLICY "bulk buyer manages own profile" ON public.bulk_buyer_profiles FOR ALL USING (
  (auth.uid() = id) OR is_admin(auth.uid())
) WITH CHECK ((auth.uid() = id) OR is_admin(auth.uid()));

CREATE POLICY "bulk buyer manages own products" ON public.bulk_buyer_products FOR ALL USING (
  is_admin(auth.uid()) OR bulk_buyer_id IN (SELECT id FROM bulk_buyer_profiles WHERE id = auth.uid())
) WITH CHECK (
  is_admin(auth.uid()) OR bulk_buyer_id IN (SELECT id FROM bulk_buyer_profiles WHERE id = auth.uid())
);

-- ---------- FUNCTION PERMISSIONS ----------
revoke execute on function public.is_order_assigned_transporter(uuid, uuid) from public, anon;
revoke execute on function public.is_order_buyer_or_farmer(uuid, uuid) from public, anon;
grant execute on function public.is_order_assigned_transporter(uuid, uuid) to authenticated;
grant execute on function public.is_order_buyer_or_farmer(uuid, uuid) to authenticated;

revoke execute on function public.get_group_delivery_info(uuid) from public, anon;
revoke execute on function public.form_delivery_group(uuid) from public, anon;
revoke execute on function public.schedule_delivery_group(uuid) from public, anon;
revoke execute on function public.start_group_delivery(uuid) from public, anon;
revoke execute on function public.advance_group_stop(uuid) from public, anon;
revoke execute on function public.complete_group_delivery(uuid) from public, anon;
revoke execute on function public.create_demo_nearby_orders(uuid, uuid, double precision, double precision) from public, anon;
revoke execute on function public.self_delivery_config() from public, anon;
revoke execute on function public.confirm_self_delivery(uuid) from public, anon;

grant execute on function public.get_group_delivery_info(uuid) to authenticated;
grant execute on function public.form_delivery_group(uuid) to authenticated;
grant execute on function public.schedule_delivery_group(uuid) to authenticated;
grant execute on function public.start_group_delivery(uuid) to authenticated;
grant execute on function public.advance_group_stop(uuid) to authenticated;
grant execute on function public.complete_group_delivery(uuid) to authenticated;
grant execute on function public.create_demo_nearby_orders(uuid, uuid, double precision, double precision) to authenticated;
grant execute on function public.self_delivery_config() to authenticated;
grant execute on function public.confirm_self_delivery(uuid) to authenticated;

revoke execute on function public.protect_order_fee_fields() from public, anon, authenticated;
