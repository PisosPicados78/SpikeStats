# Product Backlog - Aplicación de Scouting de Voleibol

A continuación se presenta el Product Backlog priorizado para el desarrollo de la aplicación móvil de scouting y análisis estadístico de partidos de voleibol.

## Sprint 1: Estructura Base y Navegación
*El objetivo de este sprint es establecer las bases del proyecto, la arquitectura, navegación principal y los cimientos de la UI/UX.*

1. **HU-01: Estructura y Navegación Principal**
   - **Como** entrenador/usuario
   - **Quiero** poder navegar fácilmente entre las secciones de equipos, configuración de partidos, scouting en vivo y estadísticas
   - **Para** tener acceso rápido a las distintas funcionalidades desde un menú principal.

2. **HU-02: Interfaz de Scouting (Layout)**
   - **Como** entrenador/scouter
   - **Quiero** una pantalla de partido en vivo con botones grandes y accesibles
   - **Para** poder registrar acciones rápidamente sin equivocarme durante la presión de un partido.

## Futuros Sprints (Priorizados)

3. **HU-03: Registro de equipos y jugadores**
   - **Como** entrenador
   - **Quiero** crear equipos y registrar la información de mis jugadores (nombre, número, posición)
   - **Para** poder seleccionarlos durante los partidos.

4. **HU-04: Creación de partidos**
   - **Como** usuario
   - **Quiero** configurar un nuevo partido (equipo local, equipo visitante, fecha, torneo)
   - **Para** iniciar la recolección de estadísticas de un encuentro específico.

5. **HU-05: Control automático del marcador y sets**
   - **Como** scouter
   - **Quiero** que el marcador y los sets se actualicen automáticamente dependiendo de las acciones registradas (puntos ganados/perdidos)
   - **Para** no tener que llevar la cuenta mentalmente ni interrumpir mi labor.

6. **HU-06: Control de rotaciones**
   - **Como** entrenador
   - **Quiero** ver la rotación actual de mi equipo en cancha
   - **Para** saber qué jugador está en cada posición y registrar las acciones correctamente.

7. **HU-07: Registro de ataques**
   - **Como** scouter
   - **Quiero** registrar acciones de ataque (remate, finta) y su resultado (punto, error, en juego)
   - **Para** evaluar la efectividad ofensiva de mis jugadores.

8. **HU-08: Registro de defensas**
   - **Como** scouter
   - **Quiero** registrar acciones defensivas (recepción, excavación) y su calidad (perfecta, buena, error)
   - **Para** analizar el desempeño defensivo del equipo.

9. **HU-09: Registro de bloqueos**
   - **Como** scouter
   - **Quiero** registrar intentos y bloqueos exitosos
   - **Para** medir la capacidad del equipo de detener el ataque rival.

10. **HU-10: Registro de saques**
    - **Como** scouter
    - **Quiero** registrar saques y su resultado (ace, error, en juego)
    - **Para** evaluar la presión que el equipo ejerce desde el servicio.

11. **HU-11: Almacenamiento de acciones**
    - **Como** usuario
    - **Quiero** que todas las acciones del partido se guarden localmente en la base de datos (SQLite)
    - **Para** no perder la información si cierro la aplicación y poder consultarla posteriormente.

12. **HU-12: Generación de estadísticas individuales/colectivas**
    - **Como** entrenador
    - **Quiero** visualizar porcentajes de efectividad, puntos y errores por jugador y por equipo
    - **Para** tomar decisiones tácticas fundamentadas.

13. **HU-13: Consulta de información post-partido**
    - **Como** usuario
    - **Quiero** acceder a un historial de partidos finalizados y ver el resumen estadístico de cada uno
    - **Para** analizar el progreso del equipo a lo largo del tiempo.
