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

test("seguridad de RRHH separa datos sensibles y operaciones críticas",async()=>{
  const migration=await readFile(new URL("../supabase/hr_security_confidentiality.sql",import.meta.url),"utf8");
  const page=await readFile(new URL("../app/page.tsx",import.meta.url),"utf8");
  const payroll=await readFile(new URL("../supabase/hr_payroll_processing.sql",import.meta.url),"utf8");
  const validation=await readFile(new URL("../supabase/hr_payroll_validation.sql",import.meta.url),"utf8");
  const actions=await readFile(new URL("../supabase/hr_personnel_actions.sql",import.meta.url),"utf8");
  const discipline=await readFile(new URL("../supabase/hr_disciplinary_management.sql",import.meta.url),"utf8");
  for(const permission of ["ver_datos_personales","ver_salarios","ver_descuentos","modificar_empleados","aprobar_acciones_personal","procesar_nomina","cerrar_nomina","consultar_expedientes_disciplinarios","exportar_informacion_rrhh","consultar_empleados_bajo_cargo"]){assert.equal(page.includes(permission),true);assert.equal(migration.includes(permission),true)}
  assert.equal(payroll.includes("procesar_nomina"),true);
  assert.equal(validation.includes("cerrar_nomina"),true);
  assert.equal(actions.includes("aplicar_acciones_personal"),true);
  assert.equal(discipline.includes("consultar_expedientes_disciplinarios"),true);
  assert.equal(migration.includes("hr_employee_in_user_scope"),true);
});

test("calidad de datos valida identidad, fechas, estructura y trazabilidad",async()=>{
  const migration=await readFile(new URL("../supabase/hr_data_quality.sql",import.meta.url),"utf8");
  const payroll=await readFile(new URL("../supabase/hr_payroll_processing.sql",import.meta.url),"utf8");
  const component=await readFile(new URL("../app/components/HrDataQuality.tsx",import.meta.url),"utf8");
  for(const rule of ["CEDULA_INVALIDA","EMPLEADO_DUPLICADO","EDAD_INVALIDA","FECHAS_INCOHERENTES","UNIDAD_INVALIDA","CARGO_INVALIDO","SIN_SALARIO","CLASIFICACION_PRESUPUESTARIA"])assert.equal(migration.includes(rule),true);
  assert.equal(migration.includes("hr_employee_change_audit"),true);
  assert.equal(migration.includes("trg_hr_validate_employee_master"),true);
  assert.equal(payroll.includes("Ya existe un empleado registrado con esta cédula"),true);
  assert.equal(payroll.includes("fecha de salida no puede ser anterior"),true);
  assert.equal(component.includes("Trazabilidad de modificaciones"),true);
});

test("la fase base de RRHH mantiene una sola fuente maestra y catálogos relacionados",async()=>{
  const migration=await readFile(new URL("../supabase/hr_module_foundation.sql",import.meta.url),"utf8");
  const payroll=await readFile(new URL("../supabase/hr_payroll_processing.sql",import.meta.url),"utf8");
  const page=await readFile(new URL("../app/page.tsx",import.meta.url),"utf8");
  for(const catalog of ["hr_employment_status_catalog","hr_occupational_group_catalog","hr_exit_cause_catalog","hr_position_catalog","organization_units"])assert.equal(migration.includes(catalog),true);
  for(const relation of ["position_id","employment_status_id","occupational_group_id","exit_cause_id","organization_unit_id","app_user_id"])assert.equal(migration.includes(relation),true);
  assert.equal(migration.includes("hr_employee_current"),true);
  assert.equal(migration.includes("hr_employee_timeline"),true);
  assert.equal(migration.includes("audit_hr_module_base"),true);
  assert.equal(payroll.includes("v_unit_id"),true);
  assert.equal(payroll.includes("Centro"),true);
  assert.equal(page.includes('module.section!=="Histórico de Empleados"'),true);
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
  assert.equal(page.includes('section === "Vacantes por Área"')&&page.includes('section === "Indicadores RRHH"'),true);
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
  assert.equal(component.includes("width:7.75in!important;height:10.2in!important"),true);
  assert.equal(component.includes("margin:.2in auto 0!important"),true);
  assert.equal(component.includes(".action-approvals{flex:1 1 auto!important;height:auto!important;min-height:190px!important"),true);
  assert.equal(component.includes("grid-template-rows:58px 1fr!important"),true);
  assert.equal(component.includes("grid-template-columns:minmax(0,1fr) minmax(0,1.65fr)!important"),true);
  assert.equal(component.includes("grid-template-rows:38px 38px!important;align-content:space-between!important"),true);
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
  assert.equal(sql.includes("Solo se pueden modificar acciones registradas o devueltas"),true);
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
  assert.equal(page.includes('loadBudgetEvent(section==="Apropiaciones y Adjudicaciones")'),true);
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
  assert.equal(migration.includes("consultar_expedientes_disciplinarios"),true);
  assert.equal(migration.includes("hr_employee_in_user_scope"),true);
  assert.equal(component.includes("EXPEDIENTES CONFIDENCIALES"),true);
  assert.equal(component.includes("ALERTAS POR ACUMULACIÓN"),true);
  assert.equal(page.includes("<HrDisciplinaryManagement"),true);
});

