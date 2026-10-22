import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {nextMeasurementStatus,paidTotal,paymentWithinAppropriation,permissionGranted} from "../app/lib/business-rules.mjs";

test("un usuario sin permiso no puede editar proyectos",()=>{
  assert.equal(permissionGranted("Usuario",{editar_proyectos_tecnicos:false},"editar_proyectos_tecnicos"),false);
  assert.equal(permissionGranted("Administrador",{},"editar_proyectos_tecnicos"),true);
});

test("los permisos de Gestión Humana se asignan de forma independiente",()=>{
  const permissions={ver_permisos_laborales:true,registrar_permisos_laborales:false,ver_amonestaciones:false,ver_vacaciones:true,aprobar_vacaciones:false};
  assert.equal(permissionGranted("Usuario",permissions,"ver_permisos_laborales"),true);
  assert.equal(permissionGranted("Usuario",permissions,"registrar_permisos_laborales"),false);
  assert.equal(permissionGranted("Usuario",permissions,"ver_amonestaciones"),false);
  assert.equal(permissionGranted("Usuario",permissions,"ver_vacaciones"),true);
  assert.equal(permissionGranted("Usuario",permissions,"aprobar_vacaciones"),false);
  assert.equal(permissionGranted("Administrador",{},"aprobar_vacaciones"),true);
});

test("permisos, vacaciones y amonestaciones poseen secuencias independientes",async()=>{
  const sql=await readFile(new URL("../supabase/hr_employee_cases.sql",import.meta.url),"utf8");
  const component=await readFile(new URL("../app/components/EmployeeCases.tsx",import.meta.url),"utf8");
  assert.equal(sql.includes("partition by case_type"),true);
  assert.equal(sql.includes("hr_employee_cases_type_number_uidx"),true);
  assert.equal(sql.includes("pg_advisory_xact_lock"),true);
  assert.equal(component.includes("item.module_number||item.case_number"),true);
  assert.equal(component.includes('useState<string>("ALL")'),true);
});

test("los indicadores de novedades respetan alcance y criterios de seguimiento",async()=>{
  const sql=await readFile(new URL("../supabase/hr_employee_cases.sql",import.meta.url),"utf8");
  const component=await readFile(new URL("../app/components/HrCaseAnalytics.tsx",import.meta.url),"utf8");
  assert.equal(sql.includes("get_hr_case_analytics"),true);
  assert.equal(sql.includes("hr_employee_in_user_scope(v_user,e)"),true);
  assert.equal(sql.includes("consecutive_licenses"),true);
  assert.equal(sql.includes("Revisión disciplinaria y plan de mejora documentado"),true);
  assert.equal(component.includes("Las alertas no sustituyen la investigación"),true);
  assert.equal(component.includes("Revisar registros →"),true);
  const page=await readFile(new URL("../app/page.tsx",import.meta.url),"utf8");
  assert.equal(page.includes('section === "Vacantes por Área" || section === "Indicadores RRHH"'),true);
});

test("el flujo de cubicaciones no permite saltar etapas",()=>{
  assert.equal(nextMeasurementStatus("Cubicada"),"Revisada");
  assert.equal(nextMeasurementStatus("Revisada"),"Libramiento");
  assert.equal(nextMeasurementStatus("Libramiento"),"Pagada");
  assert.equal(nextMeasurementStatus("Cubicada","RETURN"),null);
});

test("solo las cubicaciones pagadas afectan el total pagado",()=>{
  assert.equal(paidTotal({fixedAssetPaid:100,advancePaid:200,measurements:[
    {status:"Cubicada",amount:900},{status:"Libramiento",amount:800},{status:"Pagada",amount:300},
  ]}),600);
});

test("el resumen de obras solo incluye avances iniciales pagados",async()=>{
  const sql=await readFile(new URL("../supabase/institutional_reports.sql",import.meta.url),"utf8");
  assert.equal(sql.includes("sum(p.advance_20_amount) filter(where lower(trim(coalesce(p.advance_status,''))) in ('pagada','pago'))"),true);
  assert.equal(sql.includes("sum(m.net_paid_amount)"),true);
  assert.equal(sql.includes("lower(trim(m.status)) in ('pagada','pago')"),true);
});

test("las cubicaciones pagadas aplican una retención del 25 por ciento",async()=>{
  const sql=await readFile(new URL("../supabase/measurement_retention.sql",import.meta.url),"utf8");
  assert.equal(sql.includes("round(amount*0.25,2)"),true);
  assert.equal(sql.includes("amount-round(amount*0.25,2)"),true);
  assert.equal(sql.includes("sum(net_paid_amount)"),true);
});

