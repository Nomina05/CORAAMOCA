import {cookies} from "next/headers";
import {NextResponse} from "next/server";
import {authDatabase,sessionCookie} from "../../auth/_supabase";

const clean=(value:string|undefined)=>String(value||"").trim();
const numberValue=(value:string|undefined)=>Number(clean(value).replaceAll(",","").replace(/[^0-9.-]/g,""))||0;
const isoDate=(value:string|undefined)=>{const raw=clean(value);if(!raw)return null;const parts=raw.split("/").map(Number);if(parts.length!==3||parts.some(Number.isNaN))return null;return `${parts[2].toString().padStart(4,"0")}-${parts[0].toString().padStart(2,"0")}-${parts[1].toString().padStart(2,"0")}`;};

export async function GET(request:Request){
  const token=(await cookies()).get(sessionCookie)?.value;
  if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
  const url=new URL(request.url),year=Number(url.searchParams.get("year")||2026),month=url.searchParams.get("month");
  const {data,error}=await authDatabase().rpc("list_hr_payroll_runs",{p_token:token,p_year:year,p_month:month?Number(month):null});
  if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible consultar la ejecución de nómina."},{status:403});
  return NextResponse.json({runs:data.runs||[],lines:data.lines||[]});
}

export async function POST(request:Request){
  const token=(await cookies()).get(sessionCookie)?.value;
  if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
  const form=await request.formData(),file=form.get("file"),year=Number(form.get("year")||2026),month=Number(form.get("month")||0);
  if(!(file instanceof File)||month<1||month>12)return NextResponse.json({error:"Seleccione un archivo y un período válidos."},{status:400});
  const text=(await file.text()).replace(/^\uFEFF/,""),lines=text.split(/\r?\n/).filter(line=>line.trim());
  if(lines.length<2)return NextResponse.json({error:"El archivo de nómina está vacío."},{status:400});
  const headers=lines[0].split("\t").map(clean),required=["Fondo","Programa2","Sub-Producto","Actividad","Empleado","Apellido","Cédula","Salario Mensual"];
  if(required.some(header=>!headers.includes(header)))return NextResponse.json({error:"El archivo no posee las columnas requeridas de la nómina."},{status:400});
  const value=(cells:string[],name:string)=>cells[headers.indexOf(name)];
  const rows=lines.slice(1).map(line=>{const cells=line.split("\t");return {
    execution_fund:clean(value(cells,"Fondo")),program:numberValue(value(cells,"Programa2")),subproduct:numberValue(value(cells,"Sub-Producto")),activity:numberValue(value(cells,"Actividad")),
    first_names:clean(value(cells,"Empleado")),last_names:clean(value(cells,"Apellido")),gender:clean(value(cells,"Género")),birth_date:isoDate(value(cells,"Fecha Nacimiento")),age:numberValue(value(cells,"Edad")),document_number:clean(value(cells,"Cédula")),phone:clean(value(cells,"Teléfono")),academic_level:clean(value(cells,"Nivel Academico")),hire_date:isoDate(value(cells,"Fecha Entrada")),years_of_service:numberValue(value(cells,"Años de Servicio")),termination_date:isoDate(value(cells,"Fecha Salida")),termination_type:clean(value(cells,"Tipo de Salida")),bank_account:clean(value(cells,"Cuenta Banco")),position_name:clean(value(cells,"Cargo")),employee_group:clean(value(cells,"Grupo")),employment_status:clean(value(cells,"Estatus")).toUpperCase()==="FRIJO"?"FIJO":clean(value(cells,"Estatus")).toUpperCase(),direction_name:clean(value(cells,"Direccion")),department_name:clean(value(cells,"Departamento")),division_name:clean(value(cells,"Division")),section_name:clean(value(cells,"Seccion")),center_name:clean(value(cells,"Centro")),monthly_salary:numberValue(value(cells,"Salario Mensual"))
  };}).filter(row=>row.document_number&&row.first_names&&row.monthly_salary>0);
  if(rows.length!==lines.length-1)return NextResponse.json({error:`${lines.length-1-rows.length} registros están incompletos o poseen salario inválido.`},{status:400});
  if(new Set(rows.map(row=>row.document_number)).size!==rows.length)return NextResponse.json({error:"La nómina contiene cédulas duplicadas."},{status:400});
  const {data,error}=await authDatabase().rpc("import_hr_payroll_run",{p_token:token,p_year:year,p_month:month,p_source_name:file.name,p_rows:rows});
  if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible importar la nómina."},{status:400});
  return NextResponse.json(data);
}
