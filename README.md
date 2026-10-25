# Portward gateway on Google Cloud

Deploys the Portward gateway into your own Google Cloud project: one Compute Engine machine (Container-Optimized OS)
running the gateway, its records on an encrypted persistent disk snapshotted daily, its key generated on the machine
into your Secret Manager, and a new network with nothing open inbound. People sign in with your company directory.
The step-by-step guide for IT is [docs/deploy-gcp.md](../../docs/deploy-gcp.md).

## Usage

```hcl
module "portward" {
  source              = "./deploy/gcp"
  project_id          = "your-project"
  license_key         = var.portward_license        # pwlic_yourco_...: https://yourco.gw.portward.ai, via the relay
  directory_issuer    = "https://accounts.google.com"
  directory_client_id = "123.apps.googleusercontent.com"
  admin_subjects      = ["you@yourco.com"]
  users               = ["@yourco.com"]
}
```

Or at your own address: `address_mode = "own-domain"`, `domain = "portward.yourco.com"`, then point the domain at
the `ip_address` output.

Secrets left empty here stay out of Terraform's state: add them to Secret Manager with the commands in the
`secrets_to_add` output, and the gateway starts once they're there.