test("un pago no puede exceder la apropiación disponible",()=>{
  assert.equal(paymentWithinAppropriation(1000,999),true);
  assert.equal(paymentWithinAppropriation(1000,1001),false);
});

test("la programación mensual de nómina 2026 respeta los topes por fondo",()=>{
  const fund30=[857250,4336105,20000,30000,1913989,455000,632550,108000,202000,363663.73,10000,150000,326750,245000,650000,119035,40000];
  const fund10=[3378618.60];
  const total30=fund30.reduce((sum,value)=>sum+value,0);
  const total10=fund10.reduce((sum,value)=>sum+value,0);
  assert.equal(Number(total30.toFixed(2)),10459342.73);
  assert.equal(Number(total10.toFixed(2)),3378618.60);
  assert.equal(Number((total30+total10).toFixed(2)),13837961.33);
  assert.equal(total30<=11150504.77,true);
  assert.equal(total10<=3993167.00,true);
});

test("los módulos no utilizan almacenamiento local para datos institucionales",async()=>{
  const page=await readFile(new URL("../app/page.tsx",import.meta.url),"utf8");
  assert.equal(page.includes("localStorage"),false);
  assert.equal(page.includes("sessionStorage"),false);
  assert.equal(page.includes("/api/projects/institutional"),true);
});

test("el autorregistro público está deshabilitado",async()=>{
  const route=await readFile(new URL("../app/api/auth/register/route.ts",import.meta.url),"utf8");
  const security=await readFile(new URL("../supabase/security_permissions_audit.sql",import.meta.url),"utf8");
  assert.equal(route.includes('status:403'),true);
  assert.equal(route.includes('rpc("register_app_user"'),false);
  assert.equal(security.includes("revoke all on function public.register_app_user(text,text,text,text) from public,anon,authenticated"),true);
});

test("el estado técnico exige una sesión válida",async()=>{
  const route=await readFile(new URL("../app/api/system/status/route.ts",import.meta.url),"utf8");
  assert.equal(route.includes("sessionCookie"),true);
  assert.equal(route.includes('rpc("get_app_session"'),true);
  assert.equal(route.includes('status:401'),true);
});

test("la migración automática incluye las tablas base y módulos dependientes",async()=>{
  const workflow=await readFile(new URL("../.github/workflows/supabase-migrate.yml",import.meta.url),"utf8");
  for(const migration of ["username_auth.sql","technical_projects.sql","cubicaciones_workflow.sql","project_digital_file.sql","personal_dashboard.sql"]){
    assert.equal(workflow.includes(migration),true);
  }
});

test("el tablero institucional utiliza proyectos, empleados y presupuesto de Supabase",async()=>{
  const page=await readFile(new URL("../app/page.tsx",import.meta.url),"utf8");
  assert.equal(page.includes("portfolioProjects"),true);
  assert.equal(page.includes("activeEmployees"),true);
  assert.equal(page.includes("financialProgress"),true);
  assert.equal(page.includes("No existen iniciativas ni proyectos técnicos disponibles para este filtro."),true);
  assert.equal(page.includes("<strong>78.4</strong>"),false);
  assert.equal(page.includes('metric: "428"'),false);
  assert.equal(page.includes("Julio 2026"),false);
  assert.equal(page.includes("4.1% vs. junio"),false);
  assert.equal(page.includes("DATOS DE SUPABASE"),true);
});

test("la acción de personal se imprime en tamaño carta",async()=>{
  const component=await readFile(new URL("../app/components/PersonnelAction.tsx",import.meta.url),"utf8");
  assert.equal(component.includes("@page{size:letter portrait;margin:0}"),true);
  assert.equal(component.includes("width:8.5in!important;height:11in!important"),true);
  assert.equal(component.includes(".action-approvals{height:190px!important;min-height:190px!important"),true);
});

test("cada exportación PDF utiliza un modo de impresión independiente",async()=>{
  const page=await readFile(new URL("../app/page.tsx",import.meta.url),"utf8");
  const component=await readFile(new URL("../app/components/PersonnelAction.tsx",import.meta.url),"utf8");
  const css=await readFile(new URL("../app/globals.css",import.meta.url),"utf8");
  assert.equal(page.includes('printActiveView("printing-report")'),true);
  assert.equal(page.includes('printActiveView("printing-dashboard")'),true);
  assert.equal(component.includes("printing-personnel-action"),true);
  assert.equal(css.includes("body.printing-personnel-action *{visibility:hidden!important}"),true);
  assert.equal(css.includes("body *{visibility:hidden!important}"),false);
});

