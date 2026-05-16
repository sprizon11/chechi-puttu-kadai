-- Chechi Puttu — Supabase schema (replaces Firestore orders / checkout_sessions)

create extension if not exists "pgcrypto";

-- Orders: COD rows inserted by the app; Razorpay rows inserted by Edge Function (service role).
create table public.orders (
  id text primary key default gen_random_uuid ()::text,
  uid uuid not null references auth.users (id) on delete cascade,
  status text not null default 'placed',
  created_at timestamptz not null default now(),
  total_rupees int not null,
  delivery_line text not null,
  payment_mode text not null,
  schedule_line text,
  items jsonb not null default '[]'::jsonb,
  payment_status text,
  razorpay_order_id text,
  razorpay_payment_id text,
  checkout_session_id uuid
);

create table public.checkout_sessions (
  id uuid primary key default gen_random_uuid (),
  uid uuid not null references auth.users (id) on delete cascade,
  status text not null default 'pending_payment',
  items jsonb not null,
  total_rupees int not null,
  total_paise int not null,
  delivery_line text not null,
  schedule_line text,
  payment_mode text not null default 'razorpay',
  razorpay_order_id text,
  razorpay_payment_id text,
  order_id text,
  error_message text,
  fail_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.rzp_order_map (
  razorpay_order_id text primary key,
  session_id uuid not null references public.checkout_sessions (id) on delete cascade,
  uid uuid not null references auth.users (id) on delete cascade
);

create table public.push_tokens (
  uid uuid not null references auth.users (id) on delete cascade,
  token text not null,
  platform text,
  created_at timestamptz not null default now(),
  primary key (uid, token)
);

alter table public.orders enable row level security;
alter table public.checkout_sessions enable row level security;
alter table public.rzp_order_map enable row level security;
alter table public.push_tokens enable row level security;

-- JWT email claim (Supabase includes email by default for email/password & OAuth)
create or replace function public.is_chechi_admin () returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((auth.jwt () ->> 'email') = 'chechi@gmail.com', false);
$$;

create policy "orders_select_own" on public.orders for select using (auth.uid () = uid);

create policy "orders_select_admin" on public.orders for select using (public.is_chechi_admin ());

create policy "orders_insert_cod" on public.orders for insert
with check (
  auth.uid () = uid
  and payment_mode = 'cash_on_delivery'
  and status = 'placed'
);

create policy "checkout_select_own" on public.checkout_sessions for select using (auth.uid () = uid);

create policy "checkout_select_admin" on public.checkout_sessions for select using (public.is_chechi_admin ());

create policy "push_tokens_rw_own" on public.push_tokens for all using (auth.uid () = uid)
with check (auth.uid () = uid);

-- Realtime: order status updates → app can subscribe (replaces FCM data path for foreground).
alter publication supabase_realtime add table public.orders;
