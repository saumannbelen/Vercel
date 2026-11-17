-- Kontrola · esquema Supabase (PostgreSQL) con RLS por empresa_id
create extension if not exists "pgcrypto";

create table empresas (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  estado text not null default 'Activa' check (estado in ('Activa','Suspendida','Cancelada')),
  mensaje_bloqueo text,
  etiqueta_proceso text not null default 'Proceso',
  etiqueta_produccion text not null default 'Unidades',
  creado_en timestamptz default now()
);

create table procesos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas on delete cascade,
  nombre text not null,
  permite_produccion boolean not null default false,
  tarifa_unidad_extra int not null default 1500,
  unidades_base int not null default 5,
  sueldo_base_ref int not null default 500000,
  jornada_semanal numeric not null default 42,
  colacion_horas numeric not null default 1,
  dias_semana int not null default 5 check (dias_semana in (5,6)),
  supervisor_id uuid,
  creado_en timestamptz default now()
);

create table usuarios (
  id uuid primary key default gen_random_uuid(),
  auth_id uuid unique references auth.users on delete set null,
  empresa_id uuid references empresas on delete cascade, -- null = súper admin
  proceso_id uuid references procesos on delete set null,
  rut text not null,
  nombre text not null,
  rol text not null check (rol in ('super_admin','admin','supervisor','trabajador')),
  sueldo_base int,
  pacto_he boolean not null default false,
  pacto_vence date,
  activo boolean not null default true,
  unique (empresa_id, rut)
);
alter table procesos add foreign key (supervisor_id) references usuarios(id) on delete set null;

create table asistencias (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas on delete cascade,
  proceso_id uuid references procesos on delete set null,
  usuario_id uuid not null references usuarios on delete cascade,
  fecha date not null default current_date,
  entrada timestamptz,
  salida timestamptz,
  horas_trabajadas numeric,
  horas_extra numeric not null default 0 check (horas_extra between 0 and 2), -- Art. 31
  origen text not null default 'qr' check (origen in ('qr','manual')),
  unique (usuario_id, fecha)
);

create table permisos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas on delete cascade,
  usuario_id uuid not null references usuarios on delete cascade,
  tipo text not null check (tipo in ('Día completo','Medio día','Licencia médica','Permiso administrativo')),
  desde date not null,
  hasta date not null,
  nota text,
  estado text not null default 'Pendiente' check (estado in ('Pendiente','Aprobado','Rechazado'))
);

create table produccion (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas on delete cascade,
  proceso_id uuid not null references procesos on delete cascade,
  usuario_id uuid not null references usuarios on delete cascade,
  fecha date not null default current_date,
  unidades int not null check (unidades >= 0)
);

create index on procesos (empresa_id);
create index on usuarios (empresa_id, proceso_id);
create index on usuarios (rut);
create index on asistencias (empresa_id, fecha);
create index on asistencias (usuario_id, fecha);
create index on permisos (empresa_id, desde, hasta);
create index on produccion (proceso_id, fecha);

-- Helpers (security definer evita recursión en RLS)
create or replace function mi_rol() returns text language sql stable security definer set search_path=public
as $$ select rol from usuarios where auth_id = auth.uid() $$;
create or replace function mi_empresa() returns uuid language sql stable security definer set search_path=public
as $$ select empresa_id from usuarios where auth_id = auth.uid() $$;
create or replace function mi_proceso() returns uuid language sql stable security definer set search_path=public
as $$ select proceso_id from usuarios where auth_id = auth.uid() $$;
create or replace function empresa_activa(e uuid) returns boolean language sql stable security definer set search_path=public
as $$ select exists (select 1 from empresas where id = e and estado = 'Activa') $$;

alter table empresas enable row level security;
alter table procesos enable row level security;
alter table usuarios enable row level security;
alter table asistencias enable row level security;
alter table permisos enable row level security;
alter table produccion enable row level security;

-- Empresas: súper admin todo; el resto solo lee la suya (para ver estado y mensaje)
create policy emp_super on empresas for all using (mi_rol()='super_admin') with check (mi_rol()='super_admin');
create policy emp_lee on empresas for select using (id = mi_empresa());
create policy emp_admin_upd on empresas for update using (id = mi_empresa() and mi_rol()='admin') with check (id = mi_empresa());

-- Procesos
create policy proc_super on procesos for all using (mi_rol()='super_admin');
create policy proc_lee on procesos for select using (empresa_id = mi_empresa());
create policy proc_admin on procesos for all using (empresa_id = mi_empresa() and mi_rol()='admin' and empresa_activa(empresa_id))
  with check (empresa_id = mi_empresa());

-- Usuarios
create policy usr_super on usuarios for all using (mi_rol()='super_admin');
create policy usr_yo on usuarios for select using (auth_id = auth.uid());
create policy usr_admin on usuarios for all using (empresa_id = mi_empresa() and mi_rol()='admin' and empresa_activa(empresa_id))
  with check (empresa_id = mi_empresa());
create policy usr_sup on usuarios for select using (mi_rol()='supervisor' and empresa_id = mi_empresa() and proceso_id = mi_proceso());

-- Asistencias: supervisor inserta/lee solo su proceso y solo del día de hoy; sin borrar histórico
create policy asi_super on asistencias for select using (mi_rol()='super_admin');
create policy asi_admin on asistencias for all using (empresa_id = mi_empresa() and mi_rol()='admin' and empresa_activa(empresa_id))
  with check (empresa_id = mi_empresa());
create policy asi_sup_sel on asistencias for select using (mi_rol()='supervisor' and empresa_id = mi_empresa() and proceso_id = mi_proceso());
create policy asi_sup_ins on asistencias for insert with check (mi_rol()='supervisor' and empresa_id = mi_empresa() and proceso_id = mi_proceso() and fecha = current_date and empresa_activa(empresa_id));
create policy asi_sup_upd on asistencias for update using (mi_rol()='supervisor' and empresa_id = mi_empresa() and proceso_id = mi_proceso() and fecha = current_date);
create policy asi_trab on asistencias for select using (usuario_id in (select id from usuarios where auth_id = auth.uid()));

-- Producción (misma lógica que asistencias)
create policy pro_admin on produccion for all using (empresa_id = mi_empresa() and mi_rol()='admin' and empresa_activa(empresa_id))
  with check (empresa_id = mi_empresa());
create policy pro_sup_sel on produccion for select using (mi_rol()='supervisor' and empresa_id = mi_empresa() and proceso_id = mi_proceso());
create policy pro_sup_ins on produccion for insert with check (mi_rol()='supervisor' and empresa_id = mi_empresa() and proceso_id = mi_proceso() and fecha = current_date and empresa_activa(empresa_id));
create policy pro_trab on produccion for select using (usuario_id in (select id from usuarios where auth_id = auth.uid()));

-- Permisos
create policy per_admin on permisos for all using (empresa_id = mi_empresa() and mi_rol()='admin') with check (empresa_id = mi_empresa());
create policy per_sup on permisos for select using (mi_rol()='supervisor' and estado='Aprobado' and usuario_id in (select id from usuarios where proceso_id = mi_proceso()));
create policy per_trab_sel on permisos for select using (usuario_id in (select id from usuarios where auth_id = auth.uid()));
create policy per_trab_ins on permisos for insert with check (estado='Pendiente' and usuario_id in (select id from usuarios where auth_id = auth.uid()));
