# Checklist — App móvil Vexi (`vexi_movil`)

Qué tiene la app frente a lo que ya existe en la web. Cada sección sigue la
numeración de `../CHECKLIST-VEXI.md`.

**Leyenda:** `[x]` hecho en la app · `[ ]` falta · 🖥️ solo web, a propósito
(tareas de escritorio que no tienen sentido en el teléfono).
**API:** lo que haría falta agregar en `vexi_web/routes/api.php` para cada
pendiente. Una regla de la arquitectura: la app nunca decide permisos; el
servidor revalida todo.

Última revisión: 12/11/2026.

---

## Base técnica

- [x] Login con token Sanctum (vence a los 90 días)
- [x] Selector de veterinaria (`X-Company-Id`) y cambio desde el drawer o el perfil
- [x] Menú según `permissions` y `plan.features` de `GET /me`
- [x] Errores con código (`company_required`, `permission_denied`, `plan_module_missing`, `subscription_inactive`, `subscription_grace_readonly`)
- [x] Token en almacenamiento seguro; sesión vencida → vuelve al login con aviso
- [x] Sin conexión → pantalla de reintento (no cierra la sesión)
- [x] Drawer con todas las secciones, agrupadas; barra inferior con Inicio, Agenda y Pacientes
- [x] Identificador `com.sczsoft.vexi` (Android e iOS)
- [x] Ícono de la app con el dibujo del logo (sin el texto), adaptable en Android — `dart run flutter_launcher_icons`
- [x] Logo en el login; el de la veterinaria (o el de Vexi si no subió uno) en el drawer
- [ ] Pantalla de arranque (splash) con la marca Vexi
- [ ] Modo sin conexión (ver datos ya cargados sin internet)
- [ ] Actualización forzada cuando la API cambie de versión (`/api/v1` → `/v2`)
- [ ] Compilación de producción firmada (Play Store / App Store)

## 1. Dashboard

- [x] Resumen del día: citas, en espera, internados
- [x] «Requiere atención» con acceso a la sección que lo resuelve
- [x] Próximas citas del día
- [x] Indicadores económicos del día y del mes (para dueños y gerentes): cobrado hoy, el mes comparado con los mismos días del anterior y lo que te deben
- [ ] Accesos rápidos en el inicio (nuevo cliente, nueva cita, nueva consulta) — hoy están en Pacientes, Agenda y la ficha

## 2. Clientes y mascotas

- [x] Buscar mascotas (nombre, microchip, propietario)
- [x] Ficha: datos, precauciones clínicas, historial de peso, próximas citas
- [x] Propietario con llamar y WhatsApp
- [x] Historial de consultas y expediente
- [x] Historial de vacunas y desparasitaciones
- [x] Registrar propietario («Guardar y registrar mascota», como en la web; WhatsApp = mismo teléfono por defecto)
- [x] Registrar mascota (especie, raza, sexo, nacimiento, peso inicial al historial)
- [x] Editar propietario y mascota (un peso nuevo va al historial)
- [x] Foto de la mascota con la cámara o la galería (reducida en el teléfono; cambiar o quitar)
- [x] Buscar y ver propietarios con sus mascotas y su saldo pendiente (si la veterinaria vende y el rol puede verlo)
- [x] Compartir el carnet sanitario (PDF por WhatsApp; también «PDF» en la ficha web)
- [x] Historial de laboratorio en la ficha (pestaña «Laboratorio» con «Solicitar estudio»)
- [x] Historial de hospitalizaciones en la ficha (pestaña «Internaciones» con «Internar»)

## 3. Agenda y citas

- [x] Citas del día con flechas y calendario; «solo mis citas»
- [x] Detalle de la cita
- [x] Confirmar, llegó, iniciar, finalizar, no asistió, cancelar
- [x] Atender: abrir la consulta desde la cita
- [x] Agendar una cita desde la agenda o la ficha del paciente (servicio con su duración, profesional, choque de horario)
- [x] Reprogramar (fecha, hora, duración, servicio o profesional) con aviso al profesional
- [ ] Vista semanal
- [x] Recordatorio por WhatsApp con mensaje prellenado (como en la web)
- [x] Sala de espera: orden de llegada y tiempo esperando, en atención, por llegar hoy con «Llegó», paciente sin cita y asignar profesional (se actualiza cada 30 s)

