# PostgreSQL + pgAdmin

[PostgreSQL](https://www.postgresql.org/) + [pgAdmin 4](https://www.pgadmin.org/) als Docker-Compose-Stack auf einer VM. Pro Studierendem eine eigene DB mit eigenem DB-User. pgAdmin-Web-UI via Nginx + Self-Signed HTTPS.

## Konzept

Eine VM hostet Postgres und pgAdmin. Jeder Studierende bekommt **eine eigene Datenbank** + **einen eigenen DB-User** mit Vollzugriff darauf — aber **keinen** Zugriff auf die DBs anderer. Der Dozent ist Postgres-Superuser und sieht alles.

**Deploy-Strategien:**

- **`one-instance`** — eine Postgres-VM für den ganzen Kurs, alle Studis als eigene DB+User darauf
- **`one-per-group`** — eine Postgres-VM pro Projektgruppe, Mitglieder als DB+User auf der jeweiligen VM

## Parameter

### Allgemein

| Parameter | Typ | Pflicht | Beschreibung |
|---|---|---|---|
| `app_name` | string | ja | Identifier |
| `admin_username` | email (user-picker) | ja | Dozent → Postgres Superuser + pgAdmin Admin |
| `students` | list(email) (user-picker, multi) | bei `one-instance` | Max 30 Studis |
| `student_groups` | groups (group-builder) | bei `one-per-group` | Projektgruppen |

### Postgres-Optionen + Ressourcen

| Parameter | Typ | Default | Beschreibung |
|---|---|---|---|
| `flavor_name` | selection | `gp1.medium` | VM-Größe |
| `postgres_version` | selection | `16` | PostgreSQL Major-Version (14/15/16) |

## DB-Naming

| Email | DB-User | DB-Name |
|---|---|---|
| `s2327001@student.dhbw-mannheim.de` | `s2327001_student_dhbw-mannheim_de` | `s2327001_student_dhbw-mannheim_de_db` |
| `prof1@dhbw-mannheim.de` | `prof1_dhbw-mannheim_de` (Superuser) | — (Zugriff auf alle DBs) |

Postgres erlaubt Identifier bis 63 Zeichen — daher keine Kürzung wie bei den Linux-Usernames der anderen Apps.

## Outputs

| Output | Sichtbar | Sensitive | Beschreibung |
|---|---|---|---|
| `instance_id` | nein | nein | VM-ID (intern) |
| `app_name` | ja | nein | Projektname |
| `pgadmin_url` | ja | nein | `https://<floating-ip>` |
| `postgres_host` | ja | nein | Floating-IP für externe Clients |
| `postgres_port` | ja | nein | `5432` |
| `ssh_command` | ja | nein | SSH-Vorlage (Admin via Key) |
| `admin_credentials` | nein | ja | Superuser-Login (DB + pgAdmin) |
| `student_credentials` | nein | ja | Map email → {db_username, db_name, email, password, pgadmin_url, psql_host, psql_port} |
| `ssh_private_key` | nein | ja | SSH Private Key |

## Setup-Ablauf (cloud-init)

1. Ubuntu 22.04 + Pakete (`curl`, `ca-certificates`, `ufw`, `nginx`, `openssl`, `postgresql-client`)
2. UFW: Ports 22, 80, 443, 5432
3. Docker installieren
4. **Docker-Compose-Stack** (`/opt/pg/docker-compose.yml`):
   - `postgres:<version>` als Container, Port `5432` extern offen
   - `dpage/pgadmin4:latest` als Container, Port `80` **nur intern** auf 127.0.0.1:8081
5. **Init-Skript** `00-students.sql`: Beim ersten Postgres-Start: für jeden Studi `CREATE USER` + `CREATE DATABASE` + `GRANT ALL PRIVILEGES`
6. Self-Signed SSL-Zertifikat
7. Nginx als Reverse-Proxy: 80 → 443 Redirect, 443 → pgAdmin auf 127.0.0.1:8081
8. Systemd-Service `cloudstore-postgres.service` startet docker compose

## Zugriff

### Studierende

**pgAdmin (Web-UI):**

1. Browser öffnen: `pgadmin_url` (`https://<floating-ip>`)
2. **Self-Signed Cert akzeptieren** (Browser-Warnung wegklicken)
3. Login mit `email` + Passwort aus `student_credentials[<eigene-email>]`
4. Neue Connection in pgAdmin:
   - Host: `localhost` (oder `postgres` falls von außerhalb der VM)
   - Port: `5432`
   - Database: `<db_name>` aus credentials
   - User/Password: `db_username` + `password` aus credentials

**Direkt via `psql` oder DBeaver / DataGrip / etc.:**

```bash
psql -h <postgres_host> -p 5432 -U <db_username> -d <db_name>
```

### Dozent (Admin)

1. **pgAdmin als Superuser:** Login mit `admin_credentials.email` + Passwort. Sieht **alle** DBs.
2. **Postgres CLI als Superuser:**
   ```bash
   psql -h <postgres_host> -U <admin_dbuser> -d postgres
   ```
3. **VM per SSH:**
   ```bash
   ssh -i ./key.pem ubuntu@<floating-ip>
   sudo docker ps                                  # Container-Status
   sudo docker logs postgres                       # Postgres-Logs
   sudo docker logs pgadmin                        # pgAdmin-Logs
   sudo systemctl restart cloudstore-postgres      # Stack neustarten
   cat /etc/cloudstore/postgres_info.txt           # Übersicht aller User
   ```

### Typische Admin-Aufgaben

```bash
# In den Postgres-Container reingehen
sudo docker exec -it postgres bash

# Dort als Superuser einloggen
psql -U <admin_dbuser> -d postgres

# Alle User listen
\du
# Alle DBs listen
\l
# DB eines Studis zurücksetzen (Vorsicht!)
DROP DATABASE "<dbname>";
CREATE DATABASE "<dbname>" OWNER "<dbuser>";
```

## Ports

| Port | Zweck |
|---|---|
| 22 | SSH (Admin via Key) |
| 80 | HTTP → 301 Redirect auf HTTPS |
| 443 | pgAdmin Web UI (HTTPS, Self-Signed) |
| 5432 | PostgreSQL (für externe Clients direkt erreichbar) |

## Hinweise

- **Self-Signed Cert:** Browser warnt beim ersten Aufruf. 365 Tage gültig.
- **Postgres-Daten persistieren:** Docker-Volume `pg-data` und `pgadmin-data`. Bei VM-Destroy gehen sie verloren — Studierende sollten regelmäßig `pg_dump` auf ihre lokale Maschine machen.
- **Postgres extern offen:** Port 5432 ist von außen erreichbar. Praktisch für `psql`, aber: Authentifizierung läuft nur via DB-User/Passwort. Im Produktiv-Setup ggf. mit VPN absichern.
- **pgAdmin-Login = Email:** pgAdmin authentifiziert pro Studi mit der **E-Mail-Adresse** (nicht dem DB-Usernamen). Nach Login muss der Studi noch eine "Server-Connection" anlegen → da kommen dann DB-User/Passwort/DB-Name rein.
