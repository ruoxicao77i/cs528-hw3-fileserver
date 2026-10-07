# CS528 Homework 3: Microservices on Google Cloud

**Ruoxi Cao** (ruoxicao@bu.edu)

**Source code:** https://github.com/ruoxicao77i/cs528-hw3-fileserver.git

|                 |                                                              |
| --------------- | ------------------------------------------------------------ |
| Project         | `tonal-plateau-508118-g0`                                    |
| Region          | `us-central1`                                                |
| Bucket          | `cs528-ruoxi-pagerank`                                       |
| Service URL     | https://file-server-497093194910.us-central1.run.app         |
| Service account | `hw3-file-server@tonal-plateau-508118-g0.iam.gserviceaccount.com` |

## 1. Overview

Two cooperating services, both running as the same dedicated service account:

- **Service 1, `file-server`** (Cloud Run function): serves files from the bucket over HTTP.
- **Service 2, `forbidden-logger`** (runs on my laptop): receives a Pub/Sub message for every blocked request, prints it, and appends it to a file in the bucket.

| Request                             | Status | Comments                     |
| ----------------------------------- | ------ | ---------------------------- |
| GET or POST for an existing file    | 200    | none                         |
| GET or POST for a non-existent file | 404    | structured log + `print`     |
| Any other HTTP method               | 501    | structured log + `print`     |
| Request from a forbidden country    | 400    | message published to Pub/Sub |

## 2. Setup and Deployment

### Service account and permissions

```bash
gcloud iam service-accounts create <SA_NAME> --display-name="HW3 file server"

SA_EMAIL="hw3-file-server@tonal-plateau-508118-g0.iam.gserviceaccount.com"

gcloud storage buckets add-iam-policy-binding gs://cs528-ruoxi-pagerank \
    --member="serviceAccount:$SA_EMAIL" --role="roles/storage.objectViewer"

gcloud projects add-iam-policy-binding tonal-plateau-508118-g0 \
    --member="serviceAccount:$SA_EMAIL" --role="roles/logging.logWriter"
    
gcloud pubsub topics add-iam-policy-binding forbidden-requests \
    --member="serviceAccount:$SA_EMAIL" --role="roles/pubsub.publisher"
    
gcloud pubsub subscriptions add-iam-policy-binding forbidden-requests-sub \
    --member="serviceAccount:$SA_EMAIL" --role="roles/pubsub.subscriber"

gcloud storage buckets add-iam-policy-binding gs://cs528-ruoxi-pagerank \
    --member="serviceAccount:$SA_EMAIL" --role="roles/storage.objectUser"
```

| Role                         | Granted on   | Used by   | Purpose                    |
| ---------------------------- | ------------ | --------- | -------------------------- |
| `roles/storage.objectViewer` | bucket       | Service 1 | read requested files       |
| `roles/logging.logWriter`    | project      | Service 1 | write structured logs      |
| `roles/pubsub.publisher`     | topic        | Service 1 | report forbidden requests  |
| `roles/pubsub.subscriber`    | subscription | Service 2 | receive forbidden requests |
| `roles/storage.objectUser`   | bucket       | Service 2 | append to the log file     |

### Pub/Sub

```bash
gcloud services enable pubsub.googleapis.com
gcloud pubsub topics create forbidden-requests
gcloud pubsub subscriptions create forbidden-requests-sub --topic forbidden-requests
```

### Deploying Service 1

```bash
gcloud run deploy file-server \
    --source file-server \
    --function file_server \
    --base-image python313 \
    --region us-central1 \
    --service-account <SA_EMAIL> \
    --allow-unauthenticated
```

`--service-account` makes the function run as the dedicated account instead of the default compute service account.

## 3. Service 1: File Server (Steps 1-3)

### Request format

**GET**: the file is given in the URL path as `/<bucket>/<object-name>`. The path is split at the first slash only, because object names can contain slashes.

```
GET /cs528-ruoxi-pagerank/pages/1.html
```

**POST**: the file is given in a JSON payload, in the same `<bucket>/<object-name>` form.

