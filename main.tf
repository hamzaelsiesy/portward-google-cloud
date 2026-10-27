# Portward gateway on Google Cloud: one Compute Engine machine running the gateway container, its records on an
# encrypted persistent disk with daily snapshots, its key generated in this project's Secret Manager, and a network
# with nothing open inbound unless the address needs it. Portward (the company) is not in the data path: in relay
# mode the relay passes traffic through still encrypted; the certificate lives on this machine.

locals {
  name   = var.goog_cm_deployment_name
  region = join("-", slice(split("-", var.zone), 0, 2))
  relay  = var.address_mode == "relay"
  # The license key is pwlic_<relay name>_<secret>: the name is its public middle part.
  relay_name = nonsensitive(split("_", var.license_key)[1])
  domain     = local.relay ? "${local.relay_name}.${var.relay_domain}" : var.domain
  base_url   = "https://${local.domain}"
  labels     = merge({ app = "portward", deployment = local.name }, var.labels)
  device     = "portward-records"

  caddy_image = "caddy:2.11.7"
  relay_image = "fatedier/frpc:v0.71.1"

  portward_toml = templatefile("${path.module}/templates/portward.toml.tftpl", {
    public_url     = jsonencode(local.base_url)
    setup_hosts    = jsonencode(var.setup_hosts)
    directory      = jsonencode(trimsuffix(var.directory_issuer, "/"))
    client_id      = jsonencode(var.directory_client_id)
    admin_groups   = jsonencode(var.admin_groups)
    admin_subjects = jsonencode(var.admin_subjects)
    user_groups    = jsonencode(var.user_groups)
    users          = jsonencode(var.users)
    scopes         = jsonencode(var.directory_scopes)
    updates_auto   = var.auto_update != "off"
    updates_scope  = jsonencode(var.auto_update == "all" ? "all" : "patch")
    updates_window = jsonencode(var.auto_update_window)
  })
  caddyfile = templatefile("${path.module}/templates/Caddyfile-${var.address_mode}.tftpl", { domain = local.domain })
  relay_toml = local.relay ? templatefile("${path.module}/templates/relay.toml.tftpl", {
    domain = local.domain, relay_host = var.relay_host, relay_name = local.relay_name
  }) : "# not in relay mode"

  secrets = merge(
    { key = "${local.name}-key", directory = "${local.name}-directory-secret", license = "${local.name}-license" },
  )
  # Secrets given as variables (in Terraform's state); whether one was given isn't itself secret.
  given_values = { directory = var.directory_client_secret, license = var.license_key }
  given = [for k, isset in {
    directory = nonsensitive(var.directory_client_secret != "")
    license   = true
  } : k if isset && contains(keys(local.secrets), k)]
}

resource "terraform_data" "checks" {
  lifecycle {
    precondition {
      condition     = local.relay || var.domain != ""
      error_message = "Own-domain mode needs domain, such as portward.example.com."
    }
    precondition {
      condition     = var.public_ip || var.subnetwork != ""
      error_message = "Without a public IP the machine needs an existing subnetwork with Cloud NAT (subnetwork)."
    }
  }
}

resource "google_project_service" "apis" {
  for_each           = toset(["compute.googleapis.com", "iam.googleapis.com", "secretmanager.googleapis.com"])
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# --- identity: the machine can read its own secrets, add the key once, and write logs; nothing else ---

resource "google_service_account" "gateway" {
  project      = var.project_id
  account_id   = "${local.name}-gateway"
  display_name = "Portward gateway (${local.name})"
  depends_on   = [google_project_service.apis]
}

resource "google_project_iam_member" "logs" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = google_service_account.gateway.member
}

resource "google_secret_manager_secret" "secrets" {
  for_each  = local.secrets
  project   = var.project_id
  secret_id = each.value
  labels    = local.labels
  replication {
    auto {}
  }
  deletion_protection = each.key == "key" ? var.keep_key_on_destroy : false
  depends_on          = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "given" {
  for_each    = toset(local.given)
  secret      = google_secret_manager_secret.secrets[each.key].id
  secret_data = local.given_values[each.key]
}

resource "google_secret_manager_secret_iam_member" "read" {
  for_each  = local.secrets
  project   = var.project_id
  secret_id = google_secret_manager_secret.secrets[each.key].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.gateway.member
}

resource "google_secret_manager_secret_iam_member" "generate_key" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.secrets["key"].secret_id
  role      = "roles/secretmanager.secretVersionAdder"
  member    = google_service_account.gateway.member
}

# --- network: nothing inbound, except 80/443 for an own domain and SSH through IAP if asked ---

resource "google_compute_network" "gateway" {
  count                   = var.subnetwork == "" ? 1 : 0
  project                 = var.project_id
  name                    = "${local.name}-net"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.apis]
}

