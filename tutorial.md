# Deploy Portward on Google Cloud

<walkthrough-tutorial-duration duration="10"></walkthrough-tutorial-duration>

This puts the Portward gateway in your own Google Cloud project with one `terraform apply`: a small machine (e2-small),
an encrypted records disk snapshotted every day, its key in your Secret Manager, and a new network with nothing open
inbound. About $18 a month. Nobody from Portward gets access to your project.

You need your **Portward license key** (`pwlic_…`, from signing up) and the **sign-in app** you registered in your
company directory, with redirect address `https://<name>.gw.portward.ai/auth/callback` (the name in your key).

Click **Start**.

## Sign in

Cloud Shell opened this in a temporary session that can't use your account until you sign in here. Run this and
follow the link it prints:

```sh
gcloud auth login --update-adc
```

## Choose the project

<walkthrough-project-setup billing="true"></walkthrough-project-setup>

```sh
export TF_VAR_project_id=<walkthrough-project-id/>
gcloud config set project "$TF_VAR_project_id"
gcloud services enable compute.googleapis.com secretmanager.googleapis.com logging.googleapis.com storage.googleapis.com
```

This session's files are deleted when it ends, so Terraform keeps its state in a private bucket in your project:

```sh
STATE_BUCKET="$TF_VAR_project_id-portward-state"
gcloud storage buckets create "gs://$STATE_BUCKET" --location=us --uniform-bucket-level-access \
  --public-access-prevention || echo "(using the existing bucket)"
gcloud storage buckets update "gs://$STATE_BUCKET" --versioning
```

## Your values

Open <walkthrough-editor-open-file filePath="portward.auto.tfvars">portward.auto.tfvars</walkthrough-editor-open-file>
and fill in the lines marked `<...>`: your directory's issuer and client id, and who manages Portward. Save it
(Ctrl+S or Cmd+S).

## Your license key and directory secret

Paste each when asked, then press Enter. Nothing shows as you paste, and neither goes into a file or your shell
history.

```sh
read -rsp "License key: " TF_VAR_license_key && export TF_VAR_license_key && echo
read -rsp "Directory app's client secret: " TF_VAR_directory_client_secret && export TF_VAR_directory_client_secret && echo
```

Both go into Secret Manager in your project. Terraform's state in your state bucket holds them too: only people with
access to that bucket can read it.

## Deploy

```sh
terraform init -input=false -backend-config="bucket=$STATE_BUCKET" -backend-config="prefix=portward"
terraform apply
```

Check the plan, then type `yes`. It takes about three minutes, then the machine starts the gateway (another two while
it gets its certificate).

## Check it and connect

```sh
curl -s "$(terraform output -raw gateway_url)/health"
terraform output admin_connector
```

`/health` answers `"ok": true`. Then, in Claude (**Settings → Connectors → Add custom connector**) or ChatGPT, add
the `admin_connector` address and sign in with your work account. From there, ask **"Set up a connection."**

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

Portward is running in your project. To change a setting later, open this tutorial again from the same button, keep
the same project and state bucket, edit `portward.auto.tfvars` the same way, and run `terraform apply`.
