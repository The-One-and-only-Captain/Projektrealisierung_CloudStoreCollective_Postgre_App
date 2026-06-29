# ==============================================================================
# SYSTEM OUTPUTS (MANDATORY)
# ==============================================================================

output "instance_id" {
  description = "VM ID for backend management"
  value       = var.use_mock_provider ? "mock-instance-${var.deployment_id}" : openstack_compute_instance_v2.pg_server[0].id
}

output "app_name" {
  description = "Project name"
  value       = var.app_name
}

# ==============================================================================
# PUBLIC OUTPUTS
# ==============================================================================

output "pgadmin_url" {
  description = "pgAdmin Web-Oberfläche (HTTPS, Self-Signed)"
  value       = var.use_mock_provider ? "https://mock-ip" : "https://${openstack_networking_floatingip_v2.pg_fip[0].address}"
}

output "postgres_host" {
  description = "PostgreSQL Host (für externe Clients wie psql, DBeaver)"
  value       = var.use_mock_provider ? "mock-ip" : openstack_networking_floatingip_v2.pg_fip[0].address
}

output "postgres_port" {
  description = "PostgreSQL Port"
  value       = "5432"
}

output "ssh_command" {
  description = "SSH-Befehl für den VM-Zugang"
  value       = var.use_mock_provider ? "ssh ubuntu@mock-ip" : "ssh -i <private_key> ubuntu@${openstack_networking_floatingip_v2.pg_fip[0].address}"
}

# ==============================================================================
# SENSITIVE OUTPUTS
# ==============================================================================

output "admin_credentials" {
  description = "Admin-Zugangsdaten des Dozenten (Postgres-Superuser + pgAdmin + SSH-Debug als 'ubuntu')"
  sensitive   = true
  value = {
    db_username  = local.admin_dbuser
    db_name      = local.admin_dbname
    email        = var.admin_username
    password     = random_password.admin_password.result
    pgadmin_url  = var.use_mock_provider ? "https://mock-ip" : "https://${openstack_networking_floatingip_v2.pg_fip[0].address}"
    psql_host    = var.use_mock_provider ? "mock-ip" : openstack_networking_floatingip_v2.pg_fip[0].address
    psql_port    = "5432"
    ssh_username = "ubuntu"
    ssh_command  = "ssh ubuntu@${var.use_mock_provider ? "mock-ip" : openstack_networking_floatingip_v2.pg_fip[0].address}"
  }
}

output "student_credentials" {
  description = "Zugangsdaten aller Studierenden (eigene DB + DB-User)"
  sensitive   = true
  value = {
    for s in local.students : s.email => {
      db_username = s.dbuser
      db_name     = s.dbname
      email       = s.email
      password    = random_password.student_passwords[s.email].result
      pgadmin_url = var.use_mock_provider ? "https://mock-ip" : "https://${openstack_networking_floatingip_v2.pg_fip[0].address}"
      psql_host   = var.use_mock_provider ? "mock-ip" : openstack_networking_floatingip_v2.pg_fip[0].address
      psql_port   = "5432"
    }
  }
}

output "ssh_private_key" {
  description = "SSH Private Key für den VM-Zugang"
  sensitive   = true
  value       = tls_private_key.pg_ssh_key.private_key_openssh
}
