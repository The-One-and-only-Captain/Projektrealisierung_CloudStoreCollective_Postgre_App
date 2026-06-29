terraform {
  required_version = ">= 1.6.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.53.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "openstack" {
  cloud = "openstack"
}

# ==============================================================================
# LOCALS
# ==============================================================================
locals {
  # Bei one-per-group bekommt jeder Run eine Map mit genau einem Group-Key.
  # Bei one-instance ist student_groups leer und students enthält die Liste.
  resolved_students = length(var.student_groups) > 0 ? flatten(values(var.student_groups)) : var.students

  # Postgres-Identifier dürfen bis 63 Zeichen lang sein und unterstützen [a-z0-9_].
  # Hier behalten wir die alte Email-zu-DBuser-Logik (@/. → _, lowercase).
  admin_dbuser = replace(replace(lower(var.admin_username), "@", "_"), ".", "_")
  admin_dbname = "${replace(replace(lower(var.admin_username), "@", "_"), ".", "_")}_db"

  students = [
    for email in local.resolved_students : {
      email  = email
      dbuser = replace(replace(lower(email), "@", "_"), ".", "_")
      dbname = "${replace(replace(lower(email), "@", "_"), ".", "_")}_db"
    }
  ]
}

# ==============================================================================
# DATA SOURCES
# ==============================================================================

data "openstack_images_image_v2" "ubuntu" {
  count       = var.use_mock_provider ? 0 : 1
  name        = var.image_name
  most_recent = true
}

data "openstack_compute_flavor_v2" "selected" {
  count = var.use_mock_provider ? 0 : 1
  name  = var.flavor_name
}

data "openstack_networking_network_v2" "external" {
  count    = var.use_mock_provider ? 0 : 1
  name     = var.external_network_name
  external = true
}

# ==============================================================================
# CREDENTIALS
# ==============================================================================

resource "random_password" "admin_password" {
  length           = 20
  special          = true
  override_special = "_-"
}

resource "random_password" "student_passwords" {
  for_each         = toset(local.resolved_students)
  length           = 16
  special          = true
  override_special = "_-"
}

resource "tls_private_key" "pg_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "openstack_compute_keypair_v2" "pg_keypair" {
  count      = var.use_mock_provider ? 0 : 1
  name       = "pg-keypair-${var.deployment_id}"
  public_key = tls_private_key.pg_ssh_key.public_key_openssh
}

# ==============================================================================
# SECURITY GROUP
# ==============================================================================

resource "openstack_networking_secgroup_v2" "pg_access" {
  count       = var.use_mock_provider ? 0 : 1
  name        = "pg-access-${var.deployment_id}"
  description = "PostgreSQL + pgAdmin: SSH + HTTPS + Postgres 5432"
}

resource "openstack_networking_secgroup_rule_v2" "ssh_ingress" {
  count             = var.use_mock_provider ? 0 : 1
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.pg_access[0].id
}

resource "openstack_networking_secgroup_rule_v2" "http_ingress" {
  count             = var.use_mock_provider ? 0 : 1
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.pg_access[0].id
}

resource "openstack_networking_secgroup_rule_v2" "https_ingress" {
  count             = var.use_mock_provider ? 0 : 1
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.pg_access[0].id
}

resource "openstack_networking_secgroup_rule_v2" "postgres_ingress" {
  count             = var.use_mock_provider ? 0 : 1
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 5432
  port_range_max    = 5432
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.pg_access[0].id
}

# ==============================================================================
# INSTANCE
# ==============================================================================

resource "openstack_compute_instance_v2" "pg_server" {
  count           = var.use_mock_provider ? 0 : 1
  name            = "pg-${var.deployment_id}"
  image_id        = data.openstack_images_image_v2.ubuntu[0].id
  flavor_id       = data.openstack_compute_flavor_v2.selected[0].id
  key_pair        = openstack_compute_keypair_v2.pg_keypair[0].name
  security_groups = [openstack_networking_secgroup_v2.pg_access[0].name]

  network {
    name = var.network_name
  }

  depends_on = [openstack_networking_floatingip_v2.pg_fip]

  user_data = templatefile("${path.module}/cloud-init.yaml", {
    app_name         = var.app_name
    floating_ip      = openstack_networking_floatingip_v2.pg_fip[0].address
    postgres_version = var.postgres_version

    admin_dbuser   = local.admin_dbuser
    admin_dbname   = local.admin_dbname
    admin_email    = var.admin_username
    admin_password = random_password.admin_password.result

    students = [
      for s in local.students : {
        dbuser   = s.dbuser
        dbname   = s.dbname
        email    = s.email
        password = random_password.student_passwords[s.email].result
      }
    ]
  })
}

# ==============================================================================
# FLOATING IP
# ==============================================================================

resource "openstack_networking_floatingip_v2" "pg_fip" {
  count = var.use_mock_provider ? 0 : 1
  pool  = var.floating_ip_pool
}

resource "openstack_compute_floatingip_associate_v2" "pg_fip_assoc" {
  count       = var.use_mock_provider ? 0 : 1
  floating_ip = openstack_networking_floatingip_v2.pg_fip[0].address
  instance_id = openstack_compute_instance_v2.pg_server[0].id
}

# ==============================================================================
# MOCK RESOURCE
# ==============================================================================

resource "null_resource" "mock_pg_server" {
  count = var.use_mock_provider ? 1 : 0
  triggers = {
    deployment_id = var.deployment_id
    app_name      = var.app_name
  }
}
