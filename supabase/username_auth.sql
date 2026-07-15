create extension if not exists pgcrypto with schema extensions;

create table if not exists public.app_users (
  id uuid primary key default gen_random_uuid(),
  username text not null unique,
  password_hash text not null,
  full_name text not null,
  area text not null default 'Institucional',
  role text not null default 'Usuario' check (role in ('Administrador','Director','Supervisor','Analista','Consulta','Usuario')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_login_at timestamptz
);

create table if not exists public.app_user_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.app_users(id) on delete cascade,
  token_hash text not null unique,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

alter table public.app_users enable row level security;
alter table public.app_user_sessions enable row level security;
revoke all on public.app_users, public.app_user_sessions from anon, authenticated;

create or replace function public.register_app_user(p_username text, p_password text, p_full_name text, p_area text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_username text := lower(trim(p_username));
begin
  if v_username !~ '^[a-z0-9._-]{3,32}$' then return jsonb_build_object('success',false,'error','El usuario debe tener entre 3 y 32 caracteres y usar solo letras, números, punto, guion o guion bajo.'); end if;
  if length(p_password) < 6 then return jsonb_build_object('success',false,'error','La contraseña debe tener al menos 6 caracteres.'); end if;
  if length(trim(p_full_name)) < 3 then return jsonb_build_object('success',false,'error','Escribe el nombre completo.'); end if;
  if exists(select 1 from public.app_users where username=v_username) then return jsonb_build_object('success',false,'error','Ese nombre de usuario ya existe.'); end if;
  insert into public.app_users(username,password_hash,full_name,area) values(v_username,crypt(p_password,gen_salt('bf',10)),trim(p_full_name),coalesce(nullif(trim(p_area),''),'Institucional'));
  return jsonb_build_object('success',true);
end $$;

create or replace function public.login_app_user(p_username text, p_password text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_user public.app_users%rowtype; v_token text;
begin
  select * into v_user from public.app_users where username=lower(trim(p_username)) and active=true;
  if v_user.id is null or v_user.password_hash <> crypt(p_password,v_user.password_hash) then return null; end if;
  delete from public.app_user_sessions where expires_at < now();
  v_token := encode(gen_random_bytes(32),'hex');
  insert into public.app_user_sessions(user_id,token_hash,expires_at) values(v_user.id,encode(digest(v_token,'sha256'),'hex'),now()+interval '12 hours');
  update public.app_users set last_login_at=now() where id=v_user.id;
  return jsonb_build_object('token',v_token,'user',jsonb_build_object('id',v_user.id,'username',v_user.username,'full_name',v_user.full_name,'area',v_user.area,'role',v_user.role));
end $$;

create or replace function public.get_app_session(p_token text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_user public.app_users%rowtype;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true;
  if v_user.id is null then return null; end if;
  return jsonb_build_object('user',jsonb_build_object('id',v_user.id,'username',v_user.username,'full_name',v_user.full_name,'area',v_user.area,'role',v_user.role));
end $$;

create or replace function public.logout_app_session(p_token text)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
begin delete from public.app_user_sessions where token_hash=encode(digest(p_token,'sha256'),'hex'); return true; end $$;

revoke all on function public.register_app_user(text,text,text,text), public.login_app_user(text,text), public.get_app_session(text), public.logout_app_session(text) from public;
grant execute on function public.register_app_user(text,text,text,text), public.login_app_user(text,text), public.get_app_session(text), public.logout_app_session(text) to anon, authenticated;
