// Spanish strings. This file defines the shape every other locale must follow
// (see `Messages`), so a missing or misspelled key in en.ts fails `tsc`.

export const es = {
  /** BCP 47 tag, for <html lang> and date formatting. */
  tag: "es",

  common: {
    settingsEllipsis: "Ajustes…",
    cancel: "Cancelar",
    back: "Volver",
    save: "Guardar",
    ok: "OK",
    openConversation: "Abrir conversación",
    stored: "(guardada)",
    /** "3m" → "hace 3m"; "now" stays as it is. */
    now: "ahora",
    ago: (short: string) => `hace ${short}`,
  },

  header: {
    overview: "Resumen",
    ask: "Preguntar",
    drop: "Soltar",
    projects: "Proyectos",
    usage: "Uso",
    settings: "Ajustes",
    mute: "Silenciar",
  },

  overview: {
    open: "Abrir",
  },

  empty: {
    title: "Nada en marcha ahora mismo.",
    sub: "Suelta un archivo o una ventana, o pregúntame lo que quieras.",
    askClaude: "Preguntar a Claude",
  },

  approval: {
    needsPermission: "necesita permiso",
    queued: (total: number) => `necesita permiso · 1 de ${total}`,
    deny: "Denegar",
    allow: "Permitir",
  },

  question: {
    asking: "Claude Code te hace una pregunta",
    fallback: "Claude necesita una respuesta.",
    cantReply: "VoltaDock aún no puede responder por ti.",
  },

  error: {
    workflowStopped: "El workflow se detuvo.",
    usageLimit: "Alcanzaste el límite de uso.",
    sessionError: "La sesión se detuvo por un error.",
    noDetail: "Sin detalles disponibles.",
    retry: "Reintentar",
    openInN8n: "Abrir en n8n",
    continue: "Continuar",
  },

  finished: {
    who: "Claude Code terminó",
    fallback: "Sesión terminada",
  },

  confused: {
    title: "Demasiados golpes a la vez.",
    sub: "Dame un segundo: vuelvo al trabajo en tres segundos.",
  },

  projects: {
    title: "Proyectos",
    count: (n: number) => `${n} repos · clic para abrir Claude`,
    none: "No encuentro repositorios git. Elige la carpeta en Ajustes.",
    changes: (n: number) => `${n} cambio${n === 1 ? "" : "s"}`,
    clean: "limpio",
    rowTitle: "Abrir una sesión nueva de Claude en esta carpeta",
    more: (n: number) => `+${n} más`,
  },

  usage: {
    title: "Uso",
    sub: "estimado a precios de API",
    computing: "Calculando…",
    today: "Hoy",
    week: "7 días",
    tokens: "tokens",
    replies: (n: number) => `${n} respuestas`,
    /** Sunday first, like Date.getDay(). */
    weekdays: ["D", "L", "M", "X", "J", "V", "S"],
  },

  islandSettings: {
    sound: "Sonido",
    autoClose: (s: number) => `Cierre auto · ${s}s`,
  },

  placeholders: {
    mail: "El envío por correo no está en esta versión.",
    searching: "Claude está buscando…",
    result: "Resultado",
  },

  chat: {
    placeholder: "Pregúntame lo que quieras…",
    placeholderNext: "Continúa…",
    send: "Enviar",
  },

  upload: {
    dropHere: "Suelta tus archivos aquí",
    chips: ["PDF", "Imágenes", "Código", "Docs"],
    file: "archivo",
    fileCap: "Archivo",
    uploading: (name: string) => `Subiendo ${name}`,
    isReady: " está listo.",
    ready: (name: string) => `${name} está listo.`,
    whatToDo: "¿Qué quieres hacer con él?",
    ask: "Hacer una pregunta",
  },

  integrations: {
    integration: "Integración",
    hooksMissing: "Hooks no instalados",
    keyMissing: "Clave sin configurar",
    connectedLoading: "Conectado · cargando…",
    openVSCode: "Abrir Visual Studio Code",
    openN8n: "Abrir n8n",
    open: (name: string) => `Abrir ${name}`,
    refresh: "Actualizar",
    details: "Detalles",
    conversations: "Conversaciones",
    session: "Sesión",
    continueWhereLeft: "Continuar donde se quedó",
    deployments: "Despliegues",
    deployment: "Despliegue",
    ready: "Listo",
    canceled: "Cancelado",
    error: "Error",
    overview: "Resumen",
    totalStars: "Estrellas totales",
    repositories: "Repositorios",
    payments: "Pagos",
    payment: "Pago",
    untitled: "Sin título",
    recent: "Recientes",
    noCalls: "Sin llamadas programadas",
    meeting: "Reunión",
    schedule: "Agenda",
    success: "Éxito",
    failed: "Falló",
    completed: "Completado con éxito.",
    noErrorDetail: "Sin detalles del error.",
  },

  /** Why a conversation in the list is waiting for you. */
  sessionNotes: {
    permission: "Pide permiso",
    limit: "Límite alcanzado",
    answer: "Espera tu respuesta",
    error: "Se detuvo por un error",
  },

  steps: {
    failed: "⚠ falló",
    subagent: "+ subagente",
    subagentDone: "• subagente listo",
    usageLimit: "Límite de uso alcanzado",
    /** Tool name → verb shown in the ticker. Unknown tools show their own name. */
    tools: {
      Bash: "Ejecuta",
      Read: "Lee",
      Write: "Escribe",
      Edit: "Edita",
      Glob: "Busca",
      Grep: "Busca",
      WebSearch: "Búsqueda web",
      WebFetch: "Descarga",
      TodoWrite: "Tareas",
      Task: "Agente",
      LS: "Lista",
      MultiEdit: "Edita",
      NotebookEdit: "Notebook",
      PowerShell: "Ejecuta",
    } as Record<string, string>,
  },

  today: {
    name: "Hoy",
    settingsNote: "Enfoque de 25 min, tareas y recordatorios. Se guarda solo en este PC.",
    addPlaceholder: "Tarea, o «en 10 min estirar»",
    clearDone: "Borrar hechas",
    back: "Volver",
    remove: "Quitar",
    added: "Añadido",
    pending: (n: number) => `${n} pendiente${n === 1 ? "" : "s"}`,
    next: (when: string) => `próximo ${when}`,
    nothingPlanned: "Nada previsto",
    focus: "Enfoque",
    blocksToday: (n: number) => `${n} bloque${n === 1 ? "" : "s"} hoy`,
    paused: "En pausa",
    rest: "Descanso",
    start: "Empezar",
    resume: "Seguir",
    pause: "Pausa",
    skip: "Saltar",
    empty: "Nada todavía. Escribe una tarea, o «a las 9 llamar a Ana».",
    missed: (when: string) => `te lo perdiste mientras no estabas · ${when}`,
    reminder: (when: string) => `recordatorio · ${when}`,
    focusDone: (n: number) => `bloque de enfoque terminado · ${n} hoy`,
    restDone: "se acabó el descanso",
    focusDoneTitle: "Buen trabajo. Toca un descanso corto.",
    restDoneTitle: "¿Otro bloque de enfoque?",
    restFive: "Descansar 5",
    focus25: "Enfoque 25 min",
    done: "Hecho",
    later: "Luego",
    notNow: "Ahora no",
    snooze: "Posponer 10 min",
    tomorrow: "Mañana",
    /** Titles quick add gives a line that is only a time. */
    timerTitle: "Temporizador",
    reminderTitle: "Recordatorio",
  },

  settings: {
    windowTitle: "Ajustes — VoltaDock",
    claude: {
      connected:
        "VoltaDock está conectado a tus sesiones de Claude Code. Las llamadas a herramientas, las preguntas y las peticiones de permiso aparecen en la isla y puedes responderlas desde ahí.",
      notConnected:
        "Instala los hooks para ver tus sesiones de Claude Code en la isla y aprobar permisos sin dejar lo que estás haciendo.",
      hookMissing:
        "coucou-hook.exe todavía no está en su sitio. Reinicia VoltaDock; si sigue fallando, compílalo con `cargo build -p coucou-hook`.",
      install: "Instalar hooks…",
      reinstall: "Reinstalar hooks…",
      relayMissing: "El relay aún no está instalado.",
      uninstall: "Desinstalar hooks…",
      previewInstall:
        "Esto es exactamente lo que cambiará en tu settings.json. Tus propios hooks no se tocan.",
      previewUninstall: "Esto solo quita las entradas de VoltaDock. Tus propios hooks no se tocan.",
      backup: (path: string) => `Copia de seguridad → ${path}`,
      confirmInstall: "Hacer copia y escribir",
      confirmUninstall: "Hacer copia y quitar",
      done: (backup: string) =>
        `Hecho. La configuración anterior se guardó como ${backup}. Abre una sesión nueva de Claude Code para que cargue los hooks.`,
      writeFailed: (err: string) => `No se pudo escribir: ${err}`,
    },
    api: {
      keySaved: "Clave guardada en el Administrador de credenciales de Windows.",
      noKey: "Aún no hay clave: el chat necesita una.",
      saveKey: "Guardar clave",
      remove: "Quitar",
      saved: "Guardada. Nunca toca el disco.",
      saveFailed: (err: string) => `No se pudo guardar: ${err}`,
      removed: "Clave quitada.",
      removeFailed: (err: string) => `No se pudo quitar: ${err}`,
      apiKey: "Clave de API",
      model: "Modelo",
    },
    integrations: {
      title: "Integraciones",
      note: (used: number, max: number) =>
        `Elige hasta ${max} píldoras para mostrar junto a Volt: ${used}/${max} en uso. Las claves se guardan en el Administrador de credenciales de Windows, nunca en disco.`,
      secretKey: "Clave secreta",
      token: "Token",
      instanceUrl: "URL de la instancia",
      apiKey: "Clave de API",
      integrationToken: "Token de integración",
    },
    general: {
      title: "General",
      language: "Idioma",
      languageSystem: "Idioma de Windows",
      sound: "Sonido",
      autoClose: "Cierre automático",
      autoCloseHint: "segundos después de salir de la isla",
      screen: "La isla vive en",
      screenPrimary: "Pantalla principal",
      screenCursor: "Pantalla bajo el cursor",
      projectsRoot: "Carpeta de proyectos",
      projectsRootAuto: "Automática",
      projectsRootHint: "con tus repositorios git",
      autostart: "Iniciar con Windows",
    },
    privacy: "Sin telemetría. Las peticiones de red solo van a los servicios que tú configuras.",
  },
};

export type Messages = typeof es;
