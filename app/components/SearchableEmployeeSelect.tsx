"use client";
import {useMemo,useState} from "react";

type EmployeeOption={id:string;employee_code:string;full_name:string;position_name?:string;document_number?:string|null;unit_name?:string};
export default function SearchableEmployeeSelect({employees,value,onChange,name,required=false,disabled=false,label="Empleado"}:{employees:EmployeeOption[];value:string;onChange:(id:string)=>void;name?:string;required?:boolean;disabled?:boolean;label?:string}){
 const [query,setQuery]=useState("");
 const filtered=useMemo(()=>{const text=query.trim().toLowerCase();return employees.filter(item=>!text||`${item.employee_code} ${item.document_number||""} ${item.full_name} ${item.position_name||""} ${item.unit_name||""}`.toLowerCase().includes(text))},[employees,query]);
 const selected=employees.find(item=>item.id===value);
 const options=selected&&!filtered.some(item=>item.id===selected.id)?[selected,...filtered]:filtered;
 return <div className="searchable-employee-select"><label>Buscar {label.toLowerCase()}<input type="search" value={query} onChange={event=>setQuery(event.target.value)} placeholder="Escriba código, cédula, nombre o cargo" disabled={disabled} autoComplete="off"/></label><label>{label}<select name={name} value={value} onChange={event=>onChange(event.target.value)} required={required} disabled={disabled}><option value="">{options.length?"Seleccione un empleado":"Sin coincidencias"}</option>{options.map(item=><option key={item.id} value={item.id}>{item.employee_code} · {item.full_name}{item.position_name?` · ${item.position_name}`:""}</option>)}</select></label><small>{query?`${filtered.length} coincidencia(s) encontrada(s)`:"Escriba para reducir la lista"}</small></div>;
}
