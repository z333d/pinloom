<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/hero-dark.png">
  <img src="../images/hero-light.png" alt="Tendedero. Capturas, tendidas a secar. Tres capturas en marcos de cristal cuelgan de una línea fina bajo la barra de menús de macOS.">
</picture>

<p align="center">
  Libre y de código abierto. Para macOS 14 y posteriores.
  <br>
  <a href="../../../../releases/latest">Descargar&nbsp;&rsaquo;</a>
  &nbsp;&nbsp;
  <a href="#compilar-desde-el-código">Compilar desde el código&nbsp;&rsaquo;</a>
  <br><br>
  <a href="../../README.md">English</a>&nbsp;·&nbsp;Español
  <br>
  <sub>Traducción del README en inglés. Si no coinciden, vale el inglés.</sub>
</p>

<br>

## Fuera de la vista. A mano.

Cada captura que haces se cuelga en una línea justo encima de tu pantalla.
Deja el puntero en la barra de menús y baja deslizándose. Apártalo y desaparece.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/demo-dark.gif">
  <img src="../images/demo-light.gif" alt="El puntero se apoya en el borde superior, la línea baja con tres capturas balanceándose suavemente, un clic copia una y la línea se recoge cuando el puntero se aparta.">
</picture>

<br>
<br>

## Un gesto para cada cosa.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/bento-dark.png">
  <img src="../images/bento-light.png" alt="Clic para copiar. Mantén pulsado para marcar. Arrastra para compartir. Suéltala.">
</picture>

<br>
<br>

| | |
|:--|:--|
| Clic | Copia la imagen. |
| Mantener pulsado | Ábrela en Marcación. |
| Doble clic | Ábrela en Vista Previa. |
| Arrastrar a una app | Envía una copia. Sigue en la línea. |
| Arrastrar a una carpeta | Guárdala ahí. Sale de la línea. |
| Arrastrar a la Papelera, o clic en la cruz | Suéltala. |
| Dejar el puntero en la barra de menús | Baja la línea en esa pantalla. |
| Clic en cualquier parte de la barra de menús | Recógela. |
| <kbd>⌃</kbd>&thinsp;<kbd>⌥</kbd>&thinsp;<kbd>T</kbd> | Muestra u oculta la línea. |

<br>

## Tu Escritorio. Por fin despejado.

Deja que Tendedero se encargue de tus capturas<sup>1</sup> y no pasarán por el
Escritorio. Sin miniatura flotante. Sin esperar cinco segundos. Cada captura
se cuelga en cuanto la haces, y solo se queda lo que arrastras fuera.

Los mismos atajos. La misma memoria muscular. Solo que sin desorden.

<br>

## Privado por diseño.

Sin cuenta. Sin red. Sin analíticas.
Tendedero funciona entero en tu Mac, y tus capturas nunca salen de él.

<br>

## Especificaciones

| | |
|:--|:--|
| **Compatibilidad** | macOS 14 Sonoma o posterior, en Apple silicon e Intel. Diseñado para macOS 27. |
| **Tamaño** | 1,7 MB |
| **Idiomas** | Inglés, español |
| **Hecho con** | Swift, AppKit y SwiftUI |
| **Acceso a la red** | Ninguno |
| **Precio** | Gratis |
| **Licencia** | MIT para el código. El nombre y el icono no están incluidos. |

<br>

## Instalación

Descarga la imagen de disco de la [última versión](../../../../releases/latest),
ábrela y arrastra Tendedero a Aplicaciones. O instálalo con Homebrew:

```sh
brew install --cask alejandrobujan/tap/tendedero
```

Tendedero está firmado con un Developer ID y notarizado por Apple, así que se
abre como cualquier otra app.

<br>

## Compilar desde el código

```sh
git clone git@github.com:alejandrobujan/tendedero.git
cd tendedero
scripts/build-app.sh
open build/Tendedero.app
```

Necesitas las herramientas de Swift. Xcode es opcional. Con las Command Line
Tools de macOS 27, el script recurre al SDK de macOS 26 que instalan a su lado,
porque el SDK nuevo necesita un plugin de macros de SwiftUI que solo trae Xcode.
Las compilaciones locales se firman ad hoc, así que macOS vuelve a pedir acceso
al Escritorio después de cada compilación.

<details>
<summary>Dentro de la app</summary>
<br>

| Archivo | Función |
|:--|:--|
| `AppDelegate.swift` | Barra de menús, atajo, bajar y recoger la línea |
| `LinePanel.swift` | La franja transparente a lo largo del borde superior de la pantalla |
| `LineView.swift` | La línea y dónde cuelga cada foto |
| `PeggedView.swift` | Una foto: marco de cristal, pinza, balanceo y brisa |
| `GrabArea.swift` | Clic, pulsación larga, arrastrar y soltar |
| `ScreenshotWatcher.swift` | Detecta las capturas nuevas |
| `Inbox.swift` | Se encarga de los ajustes de captura y los deja como estaban |
| `Markup.swift` | Abre el editor de Marcación del sistema y guarda el resultado |
| `FullScreen.swift` | Sabe cuándo quedarse oculto |
| `Line.swift` | Qué hay colgado y qué puedes hacer con ello |

Todas las imágenes de aquí, el icono incluido, están dibujadas con código por
`scripts/make-icon.swift` y `scripts/make-readme-art.swift`.
`scripts/make-dmg.sh` crea la imagen de disco para cada versión.

Las traducciones están en `Sources/Tendedero/Resources`, una carpeta `.lproj`
por idioma. `swift scripts/check-strings.swift` comprueba que no falte ninguna.

</details>

<br>

---

<sub>
1. La primera vez que se abre, Tendedero se ofrece a encargarse de tus capturas. Si aceptas, desactiva la miniatura flotante y guarda las capturas nuevas en su propia carpeta, dos ajustes que también están en Opciones de Cmd+Mayús+5. Tus ajustes anteriores se guardan y se restauran al salir de Tendedero o al desactivar la opción desde la barra de menús. Tendedero se oculta solo mientras una app está a pantalla completa.
</sub>

<br>
<br>

<p align="center">
  <img src="../images/icon.png" width="64" height="64" alt="">
  <br>
  <sub>El código tiene licencia MIT. El nombre y el icono de Tendedero no, así que los forks necesitan los suyos. Consulta la <a href="../../LICENSE">LICENSE</a>.</sub>
  <br>
  <sub>Diseñado y desarrollado por <a href="https://alejandrobujan.com">Alejandro Buján</a>.</sub>
</p>