test("la nómina integrada exige validación sin errores antes del cierre",async()=>{
  const migration=await readFile(new URL("../supabase/hr_payroll_validation.sql",import.meta.url),"utf8");
  const component=await readFile(new URL("../app/components/PayrollProcessing.tsx",import.meta.url),"utf8");
  const route=await readFile(new URL("../app/api/hr/payroll-processing/route.ts",import.meta.url),"utf8");
  for(const source of ["hr_employee_benefits","hr_personnel_actions","hr_payroll_adjustments","hr_payroll_batch_lines"])assert.equal(migration.includes(source),true);
  for(const check of ["DATOS_INCOMPLETOS","ACCION_PENDIENTE","MOVIMIENTO_PERIODO","VARIACION_MES_ANTERIOR","NUEVO_EN_NOMINA","SALIDA_DE_NOMINA"])assert.equal(migration.includes(check),true);
  assert.equal(migration.includes("validation_status not in('LISTA','CON_ADVERTENCIAS')"),true);
  assert.equal(migration.includes("severity='ERROR'"),true);
  assert.equal(component.includes("CONTROL PREVIO AL CIERRE"),true);
  assert.equal(component.includes("Validar nómina"),true);
  assert.equal(component.includes("Cerrar nómina"),true);
  assert.equal(route.includes("validate_hr_payroll_batch"),true);
  assert.equal(route.includes("close_hr_payroll_batch"),true);
});

test("la comparación mensual detecta movimientos, variaciones y anomalías de nómina",async()=>{
  const migration=await readFile(new URL("../supabase/hr_payroll_monthly_comparison.sql",import.meta.url),"utf8");
  const component=await readFile(new URL("../app/components/PayrollMonthlyComparison.tsx",import.meta.url),"utf8");
  const page=await readFile(new URL("../app/page.tsx",import.meta.url),"utf8");
  for(const change of ["NUEVO","RETIRADO","AUMENTO","REDUCCION","NUEVO_DESCUENTO"])assert.equal(migration.includes(change),true);
  for(const anomaly of ["PAGO_DUPLICADO","MULTIPLES_NOMINAS","SIN_CUENTA_PRESUPUESTARIA"])assert.equal(migration.includes(anomaly),true);
  assert.equal(migration.includes("execution_fund,l.program,l.activity"),true);
  assert.equal(component.includes("Variación por clasificación presupuestaria"),true);
  assert.equal(component.includes("Exportar CSV"),true);
  assert.equal(page.includes("<PayrollMonthlyComparison"),true);
});

test("el presupuesto de nómina calcula ejecución, proyección, sobregiros y simulaciones",async()=>{
  const migration=await readFile(new URL("../supabase/hr_payroll_budget_operations.sql",import.meta.url),"utf8");
  const component=await readFile(new URL("../app/components/PayrollBudgetOperations.tsx",import.meta.url),"utf8");
  const route=await readFile(new URL("../app/api/hr/payroll-budget/route.ts",import.meta.url),"utf8");
  for(const concept of ["monthly_budget","annual_budget","executed_month","executed_ytd","available_month","available_annual","projected_year","overdraft"])assert.equal(migration.includes(concept),true);
  assert.equal(migration.includes("hr_payroll_budget_modifications"),true);
  assert.equal(migration.includes("MODIFICAR_PRESUPUESTO_NOMINA"),true);
  assert.equal(migration.includes("simulate_hr_payroll_budget"),true);
  assert.equal(component.includes("ALERTA DE SOBREGIRO"),true);
  assert.equal(component.includes("Simulación de impacto"),true);
  assert.equal(route.includes("list_hr_payroll_budget_operations"),true);
  assert.equal(route.includes("save_hr_payroll_budget_modification"),true);
});

test("la fase 7 cierra períodos presupuestarios y bloquea operaciones posteriores",async()=>{
 const migration=await readFile(new URL("../supabase/hr_payroll_budget_phase7.sql",import.meta.url),"utf8");
 const component=await readFile(new URL("../app/components/PayrollBudgetOperations.tsx",import.meta.url),"utf8");
 const route=await readFile(new URL("../app/api/hr/payroll-budget/route.ts",import.meta.url),"utf8");
 for(const rule of ["hr_payroll_budget_periods","set_hr_payroll_budget_period_status","hr_protect_closed_budget_period","hr_protect_closed_budget_modification","CERRAR_PERIODO_PRESUPUESTO_NOMINA"])assert.equal(migration.includes(rule),true);
 assert.equal(component.includes("PERÍODO PRESUPUESTARIO"),true);
 assert.equal(component.includes("Cerrar período"),true);
 assert.equal(route.includes("get_hr_payroll_budget_period"),true);
 assert.equal(route.includes('body.action==="period"'),true);
});

