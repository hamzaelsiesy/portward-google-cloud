# Portward on Google Cloud: your values. Fill in the lines marked <...>, save, and go back to the tutorial.
# The project comes from the tutorial; the license key and the directory secret are NOT here: the tutorial reads
# them into the terminal, hidden.

zone                = "us-central1-a"             # near your databases

# The app you registered in your directory, with redirect address https://<name>.gw.portward.ai/auth/callback
directory_issuer    = "<issuer>"                  # Entra: https://login.microsoftonline.com/<tenant id>/v2.0
                                                  # Okta: https://<org>.okta.com   Google: https://accounts.google.com
directory_client_id = "<client id>"

# Who manages Portward and who may ask questions. Groups as your directory sends them (Entra: group Object IDs);
# with Google Workspace, use admin_subjects = ["you@yourcompany.com"] and users = ["@yourcompany.com"] instead.
admin_groups        = ["<admin group>"]
user_groups         = []
admin_subjects      = []
users               = []
directory_scopes    = []                          # Okta: ["groups"]

# Database hosts admins may connect later (exact names, or "*.corp.example"). Empty is fine to start.
setup_hosts         = []