```
POST /
Content-Type: application/json

{"file": "cs528-ruoxi-pagerank/pages/1.html"}
```

### Errors and logging

- **404**: If the requested file cannot be found, the server will return 404. The situation includes non-existent files and incomplete or wrong filenames.

  ![image-20261006231802800](/Users/ruoxicao/Library/Application Support/typora-user-images/image-20261006231802800.png)

- **501**: every method other than GET and POST. 

  ![image-20261006231830577](/Users/ruoxicao/Library/Application Support/typora-user-images/image-20261006231830577.png)

Each 404 and 501 is logged twice: with a plain `print`, and as a structured entry through the Cloud Logging client library (fields `status`, `method`, `path`, `target`, `user_agent`; severity `WARNING`).

The output of `print`:

![image-20261006232027530](/Users/ruoxicao/Library/Application Support/typora-user-images/image-20261006232027530.png)

## 4. Demonstrations (Steps 4-6)

### Provided HTTP client, 100 requests

The provided client sends GET requests only. For each request it picks a random page from the bucket and adds an `X-country` header with a random country.

```bash
client/http-client -d file-server-497093194910.us-central1.run.app \
    -p 443 -s -b /cs528-ruoxi-pagerank -w pages -i 12000 -n 100
```

The client prints nothing unless `-v` is given.

Most of the 100 requests returned 200 and others returned 400. The 400 responses are the requests whose `X-country` header named a forbidden country. They were rejected by the country check added in step 7 (see Section 5), and each one was reported to Service 2 and written to the log file in the bucket.

To see what a single exchange looks like, the same command can be run with `-n 1 -v`, which prints the server's response:

```bash
client/http-client -d file-server-497093194910.us-central1.run.app \
    -p 443 -s -b /cs528-ruoxi-pagerank -w pages -i 12000 -n 1 -v
```

A normal request returns 200 and the content of the page:

![image-20261006233451790](/Users/ruoxicao/Library/Application Support/typora-user-images/image-20261006233451790.png)A request from a forbidden country returns 400:

![image-20261006233522759](/Users/ruoxicao/Library/Application Support/typora-user-images/image-20261006233522759.png)

### curl

```bash
URL=https://file-server-497093194910.us-central1.run.app

# GET, existing file -> 200
curl -i $URL/cs528-ruoxi-pagerank/pages/1.html

# POST, existing file -> 200
curl -i -X POST $URL -H "Content-Type: application/json" \
    -d '{"file": "cs528-ruoxi-pagerank/pages/1.html"}'

# Non-existent file -> 404
curl -i $URL/cs528-ruoxi-pagerank/pages/non-existent.html

# Unsupported method -> 501
curl -i -X PUT $URL/cs528-ruoxi-pagerank/pages/1.html
```

- Get an existent file with GET

![image-20261006220256395](/Users/ruoxicao/Library/Application Support/typora-user-images/image-20261006220256395.png)

- Get an existent file with POST

  ![image-20261006220536431](/Users/ruoxicao/Library/Application Support/typora-user-images/image-20261006220536431.png)

- Try to get a non-existent file

  ![image-20261006220633386](/Users/ruoxicao/Library/Application Support/typora-user-images/image-20261006220633386.png)

- Try to use an unimplemented function call

  ![image-20261006220718764](/Users/ruoxicao/Library/Application Support/typora-user-images/image-20261006220718764.png)

### Browser

- **Get an existing file: The browser shows the page(7845.html) normally.**

![image-20261006220804739](/Users/ruoxicao/Library/Application Support/typora-user-images/image-20261006220804739.png)

- **When we use POST:**

  ![image-20261006221512749](/Users/ruoxicao/Library/Application Support/typora-user-images/image-20261006221512749.png)

- **When you are trying to get an non-existent file, the console respond 404.**

![image-20261006221711230](/Users/ruoxicao/Library/Application Support/typora-user-images/image-20261006221711230.png)

- **Unsupported methods:**

  ![image-20261006221633472](/Users/ruoxicao/Library/Application Support/typora-user-images/image-20261006221633472.png)