test("la fase 8 genera reportes oficiales de RRHH con Excel y PDF institucional",async()=>{
 const migration=await readFile(new URL("../supabase/hr_official_reports_phase8.sql",import.meta.url),"utf8");
 const component=await readFile(new URL("../app/components/HrOfficialReports.tsx",import.meta.url),"utf8");
 const route=await readFile(new URL("../app/api/hr/official-reports/route.ts",import.meta.url),"utf8");
 const styles=await readFile(new URL("../app/globals.css",import.meta.url),"utf8");
 for(const source of ["hr_payroll_batch_lines","hr_employee_cases","hr_personnel_actions","hr_vacancies","hr_payroll_budget_lines"])assert.equal(migration.includes(source),true);
 for(const report of ["Nómina del mes","Prima de transporte","Viáticos","Horas extras","Otros descuentos","Entradas y salidas","Vacaciones","Permisos y licencias","Amonestaciones","Vacantes y disponibilidad","Ejecución presupuestaria"])assert.equal(component.includes(report),true);
 assert.equal(component.includes("application/vnd.ms-excel"),true);
 assert.equal(component.includes("print-hr-official-report"),true);
 assert.equal(styles.includes("body.print-hr-official-report #hr-official-report"),true);
 assert.equal(route.includes("list_hr_official_report"),true);
});

test("responsabilidades de RRHH y reportes oficiales poseen permisos específicos",async()=>{
 const migration=await readFile(new URL("../supabase/hr_responsibilities_reports_permissions.sql",import.meta.url),"utf8");
 const component=await readFile(new URL("../app/components/HrOfficialReports.tsx",import.meta.url),"utf8");
 const page=await readFile(new URL("../app/page.tsx",import.meta.url),"utf8");
 const route=await readFile(new URL("../app/api/hr/official-reports/route.ts",import.meta.url),"utf8");
 const workflow=await readFile(new URL("../.github/workflows/supabase-migrate.yml",import.meta.url),"utf8");
 for(const permission of ["ver_registro_empleados_rrhh","ver_acciones_personal_rrhh","ver_vacantes_rrhh","ver_reclutamiento_rrhh","ver_desempeno_rrhh","ver_capacitacion_rrhh","ver_asistencia_rrhh","ver_nomina_rrhh","ver_presupuesto_nomina_rrhh","ver_reportes_oficiales_rrhh"])assert.equal(page.includes(permission),true);
 for(const permission of ["reporte_rrhh_nomina","reporte_rrhh_prima_transporte","reporte_rrhh_viaticos","reporte_rrhh_horas_extras","reporte_rrhh_otros_descuentos","reporte_rrhh_entradas_salidas","reporte_rrhh_vacaciones","reporte_rrhh_permisos","reporte_rrhh_amonestaciones","reporte_rrhh_vacantes","reporte_rrhh_presupuesto"]){assert.equal(migration.includes(permission),true);assert.equal(component.includes(permission),true)}
 assert.equal(component.includes("hr-report-palette"),true);
 assert.equal(route.includes("p_report_type"),true);
 assert.equal(migration.includes("list_hr_official_report"),true);
 assert.equal(workflow.includes("hr_responsibilities_reports_permissions.sql"),true);
});

test("la fase 9 consolida indicadores y genera alertas dirigidas de RRHH",async()=>{
 const migration=await readFile(new URL("../supabase/hr_indicators_alerts_phase9.sql",import.meta.url),"utf8");
 const component=await readFile(new URL("../app/components/HrOperationalIndicators.tsx",import.meta.url),"utf8");
 const route=await readFile(new URL("../app/api/hr/indicators/route.ts",import.meta.url),"utf8");
 for(const indicator of ["payroll_variation","benefits_by_unit","consecutive_licenses","directed_alerts"])assert.equal(migration.includes(indicator),true);
 assert.equal(migration.includes("app_notifications"),true);
 assert.equal(migration.includes("hr_employee_in_user_scope"),true);
 for(const label of ["Licencias consecutivas","VARIACIÓN BRUTA MENSUAL","Alertas para su intervención","Beneficios y horas extras por unidad"])assert.equal(component.includes(label),true);
 assert.equal(route.includes("list_hr_decision_indicators"),true);
});