test("las acciones de personal solo se modifican mientras están pendientes",async()=>{
  const sql=await readFile(new URL("../supabase/hr_personnel_actions.sql",import.meta.url),"utf8");
  const component=await readFile(new URL("../app/components/PersonnelAction.tsx",import.meta.url),"utf8");
  assert.equal(sql.includes("Solo se pueden modificar acciones pendientes de aprobación"),true);
  assert.equal(component.includes(">Modificar</button>"),true);
  assert.equal(component.includes(">Reimprimir</button>"),true);
  assert.equal(sql.includes("coalesce(nullif(p_data->>'general_director',''),v_existing.general_director)"),true);
  assert.equal(sql.includes("v_existing.approval_dates->>'director_date'"),true);
});

test("apropiaciones y adjudicaciones actualizan el proyecto y los reportes",async()=>{
  const sql=await readFile(new URL("../supabase/budget_management.sql",import.meta.url),"utf8");
  const page=await readFile(new URL("../app/page.tsx",import.meta.url),"utf8");
  assert.equal(sql.includes("'APROPIACION','ADJUDICACION'"),true);
  assert.equal(sql.includes("set appropriation_amount=appropriation_amount+v_item.amount"),true);
  assert.equal(sql.includes("set awarded_amount=awarded_amount+v_item.amount"),true);
  assert.equal(sql.includes("La adjudicación no puede superar la apropiación vigente"),true);
  assert.equal(sql.includes("applied_to_project=true"),true);
  assert.equal(page.includes("Registrar apropiación o adjudicación"),true);
  assert.equal(page.includes("await synchronizeProjectData()"),true);
  assert.equal(sql.includes("when 'Registrada' then 'Revisada' when 'Revisada' then 'Aprobada' when 'Aprobada' then 'Aplicada'"),true);
  assert.equal(page.includes("Aún no afecta el proyecto ni los reportes hasta alcanzar la etapa Aplicada"),true);
  assert.equal(page.includes('section==="Apropiaciones y Adjudicaciones"'),true);
  assert.equal(page.includes('label:"Apropiaciones y adjudicaciones",section:"Apropiaciones y Adjudicaciones"'),true);
  assert.equal(page.includes('permission:"ver_apropiaciones_adjudicaciones"'),true);
  assert.equal(page.includes('loadBudget(section==="Apropiaciones y Adjudicaciones")'),true);
  assert.equal(page.includes('allYears?"all":budgetYear'),true);
  assert.equal(page.includes("1. Seleccionar lote"),true);
  assert.equal(page.includes("2. Municipio o distrito"),true);
  assert.equal(page.includes("3. Obra correspondiente"),true);
  const css=await readFile(new URL("../app/globals.css",import.meta.url),"utf8");
  assert.equal(css.includes(".financial-movement-modal{width:min(720px,94vw);max-height:calc(100vh - 36px);overflow-y:auto"),true);
  assert.equal(page.includes('const averageWorkProgress=(items:PublicInvestmentRow[])=>items.length?sum(items,"work_progress")/items.length:0'),true);
  assert.equal(page.includes('asset?"":"PROMEDIO"'),false);
});

