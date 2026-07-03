-- ══════════════════════════════════════════
--  Mi Cesta · esquema de Supabase
--  Ejecutar en: Supabase Dashboard → SQL Editor → New query
-- ══════════════════════════════════════════

create extension if not exists "pgcrypto";

-- ── Perfil público de cada usuario (nombre + color de avatar) ──
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  color text not null default '#0055b3',
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "Los perfiles son visibles por cualquiera autenticado"
  on public.profiles for select
  using (true);

create policy "Cada usuario inserta solo su propio perfil"
  on public.profiles for insert
  with check (auth.uid() = id);

create policy "Cada usuario actualiza solo su propio perfil"
  on public.profiles for update
  using (auth.uid() = id);

-- ── Datos de la app por usuario: supermercados, artículos, precios, historial ──
create table if not exists public.user_data (
  user_id uuid primary key references auth.users(id) on delete cascade,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.user_data enable row level security;

create policy "Cada usuario ve solo sus propios datos"
  on public.user_data for select
  using (auth.uid() = user_id);

create policy "Cada usuario inserta solo sus propios datos"
  on public.user_data for insert
  with check (auth.uid() = user_id);

create policy "Cada usuario actualiza solo sus propios datos"
  on public.user_data for update
  using (auth.uid() = user_id);

-- ── Al registrarse un usuario nuevo, crear su perfil y su fila de datos vacía ──
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, name, color)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    coalesce(new.raw_user_meta_data->>'color', '#0055b3')
  );
  insert into public.user_data (user_id, data)
  values (
    new.id,
    jsonb_build_object(
      'stores', '[]'::jsonb,
      'items', '{}'::jsonb,
      'prices', '{}'::jsonb,
      'history', '[]'::jsonb,
      'monthlySpend', jsonb_build_object('amount', 0, 'month', extract(month from now())::int - 1, 'year', extract(year from now())::int),
      'monthlyHistory', '[]'::jsonb
    )
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ── Mantener updated_at al día en cada escritura ──
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists user_data_set_updated_at on public.user_data;
create trigger user_data_set_updated_at
  before update on public.user_data
  for each row execute procedure public.set_updated_at();

-- ── Habilitar Realtime en user_data (sincronización entre pestañas/dispositivos) ──
alter publication supabase_realtime add table public.user_data;
