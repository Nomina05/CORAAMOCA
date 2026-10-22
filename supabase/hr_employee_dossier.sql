-- Expediente único del colaborador. Consolida los módulos existentes sin duplicar información.
alter table public.hr_employee_files add column if not exists document_date date;
alter table public.hr_employee_files add column if not exists description text not null default '';

create index if not exists hr_employee_files_employee_idx
on public.hr_employee_files(employee_id,created_at desc);

create or replace function public.get_hr_employee_dossier(p_token text,p_employee_id uuid)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_employee public.hr_employees;
begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null then return jsonb_build_object('success',false,'error','Sesión inválida o vencida.');end if;
 select * into v_employee from public.hr_employees where id=p_employee_id;
 if v_employee.id is null then return jsonb_build_object('success',false,'error','Empleado no encontrado.');end if;
 if v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'ver_recursos_humanos')::boolean,false) then
  return jsonb_build_object('success',false,'error','No posee permiso para consultar expedientes de colaboradores.');
 end if;
 if v_user.role<>'Administrador' and not public.hr_employee_in_user_scope(v_user,v_employee) then
  return jsonb_build_object('success',false,'error','El colaborador no pertenece a la unidad organizacional autorizada.');
 end if;
 return jsonb_build_object(
  'success',true,
  'employee',to_jsonb(v_employee),
  'history',coalesce((select jsonb_agg(to_jsonb(h) order by h.effective_year desc,h.effective_month desc,h.created_at desc) from public.hr_employee_history h where h.employee_id=p_employee_id),'[]'::jsonb),
  'actions',coalesce((select jsonb_agg(to_jsonb(a) order by a.effective_date desc,a.created_at desc) from public.hr_personnel_actions a where a.employee_id=p_employee_id),'[]'::jsonb),
  'cases',coalesce((select jsonb_agg(to_jsonb(c) order by c.request_date desc,c.created_at desc) from public.hr_employee_cases c where c.employee_id=p_employee_id),'[]'::jsonb),
  'payroll',coalesce((select jsonb_agg(to_jsonb(x) order by x.payroll_year desc,x.payroll_month desc,x.created_at desc) from(
    select l.*,b.payroll_type,b.payroll_year,b.payroll_month,b.status batch_status,b.created_at
    from public.hr_payroll_batch_lines l join public.hr_payroll_batches b on b.id=l.batch_id where l.employee_id=p_employee_id
  )x),'[]'::jsonb),
  'assignments',coalesce((select jsonb_agg(to_jsonb(a) order by a.active desc,a.payroll_type) from public.hr_employee_payroll_assignments a where a.employee_id=p_employee_id),'[]'::jsonb),
  'benefits',coalesce((select jsonb_agg(to_jsonb(b) order by b.active desc,b.benefit_type) from public.hr_employee_benefits b where b.employee_id=p_employee_id),'[]'::jsonb),
  'dependents',coalesce((select jsonb_agg(to_jsonb(d) order by d.active desc,d.full_name) from public.hr_employee_dependents d where d.employee_id=p_employee_id),'[]'::jsonb),
  'deductions',coalesce((select jsonb_agg(to_jsonb(d) order by d.active desc,d.deduction_type) from public.hr_employee_deductions d where d.employee_id=p_employee_id),'[]'::jsonb),
  'documents',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from(
    select f.*,coalesce(u.full_name,'Sistema') uploaded_by_name from public.hr_employee_files f left join public.app_users u on u.id=f.uploaded_by where f.employee_id=p_employee_id
  )x),'[]'::jsonb),
  'audit',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from(
    select a.id,a.action,a.module,a.detail,a.created_at,coalesce(u.full_name,'Sistema') actor_name
    from public.security_audit_log a left join public.app_users u on u.id=a.actor_user_id
    where a.module='Recursos Humanos' and (a.detail->>'employee_id'=p_employee_id::text or a.detail->>'target_employee_id'=p_employee_id::text)
    order by a.created_at desc limit 200
  )x),'[]'::jsonb)
 );
end $$;

create or replace function public.add_hr_employee_document(p_token text,p_employee_id uuid,p_document_type text,p_document_name text,p_document_url text,p_description text default '',p_document_date date default null)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_employee public.hr_employees;v_id uuid;
begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null then return jsonb_build_object('success',false,'error','Sesión inválida o vencida.');end if;
 if v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'editar_recursos_humanos')::boolean,false) then
  return jsonb_build_object('success',false,'error','No posee permiso para agregar documentos al expediente.');
 end if;
 select * into v_employee from public.hr_employees where id=p_employee_id;
 if v_employee.id is null then return jsonb_build_object('success',false,'error','Empleado no encontrado.');end if;
 if v_user.role<>'Administrador' and not public.hr_employee_in_user_scope(v_user,v_employee) then
  return jsonb_build_object('success',false,'error','El colaborador no pertenece a la unidad organizacional autorizada.');
 end if;
 if nullif(trim(coalesce(p_document_type,'')),'') is null or nullif(trim(coalesce(p_document_name,'')),'') is null or coalesce(p_document_url,'') !~* '^https?://' then
  return jsonb_build_object('success',false,'error','Indique tipo, nombre y un enlace válido que inicie con http:// o https://.');
 end if;
 insert into public.hr_employee_files(employee_id,document_type,document_name,document_url,description,document_date,uploaded_by)
 values(p_employee_id,trim(p_document_type),trim(p_document_name),trim(p_document_url),coalesce(trim(p_description),''),p_document_date,v_user.id) returning id into v_id;
 insert into public.security_audit_log(actor_user_id,action,module,detail)
 values(v_user.id,'AGREGAR_DOCUMENTO_EMPLEADO','Recursos Humanos',jsonb_build_object('employee_id',p_employee_id,'document_id',v_id,'document_type',trim(p_document_type),'document_name',trim(p_document_name)));
 return jsonb_build_object('success',true,'id',v_id);
end $$;

revoke all on function public.get_hr_employee_dossier(text,uuid),public.add_hr_employee_document(text,uuid,text,text,text,text,date) from public;
grant execute on function public.get_hr_employee_dossier(text,uuid),public.add_hr_employee_document(text,uuid,text,text,text,text,date) to anon,authenticated;
