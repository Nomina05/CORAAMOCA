-- Fase 10: integración de reclutamiento, desempeño y capacitación.
-- Conserva posibles registros previos y desvincula únicamente las referencias duplicadas.
with ranked as(
 select id,row_number() over(partition by performance_evaluation_id order by created_at,id) position
 from public.hr_training_needs where performance_evaluation_id is not null
)
update public.hr_training_needs n set performance_evaluation_id=null,updated_at=now()
from ranked r where n.id=r.id and r.position>1;
create unique index if not exists hr_training_need_performance_uidx on public.hr_training_needs(performance_evaluation_id) where performance_evaluation_id is not null;

create or replace function public.hr_sync_performance_training_need() returns trigger language plpgsql security definer set search_path=public,extensions as $$
declare v_year integer;v_employee public.hr_employees;
begin
 if new.status not in('VALIDADA','CERRADA') or not new.recommend_training then return new;end if;
 select cycle_year into v_year from public.hr_performance_cycles where id=new.cycle_id;
 select * into v_employee from public.hr_employees where id=new.employee_id;
 insert into public.hr_training_needs(need_year,employee_id,direction_name,department_name,source,performance_evaluation_id,topic,description,priority,status,detected_by)
 values(v_year,new.employee_id,coalesce(v_employee.direction_name,''),coalesce(v_employee.department_name,''),'DESEMPENO',new.id,'Necesidad derivada de evaluación del desempeño','Generada automáticamente al validar la evaluación. Calificación final: '||coalesce(new.final_score,0)::text||' ('||coalesce(new.final_rating,'SIN CALIFICAR')||').',case when coalesce(new.final_score,0)<60 then 'CRITICA' when coalesce(new.final_score,0)<70 then 'ALTA' else 'MEDIA' end,'DETECTADA',coalesce(new.validated_by,new.evaluated_by,new.created_by))
 on conflict(performance_evaluation_id) where performance_evaluation_id is not null do update set need_year=excluded.need_year,employee_id=excluded.employee_id,direction_name=excluded.direction_name,department_name=excluded.department_name,description=excluded.description,priority=excluded.priority,updated_at=now();
 return new;
end $$;
drop trigger if exists hr_performance_training_need_trg on public.hr_performance_evaluations;
create trigger hr_performance_training_need_trg after insert or update of status,recommend_training,final_score,final_rating on public.hr_performance_evaluations for each row execute function public.hr_sync_performance_training_need();

insert into public.hr_training_needs(need_year,employee_id,direction_name,department_name,source,performance_evaluation_id,topic,description,priority,status,detected_by)
select cy.cycle_year,ev.employee_id,coalesce(e.direction_name,''),coalesce(e.department_name,''),'DESEMPENO',ev.id,'Necesidad derivada de evaluación del desempeño','Generada automáticamente al validar la evaluación. Calificación final: '||coalesce(ev.final_score,0)::text||' ('||coalesce(ev.final_rating,'SIN CALIFICAR')||').',case when coalesce(ev.final_score,0)<60 then 'CRITICA' when coalesce(ev.final_score,0)<70 then 'ALTA' else 'MEDIA' end,'DETECTADA',coalesce(ev.validated_by,ev.evaluated_by,ev.created_by)
from public.hr_performance_evaluations ev join public.hr_performance_cycles cy on cy.id=ev.cycle_id join public.hr_employees e on e.id=ev.employee_id
where ev.status in('VALIDADA','CERRADA') and ev.recommend_training
on conflict(performance_evaluation_id) where performance_evaluation_id is not null do nothing;

create or replace function public.list_hr_talent_cycle(p_token text,p_year integer) returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;
begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or(v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'ver_recursos_humanos')::boolean,false))then return jsonb_build_object('success',false,'error','No posee permiso para consultar el ciclo de talento.');end if;
 return jsonb_build_object('success',true,
 'recruitment',jsonb_build_object('requests',(select count(*) from public.hr_recruitment_processes where extract(year from request_date)=p_year),'approved',(select count(*) from public.hr_recruitment_processes where extract(year from request_date)=p_year and request_status='APROBADA'),'candidates',(select count(*) from public.hr_recruitment_candidates where extract(year from application_date)=p_year),'appointed',(select count(*) from public.hr_recruitment_candidates where extract(year from application_date)=p_year and current_status='NOMBRADO')),
 'performance',jsonb_build_object('evaluations',(select count(*) from public.hr_performance_evaluations ev join public.hr_performance_cycles cy on cy.id=ev.cycle_id where cy.cycle_year=p_year),'validated',(select count(*) from public.hr_performance_evaluations ev join public.hr_performance_cycles cy on cy.id=ev.cycle_id where cy.cycle_year=p_year and ev.status in('VALIDADA','CERRADA')),'average_score',(select coalesce(round(avg(ev.final_score),2),0) from public.hr_performance_evaluations ev join public.hr_performance_cycles cy on cy.id=ev.cycle_id where cy.cycle_year=p_year),'improvement_plans',(select count(*) from public.hr_improvement_plans ip join public.hr_performance_evaluations ev on ev.id=ip.evaluation_id join public.hr_performance_cycles cy on cy.id=ev.cycle_id where cy.cycle_year=p_year)),
 'training',jsonb_build_object('needs',(select count(*) from public.hr_training_needs where need_year=p_year),'performance_needs',(select count(*) from public.hr_training_needs where need_year=p_year and source='DESEMPENO'),'courses',(select count(*) from public.hr_training_courses c join public.hr_training_plans p on p.id=c.plan_id where p.plan_year=p_year),'completed_courses',(select count(*) from public.hr_training_courses c join public.hr_training_plans p on p.id=c.plan_id where p.plan_year=p_year and c.status='FINALIZADO'),'participants',(select count(*) from public.hr_training_participants t join public.hr_training_courses c on c.id=t.course_id join public.hr_training_plans p on p.id=c.plan_id where p.plan_year=p_year)));
end $$;
grant execute on function public.list_hr_talent_cycle(text,integer) to anon,authenticated;
