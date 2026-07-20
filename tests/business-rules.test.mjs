import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {nextMeasurementStatus,paidTotal,paymentWithinAppropriation,permissionGranted} from "../app/lib/business-rules.mjs";

test("un usuario sin permiso no puede editar proyectos",()=>{
  assert.equal(permissionGranted("Usuario",{editar_proyectos_tecnicos:false},"editar_proyectos_tecnicos"),false);
  assert.equal(permissionGranted("Administrador",{},"editar_proyectos_tecnicos"),true);
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
