# slskd.sh

Script post-descarga para [slskd](https://github.com/slskd/slskd), el cliente de Soulseek. Se ejecuta automáticamente al completarse una descarga y realiza notificaciones, escaneo antivirus y generación de fichas según la configuración.

---

## Requisitos

- `jq` disponible en la imagen de slskd
- `wget` disponible en la imagen de slskd
- Acceso a la red Docker donde corren los servicios

---

## Requisitos opcionales

- [Gotify](https://codeberg.org/gotify/server)
- [Clamav REST API](https://github.com/benzino77/clamav-rest-api)
- [Butler](https://codeberg.org/osdaeg/butler)
- [Paste.sh](https://codeberg.org/osdaeg/paste.sh)

---

## Instalación

1. Copiar `slskd.sh` a `/app/scripts/slskd.sh` dentro del contenedor (o al volumen mapeado correspondiente).
2. Copiar `.env.example` como `.env` en `/app/scripts/.env` y completar los valores.
3. Dar permisos de ejecución:
   ```bash
   chmod +x /app/scripts/slskd.sh
   ```
4. En la configuración de slskd, apuntar el script a `/app/scripts/slskd.sh` para los eventos `DownloadFileComplete` y `DownloadDirectoryComplete`.

---

## Configuración — `.env`

| Variable           | Descripción                                              | Ejemplo                              |
|--------------------|----------------------------------------------------------|--------------------------------------|
| `LOCKFILE`         | Ruta del archivo de bloqueo                              | `/app/downloads/slskd.lock`          |
| `LOGFILE`          | Ruta del archivo de log                                  | `/app/scripts/finished.log`          |
| `GOTIFY_URL`       | URL del servidor Gotify                                  | `http://192.168.1.10:8088/message`   |
| `GOTIFY_TOKEN`     | Token de autenticación de Gotify                         | `TuTokenDeGotify`                    |
| `CLAMAV_URL`       | URL de la API REST de ClamAV                             | `http://192.168.1.10:3311/api/v1/scan` |
| `BUTLER_URL`       | URL de Butler-API                                        | `http://192.168.1.10:7999/process`   |
| `PASTEBIN_URL`     | URL del pastebin propio (para logs de error)             | `http://192.168.1.10:8090`           |
| `MUSIC_EXTENSIONS` | Extensiones de audio que activan Butler-API              | `mp3\|flac\|ogg\|m4a\|wav\|...`      |
| `NOTIFICATION`     | Activar notificaciones Gotify (`yes` / `no`)             | `yes`                                |
| `CLAMAV`           | Activar escaneo antivirus (`yes` / `no`)                 | `no`                                 |
| `BUTLER`           | Activar generación de fichas Butler-API (`yes` / `no`)   | `yes`                                |
| `PASTEBIN`         | Activar subida de logs de error al pastebin (`yes` / `no`) | `yes`                              |

---

## Flujo de ejecución

El script solo actúa ante eventos `DownloadFileComplete`. Los eventos `DownloadDirectoryComplete` son ignorados.

```
1. Crear lockfile en /app/downloads/slskd.lock
2. Notificar descarga completada (si NOTIFICATION=yes)
3. Escanear con ClamAV (si CLAMAV=yes)
   └─ Si infectado → eliminar archivo + notificar
4. Generar ficha con Butler-API (si BUTLER=yes, solo música)
5. Eliminar lockfile
```

### Lockfile

Durante la ejecución del script existe el archivo `slskd.lock` en la carpeta de descargas. Otros scripts del ecosistema (como el de importación de Beets) pueden chequear su presencia para no interferir con una descarga en curso.

### Notificaciones (Gotify)

Si `NOTIFICATION=yes`, se envían notificaciones en los siguientes eventos:

- Descarga completada
- Resultado del escaneo ClamAV (si activo)
- Error al generar ficha Butler-API (si activo)
- Errores inesperados del script (si `PASTEBIN=yes`)

### Escaneo antivirus (ClamAV)

> ⚠️ `curl` no está disponible en la imagen de slskd. El escaneo ClamAV requiere multipart/form-data, por lo que esta funcionalidad está **deshabilitada** hasta que `curl` esté disponible. El bloque correspondiente está comentado en el script listo para activarse.

Con `CLAMAV=no`, el archivo se asume limpio directamente.

### Fichas Butler-API

Si `BUTLER=yes` y el archivo descargado tiene una extensión de audio definida en `MUSIC_EXTENSIONS`, se llama a Butler-API con el nombre del archivo para generar una ficha HTML enriquecida. Butler-API maneja su propia notificación Gotify al completarse.

### Manejo de errores (Pastebin)

Si `PASTEBIN=yes`, cualquier error inesperado del script sube las últimas 100 líneas del log al pastebin configurado y notifica a Gotify con el enlace.

---

## Recursos útiles

- [Mi configuración de beets](https://codeberg.org/osdaeg/my-beets-config)
- [Editor de metadatos Taggerr](https://codeberg.org/osdaeg/taggerr)

---

## Notas técnicas

- `curl` **no está disponible** en la imagen de slskd. Todas las llamadas HTTP usan `wget`.
- `wget` no soporta multipart/form-data, por lo que ClamAV (que lo requiere) está temporalmente deshabilitado.
- Gotify y Butler-API se invocan con `--post-data` (urlencoded), que `wget` sí soporta.
- Los logs se escriben en modo append en `LOGFILE`.
