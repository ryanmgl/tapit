-- Run this once in Supabase: SQL Editor → New query.
create extension if not exists pgcrypto;
create type public.app_role as enum ('platform_admin','business_owner','staff','customer');
create table public.profiles (id uuid primary key references auth.users(id) on delete cascade, role public.app_role not null default 'customer', full_name text, created_at timestamptz not null default now());
create table public.businesses (id uuid primary key default gen_random_uuid(), name text not null, city text, active boolean not null default true, created_at timestamptz not null default now());
create table public.business_members (business_id uuid references public.businesses(id) on delete cascade, user_id uuid references auth.users(id) on delete cascade, role public.app_role not null check (role in ('business_owner','staff')), primary key (business_id,user_id));
create table public.counters (id uuid primary key default gen_random_uuid(), business_id uuid not null references public.businesses(id) on delete cascade, name text not null, active boolean not null default true, created_at timestamptz not null default now());
create table public.customers (id uuid primary key references auth.users(id) on delete cascade, email text unique not null, full_name text, created_at timestamptz not null default now());
create table public.tap_authorizations (id uuid primary key default gen_random_uuid(), counter_id uuid not null references public.counters(id) on delete cascade, staff_id uuid references auth.users(id), stamps integer not null check(stamps between 1 and 10), expires_at timestamptz not null, used_at timestamptz, claimed_by uuid references auth.users(id), created_at timestamptz not null default now());
create table public.stamps (id uuid primary key default gen_random_uuid(), customer_id uuid not null references public.customers(id), counter_id uuid references public.counters(id), business_id uuid not null references public.businesses(id), stamps integer not null check(stamps between 1 and 10), source text not null check(source in ('nfc','manual')), issued_by uuid references auth.users(id), created_at timestamptz not null default now());
create index on public.tap_authorizations(counter_id,expires_at) where used_at is null; create index on public.stamps(business_id,created_at desc);
alter table public.profiles enable row level security; alter table public.businesses enable row level security; alter table public.business_members enable row level security; alter table public.counters enable row level security; alter table public.customers enable row level security; alter table public.tap_authorizations enable row level security; alter table public.stamps enable row level security;
create or replace function public.is_platform_admin() returns boolean language sql stable security definer set search_path=public as $$select exists(select 1 from public.profiles where id=auth.uid() and role='platform_admin')$$;
create policy "own profile" on public.profiles for select using (id=auth.uid() or public.is_platform_admin());
create policy "customer profile" on public.customers for select using (id=auth.uid()); create policy "customer update" on public.customers for update using (id=auth.uid()); create policy "customer insert" on public.customers for insert with check(id=auth.uid());
-- All privileged reads/writes are performed through verified Vercel API routes using the secret key.
-- After creating your first Auth user, promote only yourself:
-- update public.profiles set role='platform_admin' where id='<your-auth-user-id>';
-- If you use email/password sign-up, create a profile automatically:
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$begin insert into public.profiles(id,full_name) values(new.id,new.raw_user_meta_data->>'full_name') on conflict do nothing; return new; end;$$;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();
