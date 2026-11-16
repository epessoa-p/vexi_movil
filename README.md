# Vexi móvil

App Flutter del SaaS veterinario Vexi. Habla con la API v1 de `../vexi_web`
(`/api/v1`, ver su README).

## Correr

```bash
flutter pub get
# Emulador Android contra el servidor local (php artisan serve en el puerto 8000):
flutter run
# Contra otro servidor:
flutter run --dart-define=API_URL=https://app.ejemplo.com/api/v1
```

Sin `API_URL` se usa `http://10.0.2.2:8000/api/v1` (el «localhost» de la
computadora visto desde el emulador). El tráfico `http://` solo está permitido
en depuración (`android/app/src/debug/AndroidManifest.xml`); en producción la
API debe ir por `https://`.

Usuarios demo: `vet@veterinariademo.test`, `admin@veterinariademo.test`
(contraseña `Admin@1234`).

## Qué hace

| Sección | Pantallas |
|---|---|
| Sesión | Login con token Sanctum, selector de veterinaria (`X-Company-Id`), sesión guardada en el almacenamiento seguro, aviso si el token vence |
| Inicio | Saludo, resumen del día, cobrado hoy y en el mes y lo que te deben (dueños y gerentes), «requiere atención» (lleva a la sección que lo resuelve), próximas citas, novedades sin leer |
| Agenda | Día con flechas y calendario, «solo mis citas», detalle con confirmar / llegó / iniciar / finalizar / no asistió / cancelar, llamar o WhatsApp al propietario |
| Navegación | Drawer con las mismas secciones y colores que el menú de la web (Principal azul, Clínica verde, Ventas naranja, Inventario violeta), usuario, veterinaria y cerrar sesión; barra inferior con Inicio, Agenda y Pacientes |
| Recepción | Propietario nuevo y su mascota (con foto de la cámara o la galería), editar ambos, agendar y reprogramar citas (avisa si el profesional ya está ocupado), sala de espera con orden de llegada, «Llegó», paciente sin cita y asignar profesional |
| Propietarios | Búsqueda, ficha con contacto, saldo pendiente (lleva a lo que debe) y mascotas |
| Pacientes | Búsqueda con paginación, ficha (precauciones, datos, pesos, próximas citas), historial y expediente de cada consulta, salud y laboratorio |
| Consultas | Nueva consulta desde la ficha o al atender una cita; evaluación, signos vitales, diagnósticos con sugerencias, receta (vinculable al inventario), procedimientos, insumos, indicaciones y próxima revisión; borrador, descartar, finalizar y seguimientos. Receta en PDF para compartir y dispensar. Sección con consultas en curso y revisiones pendientes |
| Laboratorio | Pendientes, por entregar y todos; solicitar uno o varios estudios desde la consulta o la ficha; cargar resultados con alerta de valores fuera de rango; fotografiar el informe externo; entregar o anular; informe en PDF para compartir |
| Vacunación | Atrasadas y próximas con recordatorio por WhatsApp; vacunar y desparasitar (próxima automática, elegida o sin programar); corregir y eliminar; carnet sanitario en PDF para compartir |
| Hospitalización | Internados (críticos primero); ingreso desde la sección, la ficha o la consulta; tomas por aplicar con aplicar / omitir; estado clínico, cambio de espacio, indicar y suspender tratamientos; evolución, cuidados y signos vitales; alta o fallecimiento y anulación; historial en la ficha |
| Inventario | Productos con stock y filtros (bajo, agotados), detalle por lote, vencimientos; buscar escaneando el código de barras; conteo físico encadenado con la cámara («Guardar y escanear otro»), entradas, salidas y kardex |
| Para el dueño | Resumen económico del período (ingresos, utilidad, ventas, consultas, lo más vendido, cómo te pagaron, gastos) comparado con el anterior; cuentas por cobrar con recordatorio por WhatsApp, lo que debe cada cliente y registrar abonos (con recibo por WhatsApp) |
| Perfil | Datos, cambiar de veterinaria, cambiar contraseña, notificaciones, cerrar sesión |

El menú se arma con `permissions` y `plan.features` de `GET /me`; el servidor
revalida todo igual. Los errores llegan con `code` (`permission_denied`,
`plan_module_missing`, `subscription_inactive`, …) y se muestran en español.

## Estructura

```
lib/
  core/      config, cliente HTTP (ApiException), modelos, sesión
  ui/        tema, formatos de fecha, piezas comunes (Loader, StatusChip…)
  screens/   una carpeta lógica por sección
tool/preview_main.dart   vista previa web para revisar pantallas (no se distribuye)
test/        cliente, sesión, login, drawer, consulta, recepción y laboratorio con un servidor simulado
```

## Pendiente

La lista completa, comparada con la web y con prioridades, está en [`CHECKLIST-MOVIL.md`](CHECKLIST-MOVIL.md). Lo principal:


- Notificaciones push (requiere Firebase Cloud Messaging y registrar el
  dispositivo en la API).
- Ícono y pantalla de inicio con la marca Vexi.
