-- DONG HUI FIELD KPI | Chạy trong Supabase > SQL Editor (một lần)
-- Phân quyền enforced ở DB (Row Level Security), không phụ thuộc giao diện.
create extension if not exists pgcrypto;

create table if not exists public.projects (
 id uuid primary key default gen_random_uuid(), code text not null unique,
 name text not null, active boolean not null default true,
 created_at timestamptz not null default now()
);
create table if not exists public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 email text, display_name text,
 role text not null default 'engineer' check(role in ('engineer','commander','director','admin')),
 project_id uuid references public.projects(id),
 created_at timestamptz not null default now()
);
create table if not exists public.daily_reports (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id),
 project_id uuid not null references public.projects(id),
 report_date date not null,
 manpower jsonb not null default '{}'::jsonb,
 checklist jsonb not null default '{}'::jsonb,
 equipment text not null default '', manpower_notes text not null default '',
 materials text not null default '', work_areas text not null default '',
 plan text not null default '', morning_risks text not null default '',
 completed text not null default '', delay_reasons text not null default '',
 acceptance text not null default '', tomorrow text not null default '',
 updated_at timestamptz not null default now(),
 unique(user_id,report_date)
);
create table if not exists public.quality_issues (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id),
 project_id uuid not null references public.projects(id),
 location text not null, contractor text not null default '',description text not null,
 severity text not null default 'normal' check (severity in ('normal','major','critical')),
 due_date date not null,status text not null default 'open' check (status in ('open','working','closed')),
 resolution text not null default '', photo_path text,
 created_at timestamptz not null default now()
);
create table if not exists public.evaluations (
 id uuid primary key default gen_random_uuid(),
 engineer_id uuid not null references public.profiles(id),
 project_id uuid not null references public.projects(id),
 reviewed_by uuid not null references public.profiles(id),
 review_date date not null, scores jsonb not null default '{}'::jsonb,
 violation text not null default 'none' check(violation in ('none','pending','confirmed')),
 notes text not null default '',updated_at timestamptz not null default now(),
 unique(engineer_id,review_date)
);

-- Hàm phân quyền SECURITY DEFINER để tránh vòng lặp khi RLS đọc bảng profiles.
create or replace function public.my_role() returns text language sql stable security definer set search_path = public as $$
 select role from public.profiles where id = (select auth.uid()) limit 1;
$$;
create or replace function public.my_project() returns uuid language sql stable security definer set search_path = public as $$
 select project_id from public.profiles where id = (select auth.uid()) limit 1;
$$;
create or replace function public.can_manage_project(p uuid) returns boolean language sql stable security definer set search_path = public as $$
 select coalesce(public.my_role() in ('admin','director') or (public.my_role()='commander' and public.my_project()=p),false);
$$;
create or replace function public.can_read_project(p uuid) returns boolean language sql stable security definer set search_path = public as $$
 select coalesce(public.can_manage_project(p) or public.my_project()=p,false);
$$;
revoke all on function public.my_role() from public;
revoke all on function public.my_project() from public;
revoke all on function public.can_manage_project(uuid) from public;
revoke all on function public.can_read_project(uuid) from public;
grant execute on function public.my_role(),public.my_project(),public.can_manage_project(uuid),public.can_read_project(uuid) to authenticated;

create or replace function public.new_user_profile() returns trigger language plpgsql security definer set search_path=public as $$
begin
 insert into public.profiles (id,email,display_name,role)
 values(new.id,new.email,coalesce(new.raw_user_meta_data->>'display_name',split_part(new.email,'@',1)),'engineer')
 on conflict (id) do nothing;
 return new;
end;
$$;
drop trigger if exists auth_user_profile_created on auth.users;
create trigger auth_user_profile_created after insert on auth.users for each row execute function public.new_user_profile();

alter table public.projects enable row level security;
alter table public.profiles enable row level security;
alter table public.daily_reports enable row level security;
alter table public.quality_issues enable row level security;
alter table public.evaluations enable row level security;

drop policy if exists projects_read on public.projects;
create policy projects_read on public.projects for select to authenticated using (true);
drop policy if exists projects_insert on public.projects;
create policy projects_insert on public.projects for insert to authenticated with check (public.my_role()='admin');
drop policy if exists projects_update on public.projects;
create policy projects_update on public.projects for update to authenticated using(public.my_role()='admin') with check(public.my_role()='admin');

drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated using (id=auth.uid() or public.my_role() in ('director','admin') or (public.my_role()='commander' and project_id=public.my_project()));
drop policy if exists profiles_admin_update on public.profiles;
create policy profiles_admin_update on public.profiles for update to authenticated using (public.my_role()='admin') with check (public.my_role()='admin');

drop policy if exists reports_read on public.daily_reports;
create policy reports_read on public.daily_reports for select to authenticated using (user_id=auth.uid() or public.can_manage_project(project_id));
drop policy if exists reports_create on public.daily_reports;
create policy reports_create on public.daily_reports for insert to authenticated with check (user_id=auth.uid() and project_id=public.my_project());
drop policy if exists reports_modify on public.daily_reports;
create policy reports_modify on public.daily_reports for update to authenticated using (user_id=auth.uid() and project_id=public.my_project()) with check (user_id=auth.uid() and project_id=public.my_project());

