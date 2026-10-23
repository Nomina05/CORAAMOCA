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
type RecordItem = {
  id: string;
  employee_id: string;
  employee_code: string;
  full_name: string;
  position_name: string;
  work_date: string;
  entry_at: string | null;
  exit_at: string | null;
  status: string;
  late_minutes: number;
  worked_minutes: number;
  justification: string;
  source: string;
  novelty_id: string | null;
  novelty_amount: number;
  novelty_status: string | null;
};
type Summary = {
  employee_id: string;
  employee_code: string;
  full_name: string;
  position_name: string;
  direction_name: string;
  work_records: number;
  present_count: number;
  late_count: number;
  late_minutes: number;
  justified_absences: number;
  unjustified_absences: number;
  worked_hours: number;
  alert_level: string;
};
type Indicators = {
  records: number;
  present: number;
  late: number;
  justified: number;
  unjustified: number;
  late_minutes: number;
};
const money = (v: number) =>
  new Intl.NumberFormat("es-DO", { style: "currency", currency: "DOP" }).format(
    v || 0,
  );
const months = [
  "Enero",
  "Febrero",
  "Marzo",
  "Abril",
  "Mayo",
  "Junio",
  "Julio",
  "Agosto",
  "Septiembre",
  "Octubre",
  "Noviembre",
  "Diciembre",
];
export default function AttendanceManagement({
  canManage = false,
  canApprove = false,
}: {
  canManage?: boolean;
  canApprove?: boolean;
}) {
  const today = new Date(),
    [year, setYear] = useState(today.getFullYear()),
    [month, setMonth] = useState(today.getMonth() + 1),
    [employees, setEmployees] = useState<Employee[]>([]),
    [records, setRecords] = useState<RecordItem[]>([]),
    [summary, setSummary] = useState<Summary[]>([]),
    [indicators, setIndicators] = useState<Indicators>({
      records: 0,
      present: 0,
      late: 0,
      justified: 0,
      unjustified: 0,
      late_minutes: 0,
    }),
    [employeeId, setEmployeeId] = useState(""),
    [open, setOpen] = useState(false),
    [message, setMessage] = useState(""),
    [loading, setLoading] = useState(true),
    [query, setQuery] = useState("");
  const load = useCallback(async () => {
    setLoading(true);
    const r = await fetch(`/api/hr/attendance?year=${year}&month=${month}`, {
        cache: "no-store",
      }),
      d = await r.json();
    if (r.ok) {
      setEmployees(d.employees || []);
      setRecords(d.records || []);
      setSummary(d.summary || []);
      setIndicators(d.indicators || {});
      setMessage("");
    } else setMessage(d.error);
    setLoading(false);
  }, [year, month]);
  useEffect(() => {
    load();
  }, [load]);
  async function act(action: string, data: Record<string, string>) {
    setLoading(true);
    const r = await fetch("/api/hr/attendance", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action, data }),
      }),
      d = await r.json();
    setMessage(r.ok ? "Asistencia actualizada correctamente." : d.error);
    if (r.ok) {
      setOpen(false);
      await load();
    } else setLoading(false);
  }
  function save(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const data = Object.fromEntries(
      new FormData(e.currentTarget).entries(),
    ) as Record<string, string>;
    act("REGISTRAR", {
      ...data,
      employee_id: employeeId,
      source: "MANUAL",
      entry_at: data.entry_at
        ? `${data.work_date}T${data.entry_at}:00-04:00`
        : "",
      exit_at: data.exit_at ? `${data.work_date}T${data.exit_at}:00-04:00` : "",
    });
  }
  const filtered = useMemo(
      () =>
        records.filter((r) =>
          `${r.full_name} ${r.employee_code} ${r.status}`
            .toLowerCase()
            .includes(query.toLowerCase()),
        ),
      [records, query],
    ),
    alerts = summary.filter((s) => s.alert_level !== "NORMAL");
  return (
    <section className="employee-registry-panel attendance-management">
      <div className="direction-strip">
        <strong>DIRECCIÓN RESPONSABLE</strong>
        <span>Dirección de Recursos Humanos · Asistencia y puntualidad</span>
      </div>
      <div className="employee-registry-head">
        <div>
          <span className="eyebrow">CONTROL DE ASISTENCIA</span>
          <h2>
            Resumen mensual de {months[month - 1]} {year}
          </h2>
          <p>
            Entradas, salidas, tardanzas, ausencias, reincidencias y novedades
            para nómina.
          </p>
        </div>
        <div>
          <select value={year} onChange={(e) => setYear(+e.target.value)}>
            {Array.from({ length: 8 }, (_, i) => 2025 + i).map((y) => (
              <option key={y}>{y}</option>
            ))}
          </select>
          <select value={month} onChange={(e) => setMonth(+e.target.value)}>
            {months.map((m, i) => (
              <option value={i + 1} key={m}>
                {m}
              </option>
            ))}
          </select>
          {canManage && (
            <button className="primary" onClick={() => setOpen(true)}>
              ＋ Registrar asistencia
            </button>
          )}
        </div>
      </div>
      {message && <div className="form-message">{message}</div>}
      <div className="technical-kpis">
        <article>
          <span>REGISTROS</span>
          <strong>{indicators.records || 0}</strong>
        </article>
        <article>
          <span>TARDANZAS</span>
          <strong>{indicators.late || 0}</strong>
          <small>{indicators.late_minutes || 0} minutos</small>
        </article>
        <article>
          <span>AUSENCIAS JUSTIFICADAS</span>
          <strong>{indicators.justified || 0}</strong>
        </article>
        <article>
          <span>NO JUSTIFICADAS</span>
          <strong>{indicators.unjustified || 0}</strong>
        </article>
      </div>
      {open && (
        <form className="attendance-form" onSubmit={save}>
          <SearchableEmployeeSelect
            employees={employees}
            value={employeeId}
            onChange={setEmployeeId}
            required
          />
          <label>
            Fecha
            <input
              name="work_date"
              type="date"
              defaultValue={today.toISOString().slice(0, 10)}
              required
            />
          </label>
          <label>
            Estado
            <select name="status">
              <option value="PRESENTE">Presente</option>
              <option value="AUSENCIA_JUSTIFICADA">Ausencia justificada</option>
              <option value="AUSENCIA_NO_JUSTIFICADA">
                Ausencia no justificada
              </option>
              <option value="LICENCIA">Licencia</option>
              <option value="VACACIONES">Vacaciones</option>
              <option value="FERIADO">Feriado</option>
            </select>
          </label>
          <label>
            Entrada programada
            <input name="scheduled_entry" type="time" defaultValue="08:00" />
          </label>
          <label>
            Salida programada
            <input name="scheduled_exit" type="time" defaultValue="16:00" />
          </label>
          <label>
            Entrada real
            <input name="entry_at" type="time" />
          </label>
          <label>
            Salida real
            <input name="exit_at" type="time" />
          </label>
          <label>
            Justificación
            <input name="justification" />
          </label>
          <label>
            Documento
            <input
              name="document_url"
              placeholder="Enlace protegido (opcional)"
            />
          </label>
          <button className="primary" disabled={!employeeId || loading}>
            Guardar
          </button>
          <button
            type="button"
            className="outline"
            onClick={() => setOpen(false)}
          >
            Cancelar
          </button>
        </form>
      )}
      <div className="attendance-grid">
        <article className="technical-card">
          <div className="users-card-head">
            <div>
              <h2>Alertas por reincidencia</h2>
              <p>
                Dos ausencias no justificadas o tres tardanzas elevan la alerta.
              </p>
            </div>
          </div>
          <div className="attendance-alerts">
            {alerts.map((s) => (
              <div className={s.alert_level.toLowerCase()} key={s.employee_id}>
                <b>{s.alert_level}</b>
                <strong>{s.full_name}</strong>
                <span>
                  {s.late_count} tardanzas · {s.unjustified_absences} ausencias
                  no justificadas
                </span>
              </div>
            ))}
            {!alerts.length && <p>Sin reincidencias para el período.</p>}
          </div>
        </article>
        <article className="technical-card">
          <div className="users-card-head">
            <div>
              <h2>Resumen por empleado</h2>
              <p>Horas, puntualidad y ausencias del mes.</p>
            </div>
          </div>
          <div className="users-table-wrap">
            <table className="employee-registry-table">
              <thead>
                <tr>
                  <th>EMPLEADO</th>
                  <th>PRESENTE</th>
                  <th>TARDANZAS</th>
                  <th>AUSENCIAS</th>
                  <th>HORAS</th>
                </tr>
              </thead>
              <tbody>
                {summary
                  .filter((s) => s.work_records > 0)
                  .map((s) => (
                    <tr key={s.employee_id}>
                      <td>
                        {s.full_name}
                        <small>{s.employee_code}</small>
                      </td>
                      <td>{s.present_count}</td>
                      <td>
                        {s.late_count}
                        <small>{s.late_minutes} min.</small>
                      </td>
                      <td>
                        {s.justified_absences} / {s.unjustified_absences}
                        <small>Justificadas / no justificadas</small>
                      </td>
                      <td>{s.worked_hours}</td>
                    </tr>
                  ))}
              </tbody>
            </table>
          </div>
        </article>
      </div>
      <div className="technical-card">
        <div className="users-card-head">
          <div>
            <h2>Detalle de marcaciones</h2>
            <p>Preparado para integración futura mediante origen BIOMÉTRICO.</p>
          </div>
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Buscar empleado o estado"
          />
        </div>
        <div className="users-table-wrap">
          <table className="employee-registry-table">
            <thead>
              <tr>
                <th>FECHA / EMPLEADO</th>
                <th>ENTRADA / SALIDA</th>
                <th>ESTADO</th>
                <th>TARDANZA</th>
                <th>JUSTIFICACIÓN</th>
                <th>NOVEDAD NÓMINA</th>
                {canManage && <th>ACCIONES</th>}
              </tr>
            </thead>
            <tbody>
              {filtered.map((r) => (
                <tr key={r.id}>
                  <td>
                    <strong>
                      {new Date(`${r.work_date}T12:00`).toLocaleDateString(
                        "es-DO",
                      )}
                    </strong>
                    <small>
                      {r.full_name} · {r.employee_code}
                    </small>
                  </td>
                  <td>
                    {r.entry_at
                      ? new Date(r.entry_at).toLocaleTimeString("es-DO", {
                          hour: "2-digit",
                          minute: "2-digit",
                        })
                      : "—"}
                    <small>
                      {r.exit_at
                        ? new Date(r.exit_at).toLocaleTimeString("es-DO", {
                            hour: "2-digit",
                            minute: "2-digit",
                          })
                        : "—"}
                    </small>
                  </td>
                  <td>
                    <span className="vacancy-decision">
                      {r.status.replaceAll("_", " ")}
                    </span>
                    <small>{r.source}</small>
                  </td>
                  <td>{r.late_minutes} min.</td>
                  <td>{r.justification || "—"}</td>
                  <td>
                    {r.novelty_id ? (
                      <>
                        <strong>{money(Number(r.novelty_amount))}</strong>
                        <small>{r.novelty_status}</small>
                      </>
                    ) : (
                      "No generada"
                    )}
                  </td>
                  {canManage && (
                    <td>
                      {["TARDANZA", "AUSENCIA_NO_JUSTIFICADA"].includes(
                        r.status,
                      ) &&
                        !r.novelty_id && (
                          <button
                            className="row-action"
                            onClick={() =>
                              act("GENERAR_NOVEDAD", { record_id: r.id })
                            }
                          >
                            Generar novedad
                          </button>
                        )}
                      {canApprove && r.novelty_status === "PENDIENTE" && (
                        <button
                          className="primary compact"
                          onClick={() =>
                            act("APROBAR_NOVEDAD", {
                              novelty_id: r.novelty_id || "",
                            })
                          }
                        >
                          Aprobar
                        </button>
                      )}
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </section>
  );
}