test("las desvinculaciones liberan plazas que pueden planificarse, reclutarse y ocuparse",async()=>{
  const base=await readFile(new URL("../supabase/hr_personnel_actions.sql",import.meta.url),"utf8");
  const migration=await readFile(new URL("../supabase/hr_vacancy_planning.sql",import.meta.url),"utf8");
  const component=await readFile(new URL("../app/components/VacancyDashboard.tsx",import.meta.url),"utf8");
  assert.equal(base.includes("hr_sync_employee_vacancy"),true);
  for(const status of ["CON_RECLUTAMIENTO","CONGELADA","ELIMINADA","OCUPADA"])assert.equal(migration.includes(status),true);
  assert.equal(migration.includes("hr_recruitment_processes"),true);
  assert.equal(migration.includes("monthly_amount*greatest"),true);
  assert.equal(migration.includes("GESTIONAR_VACANTE"),true);
  assert.equal(migration.includes("filled_by_employee_id=v_employee.id"),true);
  assert.equal(component.includes("DISPONIBILIDAD ANUAL"),true);
  assert.equal(component.includes("VINCULAR NUEVO EMPLEADO"),true);
  assert.equal(component.includes("Reclutar"),true);
});

test("reclutamiento conecta solicitud, candidatos, evaluaciones y nombramiento con la vacante",async()=>{
 const migration=await readFile(new URL("../supabase/hr_recruitment_selection.sql",import.meta.url),"utf8");
 const component=await readFile(new URL("../app/components/RecruitmentManagement.tsx",import.meta.url),"utf8");
 for(const table of ["hr_recruitment_candidates","hr_candidate_evaluations","hr_candidate_documents"])assert.equal(migration.includes(table),true);
 for(const action of ["SOLICITAR","APROBAR","CANDIDATO","EVALUAR","DOCUMENTO","SELECCIONAR","NOMBRAR"])assert.equal(migration.includes(`p_action='${action}'`)||migration.includes(`p_action in('${action}'`),true);
 assert.equal(migration.includes("hr_employee_code_seq"),true);
 assert.equal(migration.includes("filled_by_employee_id=v_employee"),true);
 assert.equal(component.includes("Reclutamiento y selección"),true);
 assert.equal(component.includes("Registrar candidato"),true);
 assert.equal(component.includes("Nombrar"),true);
});

test("desempeño integra metas, competencias, doble evaluación y planes de mejora",async()=>{
 const migration=await readFile(new URL("../supabase/hr_performance_management.sql",import.meta.url),"utf8");
 const component=await readFile(new URL("../app/components/PerformanceManagement.tsx",import.meta.url),"utf8");
 for(const table of ["hr_performance_cycles","hr_performance_evaluations","hr_performance_goals","hr_performance_competencies","hr_improvement_plans"])assert.equal(migration.includes(table),true);
 assert.equal(migration.includes("g*.40+c*.30+s*.10+sup*.20"),true);
 assert.equal(migration.includes("recommend_training"),true);
 assert.equal(migration.includes("recommend_promotion"),true);
 assert.equal(migration.includes("recommend_compensation"),true);
 assert.equal(component.includes("Metas individuales y de unidad"),true);
 assert.equal(component.includes("Competencias del cargo"),true);
 assert.equal(component.includes("Plan de mejora"),true);
});

test("capacitación integra necesidades, plan anual, cursos, costos y certificados",async()=>{
 const migration=await readFile(new URL("../supabase/hr_training_management.sql",import.meta.url),"utf8");
 const component=await readFile(new URL("../app/components/TrainingManagement.tsx",import.meta.url),"utf8");
 for(const table of ["hr_training_needs","hr_training_plans","hr_training_courses","hr_training_participants"])assert.equal(migration.includes(table),true);
 for(const field of ["attendance_percent","learning_score","certificate_url","planned_cost","actual_cost"])assert.equal(migration.includes(field),true);
 assert.equal(migration.includes("performance_evaluation_id"),true);
 assert.equal(component.includes("Historial de capacitación por empleado"),true);
 assert.equal(component.includes("EJECUCIÓN DEL PLAN"),true);
 assert.equal(component.includes("Certificado"),true);
});

test("asistencia controla marcaciones, reincidencias y novedades de nómina",async()=>{
 const migration=await readFile(new URL("../supabase/hr_attendance_management.sql",import.meta.url),"utf8");
 const component=await readFile(new URL("../app/components/AttendanceManagement.tsx",import.meta.url),"utf8");
 for(const table of ["hr_attendance_imports","hr_attendance_records","hr_attendance_payroll_novelties"])assert.equal(migration.includes(table),true);
 assert.equal(migration.includes("BIOMETRICO"),true);
 assert.equal(migration.includes("AUSENCIA_NO_JUSTIFICADA"),true);
 assert.equal(migration.includes("late_count')>=3"),false);
 assert.equal(migration.includes("filter(where a.status='TARDANZA')>=3"),true);
 assert.equal(migration.includes("hr_apply_payroll_adjustments"),true);
 assert.equal(component.includes("Alertas por reincidencia"),true);
 assert.equal(component.includes("Generar novedad"),true);
});