drop policy if exists issues_read on public.quality_issues;
create policy issues_read on public.quality_issues for select to authenticated using (user_id=auth.uid() or public.can_manage_project(project_id));
drop policy if exists issues_create on public.quality_issues;
create policy issues_create on public.quality_issues for insert to authenticated with check (user_id=auth.uid() and project_id=public.my_project());
drop policy if exists issues_modify on public.quality_issues;
create policy issues_modify on public.quality_issues for update to authenticated using (user_id=auth.uid() or public.can_manage_project(project_id)) with check (user_id=auth.uid() or public.can_manage_project(project_id));

-- Ràng buộc: kỹ sư không được tự xác nhận đóng lỗi.
create or replace function public.guard_issue_update() returns trigger language plpgsql security definer set search_path=public as $$
begin
 if tg_op='UPDATE' then
  if old.user_id is distinct from new.user_id or old.project_id is distinct from new.project_id then
   raise exception 'Không được thay đổi người tạo hoặc công trình của lỗi';
  end if;
  if new.status='closed' and old.status is distinct from new.status and not public.can_manage_project(new.project_id) then
   raise exception 'Chỉ chỉ huy trưởng hoặc giám đốc hạng mục được xác nhận đóng lỗi';
  end if;
 else
  if new.status='closed' and not public.can_manage_project(new.project_id) then
   raise exception 'Chỉ quản lý được xác nhận đóng lỗi';
  end if;
 end if;
 return new;
end;
$$;
drop trigger if exists quality_issues_guard on public.quality_issues;
create trigger quality_issues_guard before insert or update on public.quality_issues for each row execute function public.guard_issue_update();

drop policy if exists evals_read on public.evaluations;
create policy evals_read on public.evaluations for select to authenticated using (engineer_id=auth.uid() or public.can_manage_project(project_id));
drop policy if exists evals_create on public.evaluations;
create policy evals_create on public.evaluations for insert to authenticated with check (public.can_manage_project(project_id) and reviewed_by=auth.uid());
drop policy if exists evals_modify on public.evaluations;
create policy evals_modify on public.evaluations for update to authenticated using (public.can_manage_project(project_id)) with check (public.can_manage_project(project_id) and reviewed_by=auth.uid());

-- Chặn chấm sai công trình / tự chấm; chặn dữ liệu điểm vượt thang.
create or replace function public.guard_evaluation() returns trigger language plpgsql security definer set search_path=public as $$
declare v_role text; v_project uuid; i int; maxes int[] := array[4,3,3,3,2,10,4,4,4,3,6,5,4,6,4,5,4,3,3,4,4,2,4,3,3]; value_text text;
begin
 select role,project_id into v_role,v_project from public.profiles where id=new.engineer_id;
 if v_role is distinct from 'engineer' or v_project is distinct from new.project_id then
  raise exception 'Kỹ sư hoặc công trình đánh giá không hợp lệ';
 end if;
 if new.engineer_id = new.reviewed_by then raise exception 'Không được tự đánh giá'; end if;
 if jsonb_typeof(new.scores) <> 'object' then raise exception 'Bảng điểm không hợp lệ'; end if;
 for i in 0..24 loop
  value_text:=new.scores->>i::text;
  if value_text is null or value_text !~ '^[0-9]+$' or value_text::int>maxes[i+1] then
   raise exception 'Điểm không hợp lệ tại tiêu chí %',i;
  end if;
 end loop;
 if tg_op='UPDATE' and (old.engineer_id<>new.engineer_id or old.project_id<>new.project_id or old.review_date<>new.review_date) then
  raise exception 'Không được thay đổi đối tượng hoặc ngày đánh giá';
 end if;
 return new;
end;
$$;
drop trigger if exists evaluation_guard on public.evaluations;
create trigger evaluation_guard before insert or update on public.evaluations for each row execute function public.guard_evaluation();

-- Kho ảnh riêng tư. Kỹ sư chỉ được tải ảnh vào đường dẫn riêng.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('field-photos','field-photos',false,8388608,array['image/jpeg','image/png','image/webp','image/heic'])
on conflict (id) do nothing;
drop policy if exists dh_photo_upload on storage.objects;
create policy dh_photo_upload on storage.objects for insert to authenticated
with check(bucket_id='field-photos' and split_part(name,'/',1)=auth.uid()::text);
drop policy if exists dh_photo_read on storage.objects;
create policy dh_photo_read on storage.objects for select to authenticated
using (bucket_id='field-photos' and (split_part(name,'/',1)=auth.uid()::text or exists (
 select 1 from public.quality_issues qi where qi.photo_path=storage.objects.name and public.can_manage_project(qi.project_id)
)));

-- SAU KHI ĐĂNG KÝ TÀI KHOẢN ĐẦU TIÊN, CHỈ CHẠY LỆNH NÀY TRONG SQL EDITOR:
-- update public.profiles set role='admin' where email='email-quan-tri-cua-ban@congty.com';
-- Không đưa service_role key vào config.js hoặc GitHub.