## 5. Forbidden Countries and Pub/Sub (Step 7)

The provided client sends the source country in the `X-country` header. Service 1 reads this header and compares it with a list of nine forbidden countries: North Korea, Iran, Cuba, Myanmar, Iraq, Libya, Sudan, Zimbabwe and Syria. The comparison ignores upper and lower case and extra spaces. If the country is on the list, Service 1 returns **400 Permission denied** and does not read the file from the bucket. A request without the header, for example from a browser, is treated as allowed.

The two services communicate through Pub/Sub. For every rejected request, Service 1 publishes one message to the topic `forbidden-requests`. The message is a JSON object with four fields: the country, the HTTP method, the requested file, and the time. Service 1 waits until Pub/Sub has accepted the message before it sends the 400 response. Cloud Run may stop the CPU of the function after the response is sent, so a message that is still being sent in the background could be lost.

Service 2 runs on my laptop and listens on the subscription `forbidden-requests-sub`. For every message it does 2 things: 

- It prints an error line on standard output, for example   `[time] ERROR: forbidden request from Iran: GET cs528-ruoxi-pagerank/pages/1.html`. 
- It appends the same line to `forbidden/forbidden-requests.log` in the bucket. This  is a separate directory from `pages/`, where the served files are. 

```bash
curl -i -H "X-country: <FORBIDDEN_COUNTRY>" \
    https://file-server-497093194910.us-central1.run.app/cs528-ruoxi-pagerank/pages/1.html
```

![image-20261006221948482](/Users/ruoxicao/Library/Application Support/typora-user-images/image-20261006221948482.png)

Service 2 received the above illegal request and logged it.

![The log file in the bucket](/Users/ruoxicao/Library/Application Support/typora-user-images/image-20261006223630496.png)

After sending 100 GET requests using `http-client`, we found 4 error messages in the log file.

![image-20261006225203654](/Users/ruoxicao/Library/Application Support/typora-user-images/image-20261006225203654.png)

## 6. Running Service 2 Locally as the Service Account (Step 8)

- **Options**

Google's page [Set up ADC for a local development environment](https://docs.cloud.google.com/docs/authentication/set-up-adc-local-dev-environment) describes three ways to give credentials to a program running on a laptop:

1. **User credentials** (`gcloud auth application-default login`): the program runs as my own Google account.
2. **Service account impersonation**: my user account requests short-lived tokens for the service account.
3. **Service account key**: a JSON file that contains the service account's private key.

Option 1 is not allowed for this homework. My account is the project owner, so the program would have far more permissions than it needs. I use a **service account key** (option 3). 

```bash 
gcloud iam service-accounts keys create keys/hw3-sa.json --iam-account=<SA_EMAIL> 

export GOOGLE_APPLICATION_CREDENTIALS="$(pwd)/keys/hw3-sa.json" 
python forbidden-logger/main.py
```

- **How it works**

  My code contains no credentials. It only creates clients, for example `storage.Client()` and `pubsub_v1.SubscriberClient()`. When a client is created, Google's authentication library (`google-auth`) looks for credentials using Application Default Credentials (ADC). ADC checks the `GOOGLE_APPLICATION_CREDENTIALS` environment variable first, so it finds my key file. The key file contains the information of the private key, which confirms my identification without accessing my personal account. Therefore it is important to keep it secret.

- **Why I picked it** 
  - It is the simpler of the two allowed options. It needs one command and one  environment variable.
  - Impersonation needs extra setup: the Service Account Token Creator role for my user  account and the IAM Credentials API. 
  - It does not depend on my `gcloud` login, so the program runs the same way in any terminal.


## 7. How to Run Everything

```bash
bash scripts/setup.sh                    # service account, roles, Pub/Sub
bash scripts/run-cloud.sh                # deploy Service 1
python forbidden-logger/main.py          # start Service 2 on the laptop
bash scripts/test_curl.sh cloud          # curl tests
bash scripts/test_client.sh cloud 100    # provided client
```
