# Pinloom

Mantén imágenes, vídeos, páginas web, notas y tareas a la vista mientras trabajas. Aplicación nativa
para macOS 14 o posterior, en Apple silicon e Intel.

[English](../../README.md) · [简体中文](README.zh-Hans.md)

![La línea de Pinloom con una nota editable](../images/preview.png)

## Uso

Abrir Pinloom desde Aplicaciones muestra la línea, aunque ya esté ejecutándose
y oculta. Al iniciar sesión automáticamente, permanece oculta hasta que la abras.

Haz clic en el icono de chincheta de la barra de menús para mostrar u ocultar
la línea. Haz clic derecho para abrir el menú. Permanece visible hasta que la
ocultas, incluso sobre otras aplicaciones a pantalla completa.

- **Pegar** añade imágenes, archivos de vídeo copiados o direcciones web.
- **Añadir archivos…** abre el selector de imágenes y vídeos locales. También puedes arrastrar archivos o enlaces a la línea o al icono.
- **Añadir página web…** acepta una dirección. Las tarjetas permiten desplazarse, seleccionar texto, seguir enlaces, volver, avanzar, recargar y abrir en el navegador.
- Los vídeos empiezan pausados y silenciados, con controles nativos. Se guarda una copia propia y la posición de reproducción; ocultar la línea pausa la reproducción.
- **Nueva nota** permite editar texto y añadir tareas con casillas. Todo se guarda localmente.
- **Return** inserta una tarea debajo y mueve el texto posterior al cursor a
  ella. En una tarea vacía, la elimina y termina la edición. **Escape** termina
  la edición sin eliminarla.
- Arrastra la pinza de una tarjeta para moverla y su esquina inferior derecha para cambiar el tamaño.
- Selecciona texto y usa **Command+C**, o **Copiar nota** para copiar la nota completa con sus tareas.
- Haz clic en una imagen para copiarla, doble clic para ampliarla o mantén pulsado para usar Marcación.
- Fija una imagen en una ventana independiente de referencia. Usa una copia propia que sobrevive a cambios del archivo original.

**Organizar** agrupa restablecer posiciones y descolgar imágenes; **Opciones**
agrupa sonidos y abrir al iniciar sesión. Recuperar una nota y mostrar u ocultar
referencias aparecen solo cuando son útiles. Ocultar la línea no elimina datos.
Descolgar conserva el archivo original; **Mover a la Papelera** lo elimina explícitamente.

No observa carpetas de capturas, cambia los ajustes de captura ni registra
atajos globales. Las imágenes añadidas permanecen hasta que las quitas.
Las páginas se cargan al mostrar la línea y usan la sesión WebKit de Pinloom,
sin compartir la sesión del navegador. Algunos inicios de sesión, ventanas
emergentes y descargas requieren abrir en el navegador. Los formatos locales
compatibles dependen de AVFoundation, incluidos MP4, MOV y M4V compatibles.
Imágenes, vídeos y notas se guardan localmente. Las tarjetas web conectan con
los sitios añadidos; Pinloom no requiere cuenta ni envía analítica.

Las imágenes nuevas caben en un área de 306 × 234 puntos, manteniendo su
proporción. Las notas empiezan en 320 × 280, con un mínimo de 240 × 220.
El tamaño máximo depende del espacio disponible de la pantalla: 85% del
ancho menos 40 puntos y la altura menos 100. Las pantallas pequeñas ajustan
la presentación sin sobrescribir los tamaños guardados. Texto y tareas
comparten una sola área de desplazamiento.
Las tarjetas de vídeo empiezan en 384 × 260 y las páginas web en 480 × 360,
con los mismos límites de pantalla.

## Compilar

```sh
git clone https://github.com/z333d/pinloom.git
cd pinloom
swift test
swift scripts/check-strings.swift
SIGN_IDENTITY=- scripts/build-app.sh release
open build/Pinloom.app
```

Copia la aplicación a Aplicaciones. `scripts/make-dmg.sh` crea una imagen de
instalación sin abrir Finder. Las compilaciones locales y de CI tienen firma
ad hoc y no están notarizadas por Apple. No se selecciona automáticamente una
identidad del llavero. Se requieren credenciales propias para
firmar con Developer ID y notarizar.

Pinloom usa su propio identificador y directorio de datos. En el primer inicio
copia imágenes, notas, posiciones y referencias de las primeras compilaciones
locales sin borrar los originales ni sobrescribir datos nuevos. Cierra la app
anterior antes de abrir Pinloom.

## Origen y licencia

Mantenido de forma independiente por [z333d](https://github.com/z333d), basado en
el código MIT de [Tendedero](https://github.com/alejandrobujan/tendedero) de Alejandro
Buján. Conserva los avisos originales y usa un nombre, icono e imágenes nuevos.
No es una versión oficial ni está respaldado por el autor original.
Consulta [LICENSE](../../LICENSE) y [NOTICE](../../NOTICE).