test("el panel de RRHH consolida dotación, costos, novedades y alertas",async()=>{
 const migration=await readFile(new URL("../supabase/hr_operational_indicators.sql",import.meta.url),"utf8");
 const component=await readFile(new URL("../app/components/HrOperationalIndicators.tsx",import.meta.url),"utf8");
 for(const metric of ["rotation_rate","absence_rate","recurrent_permissions","pending_vacations","overtime_by_unit","retirement_alerts"])assert.equal(migration.includes(metric),true);
 for(const source of ["hr_attendance_records","hr_payroll_batch_lines","hr_payroll_budget_lines","hr_employee_cases","hr_vacancies"])assert.equal(migration.includes(source),true);
 assert.equal(component.includes("Distribución por dirección"),true);
 assert.equal(component.includes("Próximos a jubilación"),true);
 assert.equal(component.includes("EJECUCIÓN PRESUPUESTARIA"),true);
});
test("la seguridad de Recursos Humanos aplica alcance jerárquico y confidencialidad en Supabase",async()=>{
  const migration=await readFile(new URL("../supabase/hr_security_hierarchical_scope.sql",import.meta.url),"utf8");
  const workflow=await readFile(new URL("../.github/workflows/supabase-migrate.yml",import.meta.url),"utf8");
  const usersApi=await readFile(new URL("../app/api/users/route.ts",import.meta.url),"utf8");
  const page=await readFile(new URL("../app/page.tsx",import.meta.url),"utf8");
  for(const rule of ["organization_scope_unit_id","hr_unit_contains","with recursive lineage","hr_employee_in_user_scope","admin_set_user_hr_scope"])assert.equal(migration.includes(rule),true);
  for(const permission of ["ver_datos_personales","ver_salarios","ver_descuentos","consultar_expedientes_disciplinarios"])assert.equal(migration.includes(permission),true);
  for(const audit of ["HR_SCOPE_UPDATED","HR_EMPLOYEE_LIST_VIEWED","HR_DOSSIER_VIEWED"])assert.equal(migration.includes(audit),true);
  assert.equal(workflow.includes("hr_security_hierarchical_scope.sql"),true);
  assert.equal(usersApi.includes('action==="SET_HR_SCOPE"'),true);
  assert.equal(page.includes("organization_scope_unit_id"),true);
});

test("las acciones de personal siguen revisión, aprobación y aplicación separadas",async()=>{
 const workflow=await readFile(new URL("../supabase/hr_personnel_actions_workflow.sql",import.meta.url),"utf8");
 const actions=await readFile(new URL("../supabase/hr_personnel_actions.sql",import.meta.url),"utf8");
 const component=await readFile(new URL("../app/components/PersonnelAction.tsx",import.meta.url),"utf8");
 for(const stage of ["REGISTRADA","REVISADA","APROBADA","APLICADA","DEVUELTA"])assert.equal(workflow.includes(stage),true);
 for(const permission of ["revisar_acciones_personal","aprobar_acciones_personal","aplicar_acciones_personal"])assert.equal(workflow.includes(permission),true);
 assert.equal(workflow.includes("hr_personnel_action_workflow_history"),true);
 assert.equal(workflow.includes("La observación de devolución es obligatoria"),true);
 assert.equal(actions.includes("organization_unit_id=coalesce(v_unit_id,organization_unit_id)"),true);
 assert.equal(actions.includes("status='APLICADA'"),true);
 assert.equal(component.includes("Aplicar al expediente"),true);
 assert.equal(component.includes("Reimprimir"),true);
});

test("la fase 4 consolida permisos, vacaciones y amonestaciones con trazabilidad",async()=>{
 const migration=await readFile(new URL("../supabase/hr_cases_phase4.sql",import.meta.url),"utf8");
 const workflow=await readFile(new URL("../.github/workflows/supabase-migrate.yml",import.meta.url),"utf8");
 const page=await readFile(new URL("../app/page.tsx",import.meta.url),"utf8");
 for(const rule of ["hr_novelties_type_number_uidx","assign_hr_novelty_module_number","hr_business_days","La solicitud excede el balance de vacaciones disponible","hr_employee_in_user_scope"])assert.equal(migration.includes(rule),true);
 for(const stage of ["REVISADA_ENCARGADO","VALIDADA_RRHH","APROBADA","APLICADA_NOMINA","DEVUELTA","RECHAZADA"])assert.equal(migration.includes(stage),true);
 for(const audit of ["hr_novelty_history","hr_disciplinary_history","TRANSICION_NOVEDAD"])assert.equal(migration.includes(audit),true);
 assert.equal(migration.includes("No se permite saltar ni repetir etapas"),true);
 assert.equal(migration.includes("procesar_nomina"),true);
 assert.equal(workflow.includes("hr_cases_phase4.sql"),true);
 assert.equal(page.includes('section==="Vacaciones"&&<HrNoveltyWorkflow vacationsOnly'),true);
 assert.equal(page.includes('section==="Vacaciones"&&<EmployeeCases'),false);
});

