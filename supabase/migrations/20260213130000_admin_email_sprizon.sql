-- Align DB admin check with app reserved admin email (JWT email claim).
create or replace function public.is_chechi_admin () returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((auth.jwt () ->> 'email') = 'sprizon1311@gmail.com', false);
$$;
