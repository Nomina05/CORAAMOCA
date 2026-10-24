-- Fase 8: fuente consolidada para reportes oficiales de Recursos Humanos.
create or replace function public.list_hr_official_reports(p_token text,p_year integer,p_month integer)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;
begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'ver_recursos_humanos')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para consultar reportes oficiales de Recursos Humanos.');end if;
 return jsonb_build_object('success',true,'year',p_year,'month',p_month,
 'payroll',coalesce((select jsonb_agg(to_jsonb(x) order by x.payroll_type,x.program,x.activity,x.employee_name) from(
  select b.payroll_type,b.status,b.execution_fund,l.program,l.subproduct,l.activity,l.account_code,l.employee_code,l.document_number,l.employee_name,l.position_name,l.gross_salary,l.isr,l.insurance,l.employee_pension,l.employee_sfs,l.employer_pension,l.employer_sfs,l.employer_labor_risk,l.other_deductions,l.total_deductions,l.net_amount
  from public.hr_payroll_batches b join public.hr_payroll_batch_lines l on l.batch_id=b.id where b.payroll_year=p_year and b.payroll_month=p_month)x),'[]'::jsonb),
 'cases',coalesce((select jsonb_agg(to_jsonb(x) order by x.case_type,x.request_date,x.full_name) from(
  select c.module_number,c.case_type,c.request_date,c.category,c.start_date,c.end_date,c.day_count,c.paid,c.severity,c.reason,c.status,e.employee_code,e.full_name,e.position_name,e.direction_name,e.department_name
  from public.hr_employee_cases c join public.hr_employees e on e.id=c.employee_id where extract(year from c.request_date)=p_year and extract(month from c.request_date)=p_month and (v_user.role='Administrador' or public.hr_employee_in_user_scope(v_user,e)))x),'[]'::jsonb),
 'movements',coalesce((select jsonb_agg(to_jsonb(x) order by x.effective_date,x.full_name) from(
  select a.action_number,a.effective_date,a.action_type,a.status,a.observations,e.employee_code,e.full_name,e.position_name,e.direction_name,e.department_name
  from public.hr_personnel_actions a join public.hr_employees e on e.id=a.employee_id where extract(year from a.effective_date)=p_year and extract(month from a.effective_date)=p_month and (v_user.role='Administrador' or public.hr_employee_in_user_scope(v_user,e)))x),'[]'::jsonb),
 'vacancies',coalesce((select jsonb_agg(to_jsonb(x) order by x.direction_name,x.position_name) from(
  select v.position_name,v.direction_name,v.department_name,v.execution_fund,v.program,v.subproduct,v.activity,v.monthly_amount,v.available_from,v.status from public.hr_vacancies v where v.status in('VACANTE','CON_RECLUTAMIENTO','CONGELADA'))x),'[]'::jsonb),
 'budget',coalesce((select jsonb_agg(to_jsonb(x) order by x.execution_fund,x.program,x.subproduct,x.activity) from(
  with p as(select execution_fund,program,subproduct,activity,sum(monthly_amount) programmed from public.hr_payroll_budget_lines where budget_year=p_year and active group by execution_fund,program,subproduct,activity),e as(select l.execution_fund,l.program,l.subproduct,l.activity,sum(l.gross_salary) executed from public.hr_payroll_batch_lines l join public.hr_payroll_batches b on b.id=l.batch_id where b.payroll_year=p_year and b.payroll_month=p_month group by l.execution_fund,l.program,l.subproduct,l.activity)
  select coalesce(p.execution_fund,e.execution_fund) execution_fund,coalesce(p.program,e.program) program,coalesce(p.subproduct,e.subproduct) subproduct,coalesce(p.activity,e.activity) activity,coalesce(p.programmed,0) programmed,coalesce(e.executed,0) executed,coalesce(p.programmed,0)-coalesce(e.executed,0) available from p full join e using(execution_fund,program,subproduct,activity))x),'[]'::jsonb));
end $$;
grant execute on function public.list_hr_official_reports(text,integer,integer) to anon,authenticated;