test("el reporte presidencial organiza obras y separa contrataciones",async()=>{
  const page=await readFile(new URL("../app/page.tsx",import.meta.url),"utf8");
  assert.equal(page.includes("RESUMEN DE INVERSIÓN PÚBLICA POR SNIP – PRESENTACIÓN PRESIDENCIAL"),true);
  assert.equal(page.includes("MONTO ADJUDICADO POR OBRA"),true);
  assert.equal(page.includes("ESTATUS DE LA OBRA"),true);
  assert.equal(page.includes("% DE LA OBRA"),true);
  assert.equal(page.includes("Gaspar Hernández"),true);
  assert.equal(page.includes('sum(items,"awarded_amount")'),true);
  assert.equal(page.includes('normalize(item.work_status||"").includes("contrat")'),true);
  assert.equal(page.includes("OBRAS SIN SNIP O EN LICITACIÓN"),true);
  assert.equal(page.includes('separate?"TIPO DE OBRA":"OBRAS"'),true);
  assert.equal(page.includes("presidential-separate-head"),true);
  assert.equal(page.includes('sum(ordered,"population")'),true);
  assert.equal(page.includes('Total de inversión: {money(sum(ordered,"budgeted_amount"))}'),true);
  assert.equal(page.includes('Total de inversión: {money(sum(regular,"budgeted_amount"))}'),true);
  assert.equal(page.includes('average(ordered).toLocaleString("es-DO"'),true);
  assert.equal(page.includes("presidential-type-row"),false);
  assert.equal(page.includes('if(status==="en contratacion")return "Licitación"'),true);
  assert.equal(page.includes('if(status==="planificacion"||status==="ejecucion")return "En Ejecución"'),true);
  assert.equal(page.includes('["planificacion","ejecucion"].includes'),true);
  assert.equal(page.includes('status==="finalizada"||status==="terminada"||displayProgress(item)>=100'),true);
  assert.equal(page.includes("suministro e instalacion de micro medidores de agua potable en residenciales e industrias"),true);
  assert.equal(page.includes('sum(regular,"population")'),true);
  assert.equal(page.includes('["gaspar hernandez","jamao al norte","san victor","moca","cayetano germosen"]'),true);
  assert.equal(page.includes("municipalityRank(left)-municipalityRank(right)"),true);
  assert.equal(page.includes("if(leftFinished!==rightFinished)return leftFinished?-1:1"),true);
  assert.equal(page.includes('rightStatus.localeCompare(leftStatus,"es"'),true);
  assert.equal(page.includes('item.record_type==="ACTIVO_FIJO"&&normalize(item.municipality||"")==="moca"'),true);
  assert.equal(page.includes("ACTIVOS FIJOS DEL MUNICIPIO DE MOCA"),true);
  assert.equal(page.includes('item.record_type==="ACTIVO_FIJO"?assetPaymentProgress(item)'),true);
  assert.equal(page.includes('item.record_type==="ACTIVO_FIJO"&&assetPaymentProgress(item)>=100?"Pagado"'),true);
  assert.equal(page.includes('(Number(item.total_paid||0)/Number(item.awarded_amount))*100'),true);
  assert.equal(page.includes('item.record_type==="ACTIVO_FIJO"&&item.asset_status'),true);
  assert.equal(page.indexOf('districts.map(([district,districtItems])=>location(district,districtItems,"Distrito"))')<page.indexOf('normalize(municipality)==="moca"&&mocaAssetSection()'),true);
});

test("los activos reflejan apropiación y libramiento en los reportes",async()=>{
  const page=await readFile(new URL("../app/page.tsx",import.meta.url),"utf8");
  const assets=await readFile(new URL("../app/components/FinancialAssets.tsx",import.meta.url),"utf8");
  const route=await readFile(new URL("../app/api/reports/route.ts",import.meta.url),"utf8");
  const migration=await readFile(new URL("../supabase/financial_assets_workflow.sql",import.meta.url),"utf8");
  assert.equal(assets.includes("APROPIACIÓN"),true);
  assert.equal(assets.includes("EN LIBRAMIENTO"),true);
  assert.equal(route.includes('database.rpc("list_report_asset_statuses"'),true);
  assert.equal(route.includes("asset_status:isAsset"),true);
  assert.equal(route.includes("awarded_amount:isAsset&&registeredAssetAmount>0?registeredAssetAmount"),true);
  assert.equal(migration.includes("create or replace function public.list_report_asset_statuses"),true);
  assert.equal(migration.includes("status='Libramiento' or advance_status='Libramiento'"),true);
  assert.equal(migration.includes("coalesce(sum(amount),0) registered_amount"),true);
  assert.equal(migration.includes("awarded_amount=case when v_assets_awarded>0 then v_assets_awarded else awarded_amount end"),true);
});

test("los reportes de inversión permiten actualizar el proyecto con permiso",async()=>{
  const page=await readFile(new URL("../app/page.tsx",import.meta.url),"utf8");
  const route=await readFile(new URL("../app/api/projects/technical/route.ts",import.meta.url),"utf8");
  assert.equal(page.includes("EDICIÓN DESDE REPORTE"),true);
  assert.equal(page.includes("Aplicar cambios"),true);
  assert.equal(page.includes('canEdit={canView("editar_proyectos_tecnicos")}'),true);
  assert.equal(page.includes('method:"PATCH"'),true);
  assert.equal(route.includes("export async function PATCH"),true);
  assert.equal(route.includes("editar_proyectos_tecnicos"),true);
  assert.equal(route.includes('database.rpc("update_technical_project_from_report"'),true);
  assert.equal(route.includes('.from("technical_projects").update'),false);
  assert.equal(route.includes("PROYECTO_MODIFICADO_DESDE_REPORTE"),true);
  assert.equal(route.includes('workProgress < 0 || workProgress > 100'),true);
  assert.equal(page.includes('name="population" required type="number" min="0" step="1"'),true);
  assert.equal(route.includes("Number.isInteger(population) || population < 0"),true);
  const migration=await readFile(new URL("../supabase/technical_projects.sql",import.meta.url),"utf8");
  assert.equal(migration.includes("create or replace function public.update_technical_project_from_report"),true);
  assert.equal(migration.includes("'editar_proyectos_tecnicos'"),true);
});