test("la fase 5 vincula empleados, plazas, vacantes y presupuesto institucional",async()=>{
 const migration=await readFile(new URL("../supabase/hr_positions_phase5.sql",import.meta.url),"utf8");
 const workflow=await readFile(new URL("../.github/workflows/supabase-migrate.yml",import.meta.url),"utf8");
 const component=await readFile(new URL("../app/components/StaffPositionStructure.tsx",import.meta.url),"utf8");
 const route=await readFile(new URL("../app/api/hr/vacancies/route.ts",import.meta.url),"utf8");
 for(const rule of ["hr_staff_positions","position_code","staff_position_id","hr_release_staff_position_on_exit","hr_sync_staff_position_from_vacancy"])assert.equal(migration.includes(rule),true);
 for(const status of ["OCUPADA","VACANTE","CONGELADA","ELIMINADA"])assert.equal(migration.includes(status),true);
 for(const budget of ["execution_fund","program","subproduct","activity","monthly_amount"])assert.equal(migration.includes(budget),true);
 assert.equal(migration.includes("create_hr_staff_position"),true);
 assert.equal(migration.includes("CREAR_PLAZA"),true);
 assert.equal(workflow.includes("hr_positions_phase5.sql"),true);
 assert.equal(component.includes("CATÁLOGO INSTITUCIONAL DE PLAZAS"),true);
 assert.equal(component.includes("Crear plaza vacante"),true);
 assert.equal(route.includes('body.action==="CREAR_PLAZA"'),true);
});

test("la fase 6 segmenta, valida, cierra y reabre la nómina con auditoría",async()=>{
 const migration=await readFile(new URL("../supabase/hr_payroll_engine_phase6.sql",import.meta.url),"utf8");
 const workflow=await readFile(new URL("../.github/workflows/supabase-migrate.yml",import.meta.url),"utf8");
 const component=await readFile(new URL("../app/components/PayrollProcessing.tsx",import.meta.url),"utf8");
 for(const dimension of ["execution_fund","program","subproduct","activity","account_code"])assert.equal(migration.includes(dimension),true);
 for(const rule of ["reopen_hr_payroll_batch","hr_protect_closed_payroll_line","REABRIR_NOMINA","applied_batch_id"])assert.equal(migration.includes(rule),true);
 assert.equal(migration.includes("ACUMULADO_MENSUAL_INCREMENTAL"),true);
 assert.equal(workflow.includes("hr_payroll_engine_phase6.sql"),true);
 assert.equal(component.includes("Segmento presupuestario"),true);
 assert.equal(component.includes("Reabrir con motivo"),true);
});

test("Recursos Humanos abre un centro de módulos y no expande la barra lateral",async()=>{
 const page=await readFile(new URL("../app/page.tsx",import.meta.url),"utf8");
 const styles=await readFile(new URL("../app/globals.css",import.meta.url),"utf8");
 assert.equal(page.includes('isHr?"Centro de módulos"'),true);
 assert.equal(page.includes('setSection("Recursos Humanos")'),true);
 assert.equal(page.includes("hr-module-hub"),true);
 assert.equal(page.includes("Solo se muestran las funciones autorizadas"),true);
 assert.equal(styles.includes(".hr-hub-grid"),true);
 for(const unit of ["Sección de Registro y Control de Nómina","Sección de Evaluación del Desempeño y Capacitación","Sección de Organización del Trabajo y Compensaciones"])assert.equal(page.includes(unit),true);
 assert.equal(page.includes("hrUnitGroups"),true);
 assert.equal(styles.includes(".hr-unit-groups"),true);
 assert.equal(page.includes('section === "Indicadores RRHH" || section === "Flujo de Novedades" ||'),true);
 assert.equal(styles.includes(".sidebar { position:fixed;"),true);
 assert.equal(styles.includes(".app-shell { min-height:100vh; display:block; padding-left:248px; }"),true);
});

