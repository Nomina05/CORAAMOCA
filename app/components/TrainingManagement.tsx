"use client";
import { useCallback, useEffect, useMemo, useState } from "react";
import SearchableEmployeeSelect from "./SearchableEmployeeSelect";
type Employee = {
  id: string;
  employee_code: string;
  full_name: string;
  position_name: string;
  direction_name: string;
  department_name: string;
};
type Need = {
  id: string;
  topic: string;
  description: string;
  priority: string;
  status: string;
  source: string;
  employee_id?: string;
  full_name?: string;
  direction_name: string;
};
type Plan = {
  id: string;
  plan_year: number;
  name: string;
  budget_amount: number;
  status: string;
};
type Course = {
  id: string;
  title: string;
  provider: string;
  modality: string;
  start_date: string;
  end_date: string;
  hours: number;
  planned_cost: number;
  actual_cost: number;
  capacity: number;
  status: string;
  participant_count: number;
  approved_count: number;
  average_attendance: number;
  average_learning: number;
};
type Participant = {
  id: string;
  course_id: string;
  employee_id: string;
  employee_code: string;
  full_name: string;
  position_name: string;
  title: string;
  attendance_percent: number;
  learning_score: number;
  result: string;
  certificate_name: string;
  certificate_url: string;
};
type Indicators = {
  planned_courses: number;
  completed_courses: number;
  planned_cost: number;
  actual_cost: number;
  participants: number;
  approved: number;
  average_attendance: number;
};
const money = (v: number) =>
  new Intl.NumberFormat("es-DO", { style: "currency", currency: "DOP" }).format(
    v || 0,
  );
