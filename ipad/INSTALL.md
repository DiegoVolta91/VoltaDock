# Instalar VoltaDock en el iPad sin cuenta de desarrollador

La app de iPad todavía no está en la App Store ni en TestFlight. Mientras tanto
se puede instalar gratis desde un PC con Windows usando **Sideloadly** y un
Apple ID normal. Limitaciones de Apple para cuentas gratuitas:

- La app **caduca a los 7 días**: hay que volver a instalarla (se conservan los
  datos, también el emparejado).
- Como mucho 3 apps instaladas así a la vez.

## 1. Descargar el .ipa

1. Abre la pestaña **Actions** del repositorio → workflow **iPad** → la última
   ejecución en verde.
2. Abajo, en **Artifacts**, descarga **VoltaDock-ipa** (un .zip).
3. Descomprímelo: dentro está `VoltaDock.ipa`. No está firmado; Sideloadly lo
   firma con tu Apple ID.

## 2. Preparar el PC (una vez)

1. Instala **iTunes** e **iCloud** descargados de la web de Apple (no las
   versiones de la Microsoft Store: Sideloadly no las detecta).
2. Instala **Sideloadly** desde sideloadly.io.

## 3. Instalar

1. Conecta el iPad al PC por cable, desbloquéalo y pulsa **Confiar** en este
   ordenador.
2. Abre Sideloadly, arrastra `VoltaDock.ipa`, escribe tu Apple ID y pulsa
   **Start**. Puede pedirte un código de verificación de Apple.
3. En el iPad:
   - **Ajustes → General → VPN y gestión de dispositivos** → tu Apple ID →
     **Confiar**.
   - **Ajustes → Privacidad y seguridad → Modo de desarrollador** → actívalo y
     reinicia (lo pide iPadOS 16 o posterior).
4. Abre VoltaDock. La primera vez pedirá permiso para la **red local**: dale
   que sí, o no podrá encontrar el PC.

## 4. Emparejar con Windows

1. En VoltaDock para Windows: **Ajustes → iPad → Permitir iPad**.
2. **Emparejar iPad…** muestra un código QR. Escanéalo desde la app del iPad
   (o con la cámara: abre `voltadock://…` en la app).
3. La primera vez Windows puede preguntar si permites el acceso a la red:
   elige **Redes privadas**.
4. El iPad y el PC tienen que estar en la misma Wi‑Fi.

## Cada 7 días

Vuelve a hacer el paso 3.2 con el mismo `.ipa` (o uno nuevo de Actions).
Sideloadly también tiene una opción de renovación automática si el PC está
encendido y en la misma red; no la hemos probado.
