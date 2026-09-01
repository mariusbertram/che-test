# OpenShift Dev Spaces – Entwicklungsumgebung

Dieses Repository enthält eine [Devfile](https://devfile.io)-Konfiguration für
**Red Hat OpenShift Dev Spaces 3.29.1** (Eclipse Che) mit Toolchain für **Go**,
**Python**, **Ansible** und **Terraform**, inklusive Proxy-Konfiguration und
Unterstützung für **remote JetBrains-IDEs** (JetBrains Gateway).

## Dateien

| Datei | Zweck |
|---|---|
| `devfile.yaml` | Workspace-Definition: Container-Image, Ressourcen, Proxy-Env-Variablen, Setup-Command |
| `.devspaces/setup-tools.sh` | Läuft beim Workspace-Start (`postStart`): richtet Proxy für git/pip/go/terraform/ansible ein und installiert Ansible + Terraform |
| `.che/che-editor.yaml` | Legt den Standard-Editor für dieses Repo fest (JetBrains IntelliJ IDEA, remote via Gateway) |

## Workspace starten

In der Dev Spaces Dashboard über **"Create Workspace"** die Git-URL dieses
Repos angeben. Das `devfile.yaml` wird automatisch erkannt und verwendet.

Basis-Image ist `quay.io/devfile/universal-developer-image:ubi9-latest`
(enthält bereits Go, Python3/pip, git). Ansible und Terraform werden beim
ersten Start automatisch installiert (`.devspaces/setup-tools.sh`, per
`postStart`-Event). Bei persistentem Storage (Standard: per-workspace/per-user
PVC unter `$HOME`) bleibt das nach einem Neustart erhalten; bei "ephemeral"
Storage läuft die Installation bei jedem Start erneut – das Skript ist dafür
idempotent (überspringt bereits vorhandene Tools).

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

Es gibt zwei Wege:

### 1. Standard: IntelliJ IDEA Community (sofort einsatzbereit)

`.che/che-editor.yaml` setzt `che-incubator/che-idea/latest` als Editor.
Beim Öffnen des Workspace startet automatisch eine remote laufende
IntelliJ IDEA Community, die per JetBrains Gateway von eurem lokalen Rechner
aus verbunden wird (Gateway zeigt den Workspace als "Running IDE" an).

Für Go/Python/Ansible/Terraform in der IDE aus dem JetBrains Marketplace
installieren:
- **Go**: Go-Plugin
- **Python**: Python Community Edition-Plugin
- **Ansible**: "Ansible Support"-Plugin
- **Terraform**: "HashiCorp Terraform / HCL"-Plugin

### 2. Ultimate/Professional-Editionen (eigene JetBrains-Lizenz nötig)

Für volle Sprach-Unterstützung ohne Marketplace-Plugins (z. B. IntelliJ IDEA
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
dafür Voraussetzung.

## Anpassungen

- **Speicher/CPU-Limits**: `devfile.yaml` → `memoryLimit`/`cpuLimit`
  (Standard: 6Gi/4 Cores, da IDE-Backend + Toolchain gemeinsam laufen)
- **Terraform-Version pinnen**: `TERRAFORM_VERSION`-Env-Var in `devfile.yaml`
  (leer lassen = jeweils aktuelle Version wird beim Start ermittelt)
- **Zusätzliche Ansible-Collections**: `requirements.yml` im Repo anlegen und
  in `.devspaces/setup-tools.sh` einen `ansible-galaxy collection install -r
  requirements.yml`-Aufruf ergänzen