export default function TrainingManagement({
  canManage = false,
  canApprove = false,
}: {
  canManage?: boolean;
  canApprove?: boolean;
}) {
  const [year, setYear] = useState(new Date().getFullYear()),
    [employees, setEmployees] = useState<Employee[]>([]),
    [needs, setNeeds] = useState<Need[]>([]),
    [plans, setPlans] = useState<Plan[]>([]),
    [courses, setCourses] = useState<Course[]>([]),
    [participants, setParticipants] = useState<Participant[]>([]),
    [indicators, setIndicators] = useState<Indicators>({
      planned_courses: 0,
      completed_courses: 0,
      planned_cost: 0,
      actual_cost: 0,
      participants: 0,
      approved: 0,
      average_attendance: 0,
    }),
    [selectedCourse, setSelectedCourse] = useState(""),
    [employeeId, setEmployeeId] = useState(""),
    [message, setMessage] = useState(""),
    [loading, setLoading] = useState(true);
  const load = useCallback(async () => {
    setLoading(true);
    const r = await fetch(`/api/hr/training?year=${year}`, {
        cache: "no-store",
      }),
      d = await r.json();
    if (r.ok) {
      setEmployees(d.employees || []);
      setNeeds(d.needs || []);
      setPlans(d.plans || []);
      setCourses(d.courses || []);
      setParticipants(d.participants || []);
      setIndicators(d.indicators || {});
      setSelectedCourse((x) =>
        (d.courses || []).some((c: Course) => c.id === x)
          ? x
          : d.courses?.[0]?.id || "",
      );
      setMessage("");
    } else setMessage(d.error);
    setLoading(false);
  }, [year]);
  useEffect(() => {
    load();
  }, [load]);
  async function act(action: string, data: Record<string, string>) {
    setLoading(true);
    const r = await fetch("/api/hr/training", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action, data }),
      }),
      d = await r.json();
    setMessage(r.ok ? "Capacitación actualizada correctamente." : d.error);
    if (r.ok) await load();
    else setLoading(false);
  }
  function need() {
    const employee_id =
        prompt(
          "ID del empleado (opcional; puede dejarlo vacío para necesidad de unidad):",
          "",
        ) || "",
      topic = prompt("Tema o necesidad detectada:", ""),
      description = (topic && prompt("Descripción:", "")) || "",
      priority =
        prompt(
          "Prioridad: BAJA, MEDIA, ALTA o CRITICA",
          "MEDIA",
        )?.toUpperCase() || "MEDIA";
    if (topic)
      act("NECESIDAD", {
        year: String(year),
        employee_id,
        topic,
        description,
        priority,
        source: "MANUAL",
        direction_name: "",
        department_name: "",
      });
  }
  function plan() {
    const name = prompt(
        "Nombre del plan anual:",
        `Plan anual de capacitación ${year}`,
      ),
      budget_amount = name && prompt("Presupuesto anual:", "0"),
      objectives = prompt("Objetivos del plan:", "") || "";
    if (name && budget_amount !== null)
      act("PLAN", { year: String(year), name, budget_amount, objectives });
  }
  function addCourse() {
    const title = prompt("Nombre del curso:", ""),
      provider = (title && prompt("Proveedor o facilitador:", "")) || "",
      start_date = prompt("Fecha inicial (AAAA-MM-DD):", `${year}-01-01`),
      end_date = prompt(
        "Fecha final (AAAA-MM-DD):",
        start_date || `${year}-01-01`,
      ),
      planned_cost = prompt("Costo planificado:", "0") || "0",
      hours = prompt("Cantidad de horas:", "0") || "0",
      capacity = prompt("Capacidad:", "0") || "0",
      need_id = needs.find((n) => n.status === "DETECTADA")?.id || "";
    if (title && start_date && end_date)
      act("CURSO", {
        year: String(year),
        title,
        provider,
        start_date,
        end_date,
        planned_cost,
        hours,
        capacity,
        need_id,
        modality: "PRESENCIAL",
      });
  }
  function result(p: Participant) {
    const attendance_percent = prompt(
        "Porcentaje de asistencia:",
        String(p.attendance_percent || 0),
      ),
      learning_score = prompt(
        "Evaluación de aprendizaje (0-100):",
        String(p.learning_score || 0),
      ),
      result = prompt(
        "Resultado: APROBADO, REPROBADO, AUSENTE o RETIRADO",
        p.result,
      )?.toUpperCase();
    if (attendance_percent !== null && learning_score !== null && result)
      act("RESULTADO", {
        participant_id: p.id,
        attendance_percent,
        learning_score,
        result,
        observations: "",
      });
  }
  function certificate(p: Participant) {
    const certificate_name = prompt(
        "Nombre del certificado:",
        p.certificate_name || `Certificado - ${p.title}`,
      ),
      certificate_url =
        certificate_name &&
        prompt("Enlace protegido del certificado:", p.certificate_url || "");
    if (certificate_name && certificate_url)
      act("CERTIFICADO", {
        participant_id: p.id,
        certificate_name,
        certificate_url,
        certificate_date: new Date().toISOString().slice(0, 10),
      });
  }
  const course = useMemo(
      () => courses.find((c) => c.id === selectedCourse),
      [courses, selectedCourse],
    ),
    roster = participants.filter((p) => p.course_id === selectedCourse),
    execution = Number(indicators.planned_cost)
      ? (Number(indicators.actual_cost) / Number(indicators.planned_cost)) * 100
      : 0;
  return (
    <section className="employee-registry-panel training-management">
      <div className="direction-strip">
        <strong>DIRECCIÓN RESPONSABLE</strong>
        <span>Dirección de Recursos Humanos · Formación y desarrollo</span>
      </div>
      <div className="employee-registry-head">
        <div>
          <span className="eyebrow">CAPACITACIÓN</span>
          <h2>Plan anual y ejecución {year}</h2>
          <p>
            Necesidades, cursos, participantes, costos, asistencia, aprendizaje
            y certificados.
          </p>
        </div>
        <div>
          <select value={year} onChange={(e) => setYear(+e.target.value)}>
            {Array.from({ length: 8 }, (_, i) => 2025 + i).map((y) => (
              <option key={y}>{y}</option>
            ))}
          </select>
          {canManage && (
            <button className="outline" onClick={need}>
              ＋ Necesidad
            </button>
          )}
          {canManage && (
            <button className="primary" onClick={plans.length ? addCourse : plan}>
              {plans.length ? "＋ Curso" : "Crear plan anual"}
            </button>
          )}
        </div>
      </div>
      {message && <div className="form-message">{message}</div>}
      <div className="technical-kpis">
        <article>
          <span>EJECUCIÓN DEL PLAN</span>
          <strong>
            {indicators.completed_courses}/{indicators.planned_courses}
          </strong>
        </article>
        <article>
          <span>COSTO EJECUTADO</span>
          <strong>{money(Number(indicators.actual_cost))}</strong>
          <small>{execution.toFixed(1)}% del plan</small>
        </article>
        <article>
          <span>PARTICIPANTES</span>
          <strong>{indicators.participants}</strong>
        </article>
        <article>
          <span>ASISTENCIA PROMEDIO</span>
          <strong>
            {Number(indicators.average_attendance || 0).toFixed(1)}%
          </strong>
        </article>
      </div>
      <div className="training-summary">
        <article>
          <h3>Necesidades detectadas</h3>
          <strong>
            {needs.filter((n) => n.status === "DETECTADA").length}
          </strong>
          <span>
            {
              needs.filter(
                (n) =>
                  ["ALTA", "CRITICA"].includes(n.priority) &&
                  n.status === "DETECTADA",
              ).length
            }{" "}
            prioritarias
          </span>
        </article>
        <article>
          <h3>Presupuesto anual</h3>
          <strong>{money(Number(plans[0]?.budget_amount || 0))}</strong>
          <span>{plans[0]?.status || "Sin plan"}</span>
          {canApprove && plans[0]?.status === "BORRADOR" && (
            <button
              className="row-action"
              onClick={() => act("APROBAR_PLAN", { plan_id: plans[0].id })}
            >
              Aprobar plan
            </button>
          )}
        </article>
        <article>
          <h3>Aprendizaje aprobado</h3>
          <strong>{indicators.approved}</strong>
          <span>de {indicators.participants} participantes</span>
        </article>
      </div>
      <div className="training-layout">
        <aside className="technical-card training-course-list">
          <h3>Cursos del plan</h3>
          {courses.map((c) => (
            <button
              key={c.id}
              className={selectedCourse === c.id ? "is-selected" : ""}
              onClick={() => setSelectedCourse(c.id)}
            >
              <strong>{c.title}</strong>
              <span>
                {new Date(`${c.start_date}T12:00`).toLocaleDateString("es-DO")}{" "}
                · {c.status}
              </span>
              <small>
                {c.participant_count}/{c.capacity || "∞"} participantes
              </small>
            </button>
          ))}
        </aside>
        <div className="technical-card">
          {!course ? (
            <div className="technical-empty">
              <strong>Sin cursos planificados</strong>
              <span>Cree el plan anual y registre el primer curso.</span>
            </div>
          ) : (
            <>
              <div className="training-course-head">
                <div>
                  <span>CURSO PLANIFICADO</span>
                  <h2>{course.title}</h2>
                  <p>
                    {course.provider || "Facilitador no indicado"} ·{" "}
                    {course.hours} horas · {course.modality}
                  </p>
                </div>
                <div>
                  <strong>
                    {money(Number(course.actual_cost || course.planned_cost))}
                  </strong>
                  <small>
                    Asistencia {course.average_attendance}% · Aprendizaje{" "}
                    {course.average_learning}
                  </small>
                </div>
              </div>
              {canManage && course.status !== "FINALIZADO" && (
                <div className="training-enroll">
                  <SearchableEmployeeSelect
                    employees={employees}
                    value={employeeId}
                    onChange={setEmployeeId}
                    label="Participante"
                  />
                  <button
                    className="primary"
                    disabled={!employeeId || loading}
                    onClick={() =>
                      act("PARTICIPANTE", {
                        course_id: course.id,
                        employee_id: employeeId,
                      })
                    }
                  >
                    Inscribir
                  </button>
                  <button
                    className="outline"
                    onClick={() =>
                      act("FINALIZAR_CURSO", {
                        course_id: course.id,
                        actual_cost:
                          prompt(
                            "Costo real del curso:",
                            String(course.planned_cost),
                          ) || "0",
                      })
                    }
                  >
                    Finalizar curso
                  </button>
                </div>
              )}
              <div className="users-table-wrap">
                <table className="employee-registry-table">
                  <thead>
                    <tr>
                      <th>PARTICIPANTE</th>
                      <th>ASISTENCIA</th>
                      <th>APRENDIZAJE</th>
                      <th>RESULTADO</th>
                      <th>CERTIFICADO</th>
                      {canManage && <th>ACCIONES</th>}
                    </tr>
                  </thead>
                  <tbody>
                    {roster.map((p) => (
                      <tr key={p.id}>
                        <td>
                          <strong>{p.full_name}</strong>
                          <small>
                            {p.employee_code} · {p.position_name}
                          </small>
                        </td>
                        <td>{p.attendance_percent}%</td>
                        <td>{p.learning_score ?? "—"}</td>
                        <td>
                          <span className="vacancy-decision">{p.result}</span>
                        </td>
                        <td>
                          {p.certificate_url ? (
                            <a
                              href={p.certificate_url}
                              target="_blank"
                              rel="noreferrer"
                            >
                              {p.certificate_name}
                            </a>
                          ) : (
                            "Pendiente"
                          )}
                        </td>
                        {canManage && (
                          <td>
                            <button
                              className="row-action"
                              onClick={() => result(p)}
                            >
                              Resultado
                            </button>
                            <button
                              className="row-action"
                              onClick={() => certificate(p)}
                            >
                              Certificado
                            </button>
                          </td>
                        )}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </>
          )}
        </div>
      </div>
      <div className="technical-card training-history">
        <h2>Historial de capacitación por empleado</h2>
        <div className="users-table-wrap">
          <table className="employee-registry-table">
            <thead>
              <tr>
                <th>EMPLEADO</th>
                <th>CURSO</th>
                <th>ASISTENCIA</th>
                <th>CALIFICACIÓN</th>
                <th>RESULTADO</th>
              </tr>
            </thead>
            <tbody>
              {participants.map((p) => (
                <tr key={`history-${p.id}`}>
                  <td>
                    {p.full_name}
                    <small>{p.employee_code}</small>
                  </td>
                  <td>{p.title}</td>
                  <td>{p.attendance_percent}%</td>
                  <td>{p.learning_score ?? "—"}</td>
                  <td>{p.result}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </section>
  );
}
