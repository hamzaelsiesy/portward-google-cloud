# --- Where -------------------------------------------------------------------------------------------------------

variable "project_id" {
  type        = string
  description = "The Google Cloud project to deploy the gateway into."
}

variable "goog_cm_deployment_name" {
  type        = string
  default     = "portward"
  description = "Name of this deployment; every resource's name starts with it."
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,18}[a-z0-9])?$", var.goog_cm_deployment_name))
    error_message = "Lower-case letters, digits and dashes, starting with a letter, at most 20 characters."
  }
}

variable "zone" {
  type        = string
  default     = "us-central1-a"
  description = "The zone for the gateway machine and its records disk."
}

variable "machine_type" {
  type        = string
  default     = "e2-small"
  description = "The gateway's machine. e2-small (2 shared vCPUs, 2 GB) is enough for a team; e2-medium for heavy use."
}

variable "source_image" {
  type        = string
  default     = "projects/cos-cloud/global/images/family/cos-stable"
  description = "The machine image: any image with Docker and the Google guest environment (Container-Optimized OS)."
}

# --- Address -----------------------------------------------------------------------------------------------------

variable "address_mode" {
  type        = string
  default     = "relay"
  description = <<-EOT
    How Claude and ChatGPT reach the gateway. "relay": through the Portward relay at https://<name>.gw.portward.ai (the name in your license key)
    (the gateway connects out; nothing opens inbound; the relay passes traffic through still encrypted). "own-domain":
    at https://<domain> on a static IP with ports 80 and 443 open (point the domain's DNS at the ip_address output).
  EOT
  validation {
    condition     = contains(["relay", "own-domain"], var.address_mode)
    error_message = "address_mode is \"relay\" or \"own-domain\"."
  }
}

variable "license_key" {
  type        = string
  sensitive   = true
  description = <<-EOT
    Your Portward license key, from signing up at portward.ai (pwlic_...). It pulls the image, it is the relay key,
    and its middle part is your relay name: the gateway is then https://<name>.gw.portward.ai. Kept in Secret Manager.
  EOT
  validation {
    condition     = can(regex("^pwlic_[a-z0-9][a-z0-9-]{1,40}_[0-9a-f]{64}$", var.license_key))
    error_message = "A Portward license key: pwlic_<name>_<64 hex characters>."
  }
}

variable "domain" {
  type        = string
  default     = ""
  description = "Own-domain mode: the gateway's address, such as portward.example.com (no https://)."
  validation {
    condition     = var.domain == "" || can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", var.domain))
    error_message = "A host name such as portward.example.com, without https://."
  }
}

variable "relay_host" {
  type        = string
  default     = "relay.portward.ai"
  description = "Relay mode: the relay the gateway connects out to."
}

variable "relay_domain" {
  type        = string
  default     = "gw.portward.ai"
  description = "Relay mode: the domain the relay gives addresses under."
}

# --- Sign-in -----------------------------------------------------------------------------------------------------

variable "directory_issuer" {
  type        = string
  description = <<-EOT
    Your company directory's sign-in address (its OpenID Connect issuer), exactly as its
    /.well-known/openid-configuration states it: https://login.microsoftonline.com/<tenant id>/v2.0 (Entra),
    https://<org>.okta.com (Okta), https://accounts.google.com (Google Workspace).
  EOT
  validation {
    condition     = can(regex("^https://[A-Za-z0-9.-]+(:[0-9]+)?(/[A-Za-z0-9._~%/-]*)?$", var.directory_issuer))
    error_message = "A plain https address, such as https://accounts.google.com."
  }
}

variable "directory_client_id" {
  type        = string
  description = "The client id of the app registered in your directory for the gateway (redirect address: the redirect_uri output)."
  validation {
    condition     = can(regex("^[A-Za-z0-9._:@/-]{1,200}$", var.directory_client_id))
    error_message = "The client id as your directory shows it."
  }
}

variable "directory_client_secret" {
  type        = string
  default     = ""
  sensitive   = true
  description = <<-EOT
    The app's client secret. Leave empty to keep it out of Terraform's state and add it to Secret Manager yourself
    (the directory_secret output says how); the gateway waits for it.
  EOT
}

variable "admin_groups" {
  type        = list(string)
  default     = []
  description = "Directory groups whose members manage Portward, as your directory sends them (Entra: group object ids)."
}

variable "admin_subjects" {
  type        = list(string)
  default     = []
  description = "People who manage Portward, by sign-in id (the gateway's log names someone refused) or email."
}

variable "user_groups" {
  type        = list(string)
  default     = []
  description = "Directory groups whose members may ask questions of the data."
}

variable "users" {
  type        = list(string)
  default     = []
  description = "People who may ask questions of the data: sign-in ids, verified emails or \"@yourcompany.com\". With user_groups empty too: admins only."
}

variable "directory_scopes" {
  type        = list(string)
  default     = []
  description = "Extra sign-in scopes your directory needs to send groups (Okta: [\"groups\"])."
}

variable "setup_hosts" {
  type        = list(string)
  default     = []
  description = "Database hosts admins may connect from the setup form in Claude or ChatGPT (exact names, or \"*.corp.example\")."
}

# --- Image and storage -------------------------------------------------------------------------------------------

variable "gateway_image" {
  type        = string
  default     = "registry.portward.ai/portward/gateway:main"
  description = "The gateway's container image: from Portward's registry with the license key, or from Artifact Registry with the machine's own identity."
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]*(:[A-Za-z0-9._-]+)?(@sha256:[0-9a-f]{64})?$", var.gateway_image))
    error_message = "An image name such as registry/portward/gateway:main."
  }
}

variable "records_disk_gb" {
  type        = number
  default     = 10
  description = "Size of the encrypted disk holding the gateway's records, setup and saved connections."
}

variable "disk_kms_key" {
  type        = string
  default     = ""
  description = "Optional: a Cloud KMS key (projects/.../cryptoKeys/...) to encrypt the records disk with, instead of Google's."
}

variable "backup_retention_days" {
  type        = number
  default     = 14
  description = "How many days the records disk's daily snapshots are kept. Snapshots are kept when the disk is deleted."
}

variable "backup_time_utc" {
  type        = string
  default     = "03:00"
  description = "When the daily snapshot starts (UTC, on the hour)."
}

variable "keep_key_on_destroy" {
  type        = bool
  default     = true
  description = <<-EOT
    Protect the gateway key in Secret Manager from deletion. The key opens the saved connections in the records and
    their snapshots: without it, a restored snapshot can't be used. Set false (and apply) before removing everything.
  EOT
}

# --- Network -----------------------------------------------------------------------------------------------------

variable "subnetwork" {
  type        = string
  default     = ""
  description = <<-EOT
    Optional: an existing subnetwork (projects/<p>/regions/<r>/subnetworks/<name>) to run in, such as the one that
    reaches your databases. Empty: a new network with no inbound access except what address_mode needs.
  EOT
}

variable "public_ip" {
  type        = bool
  default     = true
  description = "Give the machine a public IP for its outbound connections. Set false only if the subnetwork has Cloud NAT."
}

variable "allow_iap_ssh" {
  type        = bool
  default     = false
  description = "Allow SSH through Identity-Aware Proxy (for gcloud compute ssh --tunnel-through-iap). Off: no SSH at all."
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "Labels added to every resource."
}