resource "google_compute_subnetwork" "gateway" {
  count                    = var.subnetwork == "" ? 1 : 0
  project                  = var.project_id
  name                     = "${local.name}-subnet"
  region                   = local.region
  network                  = google_compute_network.gateway[0].id
  ip_cidr_range            = "10.86.0.0/28"
  private_ip_google_access = true
}

locals {
  subnetwork = var.subnetwork != "" ? var.subnetwork : google_compute_subnetwork.gateway[0].self_link
  network    = var.subnetwork != "" ? data.google_compute_subnetwork.given[0].network : google_compute_network.gateway[0].self_link
}

data "google_compute_subnetwork" "given" {
  count     = var.subnetwork != "" ? 1 : 0
  self_link = var.subnetwork
}

resource "google_compute_firewall" "https" {
  count         = local.relay ? 0 : 1
  project       = var.project_id
  name          = "${local.name}-https"
  network       = local.network
  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["${local.name}-gateway"]
  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
}

resource "google_compute_firewall" "iap_ssh" {
  count         = var.allow_iap_ssh ? 1 : 0
  project       = var.project_id
  name          = "${local.name}-iap-ssh"
  network       = local.network
  direction     = "INGRESS"
  source_ranges = ["35.235.240.0/20"] # Identity-Aware Proxy's TCP forwarding
  target_tags   = ["${local.name}-gateway"]
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_address" "gateway" {
  count      = local.relay ? 0 : 1
  project    = var.project_id
  name       = "${local.name}-ip"
  region     = local.region
  labels     = local.labels
  depends_on = [google_project_service.apis]
}

# --- the records disk: encrypted, snapshotted daily, kept when the machine is replaced ---

resource "google_compute_disk" "records" {
  project = var.project_id
  name    = "${local.name}-records"
  zone    = var.zone
  type    = "pd-balanced"
  size    = var.records_disk_gb
  labels  = local.labels
  dynamic "disk_encryption_key" {
    for_each = var.disk_kms_key == "" ? [] : [var.disk_kms_key]
    content {
      kms_key_self_link = disk_encryption_key.value
    }
  }
  depends_on = [google_project_service.apis]
}

resource "google_compute_resource_policy" "backups" {
  project = var.project_id
  name    = "${local.name}-daily"
  region  = local.region
  snapshot_schedule_policy {
    schedule {
      daily_schedule {
        days_in_cycle = 1
        start_time    = var.backup_time_utc
      }
    }
    retention_policy {
      max_retention_days    = var.backup_retention_days
      on_source_disk_delete = "KEEP_AUTO_SNAPSHOTS"
    }
    snapshot_properties {
      labels      = local.labels
      guest_flush = false
    }
  }
  depends_on = [google_project_service.apis]
}

resource "google_compute_disk_resource_policy_attachment" "backups" {
  project = var.project_id
  name    = google_compute_resource_policy.backups.name
  disk    = google_compute_disk.records.name
  zone    = var.zone
}

# --- the machine ---

resource "google_compute_instance" "gateway" {
  project      = var.project_id
  name         = "${local.name}-gateway"
  zone         = var.zone
  machine_type = var.machine_type
  tags         = ["${local.name}-gateway"]
  labels       = local.labels

  boot_disk {
    initialize_params {
      image = var.source_image
      size  = 10
      type  = "pd-balanced"
    }
  }

  attached_disk {
    source      = google_compute_disk.records.id
    device_name = local.device
  }

  network_interface {
    subnetwork = local.subnetwork
    dynamic "access_config" {
      for_each = var.public_ip ? [1] : []
      content {
        nat_ip = local.relay ? null : google_compute_address.gateway[0].address
      }
    }
  }

  service_account {
    email  = google_service_account.gateway.email
    scopes = ["cloud-platform"] # what it may do is limited by its roles above
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    enable-oslogin         = "TRUE"
    block-project-ssh-keys = "TRUE"
    google-logging-enabled = "true"
  }

  # Settings live in the startup script: changing them replaces the machine (the disk and the key carry over).
  metadata_startup_script = templatefile("${path.module}/templates/startup.sh.tftpl", {
    project          = var.project_id
    mode             = var.address_mode
    gateway_image    = var.gateway_image
    caddy_image      = local.caddy_image
    relay_image      = local.relay_image
    key_secret       = local.secrets["key"]
    directory_secret = local.secrets["directory"]
    license_secret   = local.secrets["license"]
    disk_device      = local.device
    portward_toml    = local.portward_toml
    caddyfile        = local.caddyfile
    relay_toml       = local.relay_toml
    auto_update      = var.auto_update != "off"
  })

  allow_stopping_for_update = true

  depends_on = [
    terraform_data.checks,
    google_project_iam_member.logs,
    google_secret_manager_secret_iam_member.read,
    google_secret_manager_secret_iam_member.generate_key,
    google_compute_disk_resource_policy_attachment.backups,
  ]
}
