# NetApp BlueXP Connector - GCP Setup

## Get ready
This tutorial guides you through running the GCP setup script from Cloud Shell.
If you are not already in the repo folder, run:

```sh
cd tutorial-repo
```

### Shortcut
If the web app already gave you a setup command, paste it into Cloud Shell now
and press ENTER. You can skip the rest of this tutorial.

## Provide your values
Paste the project ID and email you entered in the web app.
Use the backend domain provided by your admin (without `https://`).

```sh
PROJECT_ID="YOUR_GCP_PROJECT_ID"
CUSTOMER_EMAIL="you@example.com"
CALLBACK_DOMAIN="your-ngrok-url.ngrok-free.app"
```

## Build the URLs
These URLs tell the script where to call back and where to fetch the role file.

```sh
CALLBACK_URL="https://${CALLBACK_DOMAIN}/api/webhooks/setup-complete"
SCRIPT_BASE_URL="https://${CALLBACK_DOMAIN}/api/scripts"
```

## Run the setup script
```sh
bash ./gcp-scripts/setup.sh \
  --project="${PROJECT_ID}" \
  --email="${CUSTOMER_EMAIL}" \
  --callback="${CALLBACK_URL}" \
  --script-base="${SCRIPT_BASE_URL}"
```

## Finish
Return to the web app. It will update when setup completes.
