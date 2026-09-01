# OpenShift Dev Spaces – Entwicklungsumgebung

Dieses Repository enthält eine [Devfile](https://devfile.io)-Konfiguration für
**Red Hat OpenShift Dev Spaces 3.29.1** (Eclipse Che) mit Toolchain für **Go**,
**Python**, **Ansible** und **Terraform**, inklusive Proxy-Konfiguration und
ausgelegt auf **IntelliJ IDEA Ultimate als remote IDE** über JetBrains
Gateway.

## Dateien

| Datei | Zweck |
|---|---|
| `devfile.yaml` | Workspace-Definition: Container-Image, Ressourcen, Proxy-Env-Variablen, postStart-Command |
| `.devspaces/Dockerfile` | Custom Workspace-Image: UDI-Basis-Image + Ansible |
| `.github/workflows/build-dev-image.yml` | Baut `.devspaces/Dockerfile` bei jeder Änderung automatisch und pusht nach GHCR |
| `.devspaces/configure-proxy.sh` | Läuft beim Workspace-Start (`postStart`): richtet Proxy für git/pip ein |
| `.che/che-editor.yaml` | Legt den Standard-Editor für dieses Repo fest (che-code, dient nur als Andockpunkt für JetBrains Gateway – siehe unten) |

## Workspace-Image

Alle Abhängigkeiten stecken fest im Container-Image, nichts wird beim
Workspace-Start nachinstalliert:

- Basis: `quay.io/devfile/universal-developer-image:ubi9-latest` – bringt
  bereits **Go**, **Python3/pip**, **Terraform** und git mit.
- `.devspaces/Dockerfile` ergänzt nur **Ansible** (das einzige fehlende Tool)
  per `pip3 install ansible`.
- `.github/workflows/build-dev-image.yml` baut das Image bei jeder Änderung
  an `.devspaces/Dockerfile` automatisch und pusht es nach
  `ghcr.io/mariusbertram/che-test-dev:latest` – dorthin zeigt `devfile.yaml`.

**Einmalig nach dem ersten Build nötig:** Das GHCR-Package ist standardmäßig
privat. Unter `github.com/mariusbertram?tab=packages` → Package
`che-test-dev` → **Package settings** → **Change visibility** → *Public*
setzen, sonst schlägt der Image-Pull im Workspace mit `ImagePullBackOff` fehl
(alternativ: Image-Pull-Secret im OpenShift-Namespace hinterlegen).

Um eine andere Terraform-Version als die im Basis-Image zu bekommen, im
Dockerfile eine zusätzliche `RUN`-Zeile mit `curl`/`unzip` nach
`releases.hashicorp.com` ergänzen, oder direkt bei
`quay.io/devfile/universal-developer-image` prüfen, ob eine neuere UDI-Version
bereits eine aktuellere Terraform-Version mitbringt.

## Proxy-Konfiguration

In `devfile.yaml` unter `components[0].container.env`:

```yaml
- name: HTTP_PROXY
  value: 'http://proxy.example.corp:3128'
- name: HTTPS_PROXY
  value: 'http://proxy.example.corp:3128'
- name: NO_PROXY
  value: 'localhost,127.0.0.1,.svc,.cluster.local'
```

Vor dem ersten Start eintragen (oder leer lassen, falls euer Cluster den
Proxy bereits clusterweit über die `CheCluster`-Custom-Resource
(`spec.devEnvironments.proxyURL` etc.) in jeden Workspace-Container injiziert
– das ist eine Admin-seitige Einstellung, unabhängig von diesem Devfile).

Das Setup-Skript übernimmt daraus automatisch:
- `git config --global http.proxy/https.proxy`
- `pip.conf` mit `proxy =`
- Ergänzt `NO_PROXY` um `KUBERNETES_SERVICE_HOST` sowie `.svc`/`.cluster.local`,
  damit Traffic zum Kubernetes-API-Server **nicht** über den Proxy läuft
  (sonst schlägt intern-Cluster-Kommunikation fehl)

Go (`GOPROXY`), Terraform (Provider-Downloads) und `ansible-galaxy` nutzen
`HTTP_PROXY`/`HTTPS_PROXY` direkt über ihre HTTP-Clients – dafür ist keine
zusätzliche Konfiguration nötig, solange die Env-Variablen gesetzt sind.

## Remote JetBrains-IDE (Ultimate)

Dieses Setup ist auf **IntelliJ IDEA Ultimate** ausgelegt (statt der
kostenlosen Community-Edition), da nur Ultimate den Go-Plugin unterstützt –
Community kann kein Go. Ultimate ist **kein Eintrag in `che-editor.yaml`**
(die Che-Plugin-Registry kennt nur `che-code` und `che-idea`/Community);
stattdessen verbindet sich eure lokal installierte, lizenzierte Ultimate
per JetBrains Gateway mit dem Workspace. `.che/che-editor.yaml` setzt daher
`che-code` als Basis-Editor – der läuft nur als Andockpunkt, entwickelt wird
in Ultimate.

**Voraussetzung:** gültige JetBrains-Lizenz für IntelliJ IDEA Ultimate
(oder All Products Pack), aktiviert lokal in Gateway/Toolbox – das ist reine
Client-seitige Lizenzierung, im Workspace-Image steckt keine Lizenz.

### Verbinden

1. [JetBrains Gateway](https://www.jetbrains.com/remote-development/gateway/)
   lokal installieren.
2. Workspace in der Dev Spaces Dashboard aus diesem Repo starten (Editor:
   che-code, per `che-editor.yaml`).
3. Zwei gleichwertige Wege, Gateway mit dem Workspace zu verbinden:
   - **Über die Dashboard**: laufenden Workspace öffnen → Button
     **„Open Gateway"** → Gateway startet lokal und fragt nach der
     gewünschten IDE → **IntelliJ IDEA Ultimate** wählen.
   - **Direkt aus Gateway**: in Gateway zusätzlich das Plugin
     **„OpenShift Dev Spaces"**
     ([redhat-developer/devspaces-gateway-plugin](https://github.com/redhat-developer/devspaces-gateway-plugin))
     installieren, damit lässt sich der Workspace auch ohne Umweg über die
     Dashboard direkt aus Gateway heraus auswählen.
4. Gateway lädt das Ultimate-Backend automatisch in den Workspace-Container
   (nach `$HOME`, bleibt bei persistentem Storage über Neustarts erhalten)
   und öffnet lokal den Thin-Client.

### Plugins

Go und Python sind in Ultimate bereits eingebaut. Ansible und Terraform/HCL
gibt es nur als Marketplace-Plugins – ein Vorinstallieren über das Devfile
ist für JetBrains-Editoren nicht (mehr) vorgesehen. Einmalig manuell über
**Settings → Plugins → Marketplace** installieren, bleibt danach bei
persistentem Storage erhalten:
- [Ansible Support](https://plugins.jetbrains.com/plugin/15704-ansible-support) oder [Ansible](https://plugins.jetbrains.com/plugin/14893-ansible)
- [HashiCorp Terraform / HCL](https://plugins.jetbrains.com/plugin/7808-hcl-language-support)

## Anpassungen

- **Speicher/CPU-Limits**: `devfile.yaml` → `memoryLimit`/`cpuLimit`
  (Standard: 8Gi/4 Cores, da Ultimate-Backend + Toolchain gemeinsam laufen)
- **Zusätzliche Ansible-Collections**: im `.devspaces/Dockerfile` nach dem
  `pip3 install ansible` einen `ansible-galaxy collection install ...`-Aufruf
  ergänzen und das Image neu bauen lassen (Push auf `.devspaces/Dockerfile`)
- **Weitere Tools**: analog im `.devspaces/Dockerfile` per `RUN` ergänzen,
  statt zur Laufzeit zu installieren
