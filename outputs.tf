output "gateway_url" {
  description = "The gateway's address."
  value       = local.base_url
}

output "data_connector" {
  description = "Add in Claude or ChatGPT, for people asking questions."
  value       = "${local.base_url}/mcp"
}

output "admin_connector" {
  description = "Add in Claude or ChatGPT, for admins (setup and what the AI may see)."
  value       = "${local.base_url}/admin/mcp"
}

output "redirect_uri" {
  description = "The redirect address of the app registered in your directory."
  value       = "${local.base_url}/auth/callback"
}

output "ip_address" {
  description = "Own-domain mode: point the domain's DNS A record here. Relay mode: none (nothing opens inbound)."
  value       = local.relay ? null : google_compute_address.gateway[0].address
}

output "secrets_to_add" {
  description = "Secrets the deployment left empty: add each with the command shown; the gateway waits for them."
  value = {
    for k, id in local.secrets : id => "gcloud secrets versions add ${id} --project ${var.project_id} --data-file=<file>"
    if k != "key" && !contains(local.given, k)
  }
}

output "key_secret" {
  description = "The gateway key, generated on the machine at first start. Back it up apart from the records."
  value       = google_secret_manager_secret.secrets["key"].secret_id
}

output "logs" {
  description = "The containers' logs in Cloud Logging (a refused sign-in names the id to add to admin_subjects or users)."
  value       = "https://console.cloud.google.com/logs/query;query=resource.labels.instance_id%3D%22${google_compute_instance.gateway.instance_id}%22%20logName%3D%22projects%2F${var.project_id}%2Flogs%2Fcos_containers%22?project=${var.project_id}"
}

output "machine" {
  description = "The gateway machine."
  value       = google_compute_instance.gateway.name
}
