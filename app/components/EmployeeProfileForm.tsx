"use client";
import {FormEvent,useMemo,useState} from "react";

type Field={name:string;label:string;type?:string;required?:boolean;placeholder?:string;wide?:boolean};
const identity:Field[]=[
 {name:"full_name",label:"Nombre y apellido",required:true,placeholder:"Nombre completo",wide:true},
 {name:"document_number",label:"Cédula",required:true,placeholder:"Solo números"},
 {name:"birth_date",label:"Fecha de nacimiento",type:"date"},
 {name:"academic_level",label:"Escolaridad",placeholder:"Nivel académico"},
 {name:"blood_type",label:"Tipo de sangre",placeholder:"Ej.: O+"},
 {name:"driver_license",label:"Licencia de conducir",placeholder:"Número de licencia"}
];
const contact:Field[]=[
 {name:"cell_phone",label:"Celular",type:"tel",placeholder:"(809) 000-0000"},
 {name:"landline_phone",label:"Teléfono",type:"tel",placeholder:"(809) 000-0000"},
 {name:"home_address",label:"Dirección donde vive",placeholder:"Calle, sector y municipio",wide:true}
];
const work:Field[]=[
 {name:"hire_date",label:"Fecha de entrada",type:"date",required:true},
 {name:"position_name",label:"Cargo",required:true,placeholder:"Cargo institucional"},
 {name:"direction_name",label:"Dirección",required:true,placeholder:"Área de trabajo"},
 {name:"department_name",label:"Departamento",placeholder:"Si aplica"},
 {name:"division_name",label:"División",placeholder:"Si aplica"},
 {name:"section_name",label:"Sección",placeholder:"Si aplica"},
 {name:"center_name",label:"Centro de servicio",placeholder:"Si aplica"},
 {name:"immediate_supervisor",label:"Superior inmediato",placeholder:"Nombre y cargo"}
];
const benefits=[["PRIMA_TRANSPORTE","Prima de transporte","Asignación recurrente para transporte"],["VIATICOS","Viáticos","Asignación por servicios fuera de la sede"],["HORAS_EXTRAS","Horas extras","Compensación por jornada extraordinaria"]] as const;

function FieldControl({field}:{field:Field}){return <label className={field.wide?"profile-wide":""}><span>{field.label}{field.required&&<b> *</b>}</span><input name={field.name} type={field.type||"text"} required={field.required} placeholder={field.placeholder} inputMode={field.name==="document_number"?"numeric":undefined} pattern={field.name==="document_number"?"[0-9]{11}":undefined} maxLength={field.name==="document_number"?11:undefined}/>{field.name==="document_number"&&<small>11 dígitos, sin guiones.</small>}</label>}

export default function EmployeeProfileForm(){
 const [message,setMessage]=useState(""),[busy,setBusy]=useState(false),[enabled,setEnabled]=useState<Record<string,boolean>>({});
 const activeBenefits=useMemo(()=>Object.values(enabled).filter(Boolean).length,[enabled]);
 async function submit(e:FormEvent<HTMLFormElement>){
  e.preventDefault();setBusy(true);setMessage("");const form=e.currentTarget;const f=new FormData(form);const data:Record<string,unknown>=Object.fromEntries(f);
  data.monthly_salary=Number(f.get("monthly_salary")||0);data.benefits=benefits.filter(([key])=>enabled[key]).map(([key])=>({type:key,amount:Number(f.get(`amount_${key}`)||0),active:true}));
  try{const r=await fetch("/api/hr/employee-profile",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(data)});const d=await r.json();setMessage(r.ok?`Empleado guardado correctamente con el código ${d.employee_code}.`:d.error||"No fue posible guardar la ficha.");if(r.ok){form.reset();setEnabled({});window.scrollTo({top:0,behavior:"smooth"})}}catch{setMessage("No fue posible conectar con el registro de empleados.")}finally{setBusy(false)}
 }
 return <section className="employee-profile-page">
  <div className="direction-strip"><strong>DIRECCIÓN RESPONSABLE</strong><span>Dirección de Recursos Humanos · Expediente maestro</span></div>
  <header className="profile-hero"><div><span className="eyebrow">REGISTRO DE PERSONAL</span><h2>Nueva ficha de empleado</h2><p>Centraliza la identificación, ubicación institucional, compensación y beneficios del colaborador.</p></div><aside><i>Automático</i><strong>Código de empleado</strong><small>Se asignará al guardar la ficha.</small></aside></header>
  {message&&<div className={`profile-message ${message.includes("correctamente")?"success":"error"}`}>{message}</div>}
  <form className="employee-profile-form" onSubmit={submit}>
   <section className="profile-card"><header><span>01</span><div><h3>Identificación personal</h3><p>Datos básicos y documentos del empleado.</p></div></header><div className="profile-grid">{identity.map(field=><FieldControl key={field.name} field={field}/>)}</div></section>
   <section className="profile-card"><header><span>02</span><div><h3>Contacto y residencia</h3><p>Información privada para el expediente de Recursos Humanos.</p></div></header><div className="profile-grid">{contact.map(field=><FieldControl key={field.name} field={field}/>)}</div></section>
   <section className="profile-card"><header><span>03</span><div><h3>Asignación institucional</h3><p>Estructura jerárquica y lugar de trabajo.</p></div></header><div className="profile-grid">{work.map(field=><FieldControl key={field.name} field={field}/>)}</div></section>
   <section className="profile-card"><header><span>04</span><div><h3>Clasificación laboral</h3><p>Condición del nombramiento y grupo ocupacional.</p></div></header><div className="profile-grid"><label><span>Estatus laboral <b>*</b></span><select name="employment_status" required><option value="">Seleccionar</option>{["Fijo","Carrera Administrativa","Temporal","Interino","Estatuto Simplificado"].map(value=><option key={value}>{value}</option>)}</select></label><label><span>Grupo ocupacional</span><select name="occupational_group"><option value="">Seleccionar</option>{["I","II","III","IV","V"].map(value=><option key={value}>{value}</option>)}</select></label><label><span>Salario mensual <b>*</b></span><div className="money-input"><i>RD$</i><input name="monthly_salary" type="number" min="0" step="0.01" required placeholder="0.00"/></div></label></div></section>
   <section className="profile-card benefits-card"><header><span>05</span><div><h3>Beneficios adicionales</h3><p>Active únicamente los beneficios autorizados para este empleado.</p></div><strong>{activeBenefits} activos</strong></header><div className="profile-benefits">{benefits.map(([key,label,description])=><article className={enabled[key]?"enabled":""} key={key}><label><input type="checkbox" checked={Boolean(enabled[key])} onChange={event=>setEnabled(current=>({...current,[key]:event.target.checked}))}/><i/><span><b>{label}</b><small>{description}</small></span></label><div className="money-input"><i>RD$</i><input name={`amount_${key}`} type="number" min="0" step="0.01" disabled={!enabled[key]} required={enabled[key]} placeholder="0.00"/></div></article>)}</div></section>
   <footer className="profile-actions"><div><strong>Campos obligatorios</strong><span>Los campos marcados con * deben completarse antes de guardar.</span></div><button type="reset" className="outline" onClick={()=>{setEnabled({});setMessage("")}}>Limpiar formulario</button><button className="primary" disabled={busy}>{busy?"Guardando ficha…":"Guardar ficha de empleado"}</button></footer>
  </form>
 </section>
}