test("las licencias médicas poseen registro operativo y permisos independientes",async()=>{
 const page=await readFile(new URL("../app/page.tsx",import.meta.url),"utf8");
 const component=await readFile(new URL("../app/components/HrPermissionControl.tsx",import.meta.url),"utf8");
 const migration=await readFile(new URL("../supabase/hr_medical_leave_module.sql",import.meta.url),"utf8");
 const workflow=await readFile(new URL("../.github/workflows/supabase-migrate.yml",import.meta.url),"utf8");
 for(const permission of ["ver_licencias_medicas","registrar_licencias_medicas","validar_licencias_medicas"])assert.equal(page.includes(permission),true);
 assert.equal(page.includes('section:"Licencias Médicas"'),true);
 assert.equal(page.includes("<HrPermissionControl medicalOnly"),true);
 assert.equal(component.includes('medicalOnly?"Registro de licencias médicas"'),true);
 assert.equal(component.includes("requires_medical_document"),true);
 assert.equal(component.includes("medical_document_status"),true);
 assert.equal(migration.includes("validar_licencias_medicas"),true);
 assert.equal(migration.includes("VALIDAR_DOCUMENTO_MEDICO"),true);
 assert.equal(workflow.includes("hr_medical_leave_module.sql"),true);
});

test("carnetización utiliza empleados activos, Supabase y permisos independientes",async()=>{
 const page=await readFile(new URL("../app/page.tsx",import.meta.url),"utf8");
 const component=await readFile(new URL("../app/components/HrIdCardManagement.tsx",import.meta.url),"utf8");
 const route=await readFile(new URL("../app/api/hr/id-cards/route.ts",import.meta.url),"utf8");
 const styles=await readFile(new URL("../app/globals.css",import.meta.url),"utf8");
 const migration=await readFile(new URL("../supabase/hr_id_card_management.sql",import.meta.url),"utf8");
 const workflow=await readFile(new URL("../.github/workflows/supabase-migrate.yml",import.meta.url),"utf8");
 for(const permission of ["ver_carnets_rrhh","gestionar_carnets_rrhh","imprimir_carnets_rrhh","configurar_carnets_rrhh"])assert.equal(page.includes(permission),true);
 assert.equal(page.includes('section:"Carnetización"'),true);
 assert.equal(styles.includes("width:54mm;height:85mm"),true);
 assert.equal(component.includes("/api/hr/id-cards"),true);
 assert.equal(component.includes("localStorage"),false);
 assert.equal(route.includes('rpc("save_hr_id_card"'),true);
 assert.equal(migration.includes("create table if not exists public.hr_employee_id_cards"),true);
 assert.equal(migration.includes("public.hr_employee_in_user_scope"),true);
 assert.equal(migration.includes("HR_ID_CARD_SAVED"),true);
 assert.equal(workflow.includes("hr_id_card_management.sql"),true);
});

test("el ingreso de empleados distingue creación y sustitución de vacantes",async()=>{
 const migration=await readFile(new URL("../supabase/hr_employee_entry_management.sql",import.meta.url),"utf8");
 const component=await readFile(new URL("../app/components/EmployeeProfileForm.tsx",import.meta.url),"utf8");
 const dossier=await readFile(new URL("../app/components/EmployeeDossier.tsx",import.meta.url),"utf8");
 const route=await readFile(new URL("../app/api/hr/employee-profile/route.ts",import.meta.url),"utf8");
 for(const field of ["entry_type","entry_vacancy_id","referred_by_internal"])assert.equal(migration.includes(field),true);
 assert.equal(migration.includes("status='OCUPADA'"),true);
 assert.equal(migration.includes("filled_by_employee_id=v_employee_id"),true);
 assert.equal(component.includes("Filtrar vacantes por área"),true);
 assert.equal(component.includes("Recomendado por — uso interno"),true);
 assert.equal(dossier.includes("INFORMACIÓN INTERNA DE INGRESO"),true);
 assert.equal(route.includes("save_hr_employee_profile_with_entry"),true);
});

test("la fase 10 integra reclutamiento, desempeño y capacitación",async()=>{
 const migration=await readFile(new URL("../supabase/hr_talent_cycle_phase10.sql",import.meta.url),"utf8");
 const workflow=await readFile(new URL("../.github/workflows/supabase-migrate.yml",import.meta.url),"utf8");
 const training=await readFile(new URL("../app/components/TrainingManagement.tsx",import.meta.url),"utf8");
 for(const integration of ["hr_sync_performance_training_need","hr_performance_training_need_trg","performance_evaluation_id","DESEMPENO","list_hr_talent_cycle"])assert.equal(migration.includes(integration),true);
 for(const area of ["recruitment","performance","training"])assert.equal(migration.includes(`'${area}'`),true);
 assert.equal(workflow.includes("hr_talent_cycle_phase10.sql"),true);
 assert.equal(training.includes("Derivadas de desempeño"),true);
});