test("el expediente único consolida los registros del colaborador y respeta su alcance",async()=>{
  const migration=await readFile(new URL("../supabase/hr_employee_dossier.sql",import.meta.url),"utf8");
  const page=await readFile(new URL("../app/page.tsx",import.meta.url),"utf8");
  const component=await readFile(new URL("../app/components/EmployeeDossier.tsx",import.meta.url),"utf8");
  const workflow=await readFile(new URL("../.github/workflows/supabase-migrate.yml",import.meta.url),"utf8");
  for(const source of ["hr_employee_history","hr_personnel_actions","hr_employee_cases","hr_payroll_batch_lines","hr_employee_payroll_assignments","hr_employee_benefits","hr_employee_dependents","hr_employee_deductions","hr_employee_files","security_audit_log"])assert.equal(migration.includes(source),true);
  assert.equal(migration.includes("hr_employee_in_user_scope(v_user,v_employee)"),true);
  assert.equal(migration.includes("AGREGAR_DOCUMENTO_EMPLEADO"),true);
  assert.equal(page.includes("openEmployeeDossier(item.id)"),true);
  assert.equal(component.includes("EXPEDIENTE ÚNICO DEL COLABORADOR"),true);
  assert.equal(component.includes("Fecha de salida"),true);
  assert.equal(workflow.includes("hr_employee_dossier.sql"),true);
});

test("las novedades avanzan por cinco etapas y las vacaciones excluyen días no laborables",async()=>{
  const migration=await readFile(new URL("../supabase/hr_novelty_workflow.sql",import.meta.url),"utf8");
  const component=await readFile(new URL("../app/components/HrNoveltyWorkflow.tsx",import.meta.url),"utf8");
  for(const stage of ["REGISTRADA","REVISADA_ENCARGADO","VALIDADA_RRHH","APROBADA","APLICADA_NOMINA"])assert.equal(migration.includes(stage),true);
  assert.equal(migration.includes("hr_novelty_history"),true);
  assert.equal(migration.includes("hr_business_days"),true);
  assert.equal(migration.includes("extract(isodow from d)<6"),true);
  assert.equal(migration.includes("hr_holidays"),true);
  assert.equal(migration.includes("Existe otra ausencia programada en la misma unidad"),true);
  assert.equal(component.includes("COSTO PROYECTADO"),true);
  assert.equal(component.includes("Calendario y feriados"),true);
});

test("los permisos controlan límites, soportes médicos y descuentos de nómina",async()=>{
  const migration=await readFile(new URL("../supabase/hr_permission_license_control.sql",import.meta.url),"utf8");
  const component=await readFile(new URL("../app/components/HrPermissionControl.tsx",import.meta.url),"utf8");
  for(const rule of ["max_days_per_request","max_days_per_year","max_requests_per_year","consecutive_request","medical_document_status","requested_hours","payroll_discount_amount"])assert.equal(migration.includes(rule),true);
  assert.equal(migration.includes("PERMISO_SIN_SUELDO"),true);
  assert.equal(migration.includes("trg_hr_apply_payroll_adjustments"),true);
  assert.equal(component.includes("FRECUENCIA ELEVADA"),true);
  assert.equal(component.includes("No remunerado"),true);
});

test("la gestión disciplinaria protege expedientes y controla reincidencias",async()=>{
  const migration=await readFile(new URL("../supabase/hr_disciplinary_management.sql",import.meta.url),"utf8");
  const component=await readFile(new URL("../app/components/HrDisciplinaryManagement.tsx",import.meta.url),"utf8");
  const page=await readFile(new URL("../app/page.tsx",import.meta.url),"utf8");
  for(const rule of ["offense_type_id","recurrence_count","employee_statement","disciplinary_measure","follow_up_date","close_date","confidential"])assert.equal(migration.includes(rule),true);
  assert.equal(migration.includes("hr_disciplinary_evidence"),true);
  assert.equal(migration.includes("ver_amonestaciones"),true);
  assert.equal(migration.includes("hr_employee_in_user_scope"),true);
  assert.equal(component.includes("EXPEDIENTES CONFIDENCIALES"),true);
  assert.equal(component.includes("ALERTAS POR ACUMULACIÓN"),true);
  assert.equal(page.includes("<HrDisciplinaryManagement"),true);
});
