# OpenShift Dev Spaces – Entwicklungsumgebung

Dieses Repository enthält eine [Devfile](https://devfile.io)-Konfiguration für
**Red Hat OpenShift Dev Spaces 3.29.1** (Eclipse Che) mit Toolchain für **Go**,
**Python**, **Ansible** und **Terraform**, inklusive Proxy-Konfiguration und
Unterstützung für **remote JetBrains-IDEs** (JetBrains Gateway).

## Dateien

| Datei | Zweck |
|---|---|
| `devfile.yaml` | Workspace-Definition: Container-Image, Ressourcen, Proxy-Env-Variablen, postStart-Command |
| `.devspaces/Dockerfile` | Custom Workspace-Image: UDI-Basis-Image + Ansible |
| `.github/workflows/build-dev-image.yml` | Baut `.devspaces/Dockerfile` bei jeder Änderung automatisch und pusht nach GHCR |
| `.devspaces/configure-proxy.sh` | Läuft beim Workspace-Start (`postStart`): richtet Proxy für git/pip ein |
| `.che/che-editor.yaml` | Legt den Standard-Editor für dieses Repo fest (JetBrains IntelliJ IDEA Community, remote via Gateway) |

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

## Remote JetBrains-IDE nutzen

Es gibt zwei Wege – **wichtig:** nur einer davon deckt Go tatsächlich ab.

### 1. Standard: IntelliJ IDEA Community (sofort einsatzbereit, kostenlos)

`.che/che-editor.yaml` setzt `che-incubator/che-idea/latest` als Editor.
Beim Öffnen des Workspace startet automatisch eine remote laufende
IntelliJ IDEA Community, die per JetBrains Gateway von eurem lokalen Rechner
aus verbunden wird.

**Plugins werden hier nicht über das Devfile vorinstalliert** – Eclipse Che
hat das Feature für Nicht-VS-Code-Editoren wieder entfernt (nur
`.vscode/extensions.json` funktioniert noch, und das nur für den che-code/VS
Code-Editor). Plugins müssen einmalig manuell über
**Settings → Plugins → Marketplace** in der IDE installiert werden; sie
bleiben danach erhalten, solange der Workspace-Storage persistent ist
(Standard: per-workspace/per-user PVC).

Empfohlene Marketplace-Plugins:
- **Python**: [Python Community Edition](https://plugins.jetbrains.com/plugin/7322-python-community-edition) – funktioniert in Community
- **Ansible**: [Ansible Support](https://plugins.jetbrains.com/plugin/15704-ansible-support) oder [Ansible](https://plugins.jetbrains.com/plugin/14893-ansible) – funktioniert in Community
- **Terraform/HCL**: [HashiCorp Terraform / HCL](https://plugins.jetbrains.com/plugin/7808-hcl-language-support) – Kompatibilität mit Community auf der Plugin-Seite prüfen, teils Ultimate-only
- **Go**: **kein offizielles Go-Plugin für IntelliJ IDEA Community** – der
  JetBrains-Go-Support ist exklusiv an GoLand bzw. IDEA Ultimate gebunden.
  Für Go-Entwicklung ist Weg 2 notwendig.

### 2. Ultimate/Professional-Editionen inkl. Go (eigene JetBrains-Lizenz nötig)

Für vollständige Sprach-Unterstützung inklusive Go (z. B. IntelliJ IDEA
Ultimate mit nativer Go-, Python-, Ansible- und Terraform-Integration, oder
GoLand/PyCharm Professional direkt):

1. [JetBrains Gateway](https://www.jetbrains.com/remote-development/gateway/)
   lokal installieren.
2. In Gateway das Plugin **"OpenShift Dev Spaces"**
   ([redhat-developer/devspaces-gateway-plugin](https://github.com/redhat-developer/devspaces-gateway-plugin))
   aus dem JetBrains-Marketplace installieren.
3. Workspace in der Dev Spaces Dashboard starten und dort statt IntelliJ IDEA
   Community die gewünschte JetBrains-IDE (Ultimate/Professional) auswählen.
   Dev Spaces lädt das passende IDE-Backend herunter und startet es headless
   im Workspace; über Gateway verbindet sich lokal ein Thin-Client.

Eine gültige JetBrains-Lizenz für die gewählte Ultimate/Professional-IDE ist
Voraussetzung. Auch hier werden zusätzliche Plugins (Ansible, Terraform/HCL)
einmalig manuell über den Marketplace installiert; Go und Python sind in
Ultimate/GoLand/PyCharm bereits eingebaut.

**Empfehlung für euren Stack (Go + Python + Ansible + Terraform):** IntelliJ
IDEA Ultimate über Weg 2 – deckt alle vier Sprachen in einer IDE ab.

## Anpassungen

- **Speicher/CPU-Limits**: `devfile.yaml` → `memoryLimit`/`cpuLimit`
  (Standard: 6Gi/4 Cores, da IDE-Backend + Toolchain gemeinsam laufen)
- **Zusätzliche Ansible-Collections**: im `.devspaces/Dockerfile` nach dem
  `pip3 install ansible` einen `ansible-galaxy collection install ...`-Aufruf
  ergänzen und das Image neu bauen lassen (Push auf `.devspaces/Dockerfile`)
- **Weitere Tools**: analog im `.devspaces/Dockerfile` per `RUN` ergänzen,
  statt zur Laufzeit zu installieren
