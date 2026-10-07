#!/bin/bash

# create the service account
gcloud iam service-accounts create hw3-file-server \
    --display-name="HW3 file server"

# grant the role
SA_EMAIL="hw3-file-server@tonal-plateau-508118-g0.iam.gserviceaccount.com"

gcloud storage buckets add-iam-policy-binding gs://cs528-ruoxi-pagerank \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/storage.objectViewer"

# create keys (once)
mkdir -p ~/.gcp-keys

gcloud iam service-accounts keys create ~/.gcp-keys/hw3-sa.json \
    --iam-account="$SA_EMAIL"

chmod 600 ~/.gcp-keys/hw3-sa.json 

# logging
gcloud projects add-iam-policy-binding tonal-plateau-508118-g0 \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/logging.logWriter"