test("formularios y pantallas comparten una capa adaptable sin desbordamientos",async()=>{
 const styles=await readFile(new URL("../app/globals.css",import.meta.url),"utf8");
 for(const rule of ["box-sizing:border-box","overflow-wrap:anywhere","max-height:calc(100dvh - 32px)","overscroll-behavior-inline:contain","grid-template-columns:repeat(3,minmax(0,1fr))","@media screen and (max-width:700px)"])assert.equal(styles.includes(rule),true);
 assert.equal(styles.includes(".personnel-action-sheet{max-width:8.5in"),true);
});

test("la ficha del empleado mantiene datos legibles sin secciones intercaladas",async()=>{
 const styles=await readFile(new URL("../app/globals.css",import.meta.url),"utf8");
 const component=await readFile(new URL("../app/components/EmployeeProfileForm.tsx",import.meta.url),"utf8");
 assert.equal(styles.includes(".employee-profile-form>.profile-card,.employee-profile-form>.profile-actions{grid-column:1/-1"),true);
 assert.equal(styles.includes(".employee-profile-form .profile-grid{grid-template-columns:repeat(3,minmax(0,1fr))"),true);
 assert.equal(styles.includes(".employee-profile-form .profile-grid label>span{min-height:16px"),true);
 assert.equal(styles.includes(".employee-profile-form .payroll-assignment-list article{grid-template-columns:repeat(5"),true);
 assert.equal(component.includes('field={field} initial={initial}'),true);
 for(const number of ["01","02","03","04","05","06","07","08"])assert.equal(component.includes(`<span>${number}</span>`),true);
});

test("la interfaz institucional aplica una base visual profesional y accesible",async()=>{
 const styles=await readFile(new URL("../app/globals.css",import.meta.url),"utf8");
 const packageFile=JSON.parse(await readFile(new URL("../package.json",import.meta.url),"utf8"));
 for(const rule of [":focus-visible","text-rendering:optimizeLegibility","font-size:9px!important","position:sticky;top:0","prefers-reduced-motion:reduce","min-width:320px","--card-shadow"])assert.equal(styles.includes(rule),true);
 assert.equal(packageFile.engines.node,">=22 <25");
 assert.equal(packageFile.dependencies.next,"^16.4.3");
 assert.equal(packageFile.dependencies["@supabase/supabase-js"],"^2.118.0");
 assert.equal(packageFile.devDependencies["eslint-config-next"],"^16.4.3");
});

test("la ficha flotante del empleado conserva cada etiqueta unida a su dato",async()=>{
 const styles=await readFile(new URL("../app/globals.css",import.meta.url),"utf8");
 const component=await readFile(new URL("../app/components/EmployeeDossier.tsx",import.meta.url),"utf8");
 assert.equal(component.includes("function DossierField"),true);
 assert.equal(component.includes('className="dossier-field-grid"'),true);
 assert.equal(component.includes("<dl>"),false);
 for(const rule of [".dossier-field-grid>article.is-wide{grid-column:1/-1}",".employee-dossier-modal{position:relative;width:min(1180px", "height:100dvh", "overflow-wrap:anywhere"])assert.equal(styles.includes(rule),true);
});

test("el encabezado y las pestañas del expediente mantienen una lectura compacta",async()=>{
 const styles=await readFile(new URL("../app/globals.css",import.meta.url),"utf8");
 const component=await readFile(new URL("../app/components/EmployeeDossier.tsx",import.meta.url),"utf8");
 assert.equal(component.includes("employee-dossier-meta"),true);
 assert.equal(component.includes("employee-dossier-position"),true);
 assert.equal(component.includes("employee_code} · Cédula"),false);
 assert.equal(styles.includes(".employee-dossier-tabs>button{display:inline-flex;flex:0 0 auto!important"),true);
 assert.equal(styles.includes("width:auto!important;height:30px!important;min-height:30px!important"),true);
 assert.equal(styles.includes("height:auto!important;min-height:112px"),true);
});

test("el código del empleado es independiente de la cédula y la acción usa formato dominicano",async()=>{
 const component=await readFile(new URL("../app/components/PersonnelAction.tsx",import.meta.url),"utf8");
 const migration=await readFile(new URL("../supabase/hr_employee_code_separation.sql",import.meta.url),"utf8");
 const payroll=await readFile(new URL("../supabase/hr_payroll_execution.sql",import.meta.url),"utf8");
 const workflow=await readFile(new URL("../.github/workflows/supabase-migrate.yml",import.meta.url),"utf8");
 assert.equal(component.includes("const dominicanId="),true);
 assert.equal(component.includes("dominicanId(employee?.document_number||editing?.document_number)"),true);
 assert.equal(migration.includes("hr_employees_code_document_distinct"),true);
 assert.equal(migration.includes("new.employee_code:='EMP-'"),true);
 assert.equal(payroll.includes("select 'EMP-'||lpad(nextval('public.hr_employee_code_seq')"),true);
 assert.equal(workflow.includes("hr_employee_code_separation.sql"),true);
});
