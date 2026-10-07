# CS528 HW3: Microservices on Google Cloud

Two small services:

- **`file-server/`**: a Cloud Run function that serves files from a Cloud Storage bucket over HTTP (GET and POST). It returns 404 for missing files, 501 for other methods, and 400 for requests from forbidden countries.
- **`forbidden-logger/`**: a local program that receives the forbidden requests through Pub/Sub, prints them, and appends them to a log file in the bucket.

## Requirements

- Python 3 and the `gcloud` CLI, logged in to a Google Cloud project
- A bucket with the files to serve
- A service account, with a key file saved at `keys/hw3-sa.json`

Install the Python packages:

```bash
python -m venv .myenv
source .myenv/bin/activate
pip install -r file-server/requirements.txt -r forbidden-logger/requirements.txt
```

## One-time setup

```bash
PROJECT_ID=<your-project-id>
BUCKET=<your-bucket>
SA_EMAIL=<service-account>@$PROJECT_ID.iam.gserviceaccount.com

# Pub/Sub
gcloud pubsub topics create forbidden-requests
gcloud pubsub subscriptions create forbidden-requests-sub --topic forbidden-requests

# Permissions for the service account
gcloud storage buckets add-iam-policy-binding gs://$BUCKET \
    --member="serviceAccount:$SA_EMAIL" --role="roles/storage.objectUser"
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SA_EMAIL" --role="roles/logging.logWriter"
gcloud pubsub topics add-iam-policy-binding forbidden-requests \
    --member="serviceAccount:$SA_EMAIL" --role="roles/pubsub.publisher"
gcloud pubsub subscriptions add-iam-policy-binding forbidden-requests-sub \
    --member="serviceAccount:$SA_EMAIL" --role="roles/pubsub.subscriber"
```

## Run

**1. Deploy the file server to Cloud Run**

```bash
bash scripts/run-cloud.sh
```

**2. Start the forbidden-request logger on your laptop**

```bash
# Generate the key with the service account
export GOOGLE_APPLICATION_CREDENTIALS="$(pwd)/keys/hw3-sa.json"
python forbidden-logger/main.py
```

Leave it running. It prints one line for every forbidden request.

To run the file server locally instead of on Cloud Run (port 8080):

```bash
bash scripts/run-local.sh
```

## Test

```bash
bash scripts/test_curl.sh cloud          # GET, POST, 404, 501 against Cloud Run
bash scripts/test_curl.sh                # the same against localhost:8080
bash scripts/test_client.sh cloud 100    # 100 requests with the course client
```

A request from a forbidden country:

```bash
URL=$(gcloud run services describe file-server --region us-central1 --format='value(status.url)')
curl -i -H "X-country: Iran" $URL/<your-bucket>/pages/1.html
```

See what the logger wrote to the bucket:

```bash
gcloud storage cat gs://<your-bucket>/forbidden/forbidden-requests.log
```

## Request format

```bash
# GET: the file is in the path
curl $URL/<bucket>/<object>

# POST: the file is in a JSON payload
curl -X POST $URL -H "Content-Type: application/json" -d '{"file": "<bucket>/<object>"}'
```

## Not in this repository

- `keys/`: the service account key. Create your own and never commit it.
- `client/http-client`: the HTTP client provided by the course. Place it at this path before running `scripts/test_client.sh`.