## 4. Consultas

- [x] Nueva consulta desde la ficha del paciente
- [x] Evaluación clínica: motivo, anamnesis, examen físico, notas
- [x] Signos vitales: temperatura, peso, frecuencias, hidratación, mucosas, condición corporal
- [x] Diagnósticos (principal, secundario, diferencial) con sugerencias
- [x] Tratamiento y receta: medicamento, presentación, dosis, vía, frecuencia, duración, cantidad
- [x] Indicaciones, recomendaciones y próxima revisión
- [x] Guardar borrador, finalizar (exige diagnóstico principal) y aviso al salir sin guardar
- [x] Seguimiento de una consulta finalizada
- [x] Procedimientos (nombre, descripción, materiales, quién lo hizo, costo)
- [x] Insumos del inventario usados (se descuentan al finalizar)
- [x] Vincular un medicamento de la receta a un producto del inventario (buscador)
- [x] Compartir la receta en PDF (A5, ~25 KB) por WhatsApp, correo o lo que tenga el teléfono
- [x] Dispensar la receta (propone la cantidad recetada; no entrega sin stock)
- [x] Descartar un borrador
- [x] Sección «Consultas»: en curso para retomarlas y revisiones pendientes con «Agendar revisión» (filtro «Mías»)
- [x] Al finalizar abre el expediente, listo para compartir la receta

## 5. Vacunas y desparasitaciones

- [x] Atrasadas y próximas
- [x] Registrar vacuna (la próxima dosis la calcula el servidor; descuenta stock)
- [x] Historial en la ficha
- [x] Registrar desparasitación (interna, externa o ambas; producto con sugerencias o del inventario; peso actual propuesto)
- [x] Próxima aplicación automática, con fecha elegida o sin programar
- [x] Corregir o eliminar una vacuna o desparasitación (lo descontado vuelve al stock)
- [x] Recordatorio por WhatsApp al propietario (mensaje prellenado, el mismo de la web) en pendientes y en la ficha
- [x] Carnet sanitario en PDF para compartir

## 6. Laboratorio

- [x] Sección «Laboratorio»: pendientes, por entregar y todos; búsqueda y «Míos»
- [x] Ver resultados en la ficha y en la consulta, con alerta de valores fuera de rango (Bajo / Alto)
- [x] Ver los adjuntos: fotos con zoom; los PDF se abren con lo que tenga el teléfono
- [x] Solicitar uno o varios estudios desde la consulta, la ficha o la sección (laboratorio externo, indicaciones)
- [x] Cargar resultados con la referencia de cada parámetro y aviso de rango al escribir; borrador o completar
- [x] Fotografiar y adjuntar el informe de un laboratorio externo (cámara o galería); quitar adjuntos
- [x] En proceso, entregado al propietario y anular con motivo
- [x] Informe en PDF para compartir por WhatsApp (también «Descargar PDF» en la web)
- 🖥️ Catálogo de estudios y sus parámetros de referencia; cobrar el estudio en caja

## 7. Farmacia e inventario

- [x] Buscar productos y medicamentos (nombre, código, marca)
- [x] Stock total, por sucursal y por lote
- [x] Filtros: stock bajo y agotados
- [x] Vencidos y por vencer
- [x] Buscar escaneando el código de barras con la cámara (o escribiéndolo; linterna)
- [x] Conteo físico rápido: escanear, contar y «Guardar y escanear otro»; por lote si el producto los lleva
- [x] Entradas (con lote y vencimiento) y salidas (merma, consumo interno…)
- [x] Kardex del producto con el saldo después de cada movimiento
- 🖥️ Alta y edición de productos (y su código de barras) y categorías, transferencias entre sucursales

## 8. Compras y proveedores

- [ ] Recibir mercadería (marcar lo que llegó, lote y vencimiento) — útil en el depósito con el teléfono
- 🖥️ Proveedores, órdenes de compra, cuentas por pagar

## 9. Ventas y caja

- [x] Cuentas por cobrar: deudores (vencido primero en rojo), recordatorio por WhatsApp, cobros recientes
- [x] Ver lo que debe un cliente venta por venta y registrar un abono (método, referencia, caja abierta) con recibo por WhatsApp
- [ ] Cobrar una consulta o servicio rápido (POS simple) — API: `POST /sales`
- [ ] Finanzas: gastos en pestañas (Gastos · Proveedores · Personal · Servicios) con el origen del dinero y anulación — API: `/finance/options`, `/finance/expenses` (acepta `receipt`)
- [ ] Finanzas: control del mes de servicios básicos — API: `GET /finance/basics?month=`
- [ ] Finanzas: cuentas con su extracto, ingreso / egreso y transferencia — API: `/finance/accounts`
- [ ] Mis comisiones (cada profesional, lo suyo) — API: `GET /me/commissions`
- [ ] Comisiones por pagar y liquidar — API: `/commissions/pending`, `POST /commissions/professionals/{id}/settle`
- 🖥️ POS completo, apertura, arqueo y cierre de caja, anulaciones y devoluciones

## 10. Hospitalización

- [x] Internados (críticos primero, tomas atrasadas)
- [x] Tomas por aplicar: aplicar u omitir con motivo (descuenta stock)
- [x] Tratamientos programados
- [x] Evolución, signos vitales, alimentación, hidratación, cuidados e incidencias
- [x] Cambiar el estado clínico (tocando el estado o al registrar la evolución)
- [x] Indicar un tratamiento (cada 4–24 h, por 1–10 días, con producto del inventario) o suspenderlo
- [x] Ingresar un paciente desde la sección, la ficha o la consulta (motivo y diagnóstico propuestos)
- [x] Dar el alta o registrar el fallecimiento; anular un ingreso cargado por error
- [x] Mover de jaula o espacio (solo los libres)
- 🖥️ Costos y cargos de la internación, informe imprimible

## 11. Servicios adicionales (peluquería, guardería…)

- [ ] Agenda de servicios — pendiente también en la web (§11.3)

## 12. Personal y usuarios

- [x] Datos del usuario y cambio de contraseña (cierra las otras sesiones)
- [ ] Perfil profesional (matrícula, especialidad, firma con el dedo) — API: `PUT /me/professional`
- 🖥️ Usuarios, roles y permisos

## 13. Reportes

- [x] Resumen para el dueño: ingresos, utilidad, ventas y consultas del período con comparación, lo más vendido, cómo te pagaron y en qué se gastó
- 🖥️ Reportes detallados y exportación a Excel

## 14. Notificaciones

- [x] Campana dentro de la app: pendientes en vivo y novedades con leído / no leído
- [x] Abrir la cita desde la novedad
- [ ] **Notificaciones push** (Firebase Cloud Messaging) — API: `POST /devices` para registrar el teléfono y envío desde `Notifier`
- [x] Abrir los resultados de laboratorio desde la novedad «Resultados listos»
- [ ] Abrir ventas desde la novedad
- [ ] Preferencias: qué avisos recibir por push

## 15–18. Configuración, suscripción y superadmin

- [x] Ver plan y estado de la suscripción (perfil y drawer)
- [x] Aviso de solo lectura cuando la suscripción venció
- 🖥️ Configuración de la veterinaria, administración de la suscripción y panel SCZSOFT

---

## Prioridad sugerida

1. ~~**Recepción desde el teléfono:** registrar propietario y mascota (con foto), agendar y reprogramar citas, sala de espera.~~ Hecho.
2. ~~**Completar la consulta:** procedimientos, insumos, receta en PDF compartible por WhatsApp, revisiones pendientes.~~ Hecho.
3. **Notificaciones push** (llegó el paciente, resultados listos, toma atrasada).
4. ~~**Laboratorio:** ver resultados y adjuntar fotos de informes.~~ Hecho.
5. ~~**Desparasitaciones** y recordatorios por WhatsApp.~~ Hecho.
6. ~~**Hospitalización completa:** ingreso, alta, tratamientos y estado clínico.~~ Hecho.
7. ~~**Inventario con cámara:** código de barras y conteo rápido.~~ Hecho.
8. ~~**Para el dueño:** resumen económico y cobro de deudas.~~ Hecho.
9. **Marca y publicación:** ícono, splash, firma de la app y tiendas.
