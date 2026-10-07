import functions_framework
import flask
from google.cloud import storage
from google.cloud.exceptions import NotFound
from google.cloud import logging as cloud_logging
from google.cloud import pubsub_v1
from datetime import datetime, timezone
import json

storage_client = storage.Client()
# logging
logging_client = cloud_logging.Client()
logger = logging_client.logger("file-server")
FORBIDDEN_COUNTRIES = {
    "north korea", "iran", "cuba", "myanmar", "iraq",
    "libya", "sudan", "zimbabwe", "syria",
}
publisher = pubsub_v1.PublisherClient()
topic_path = publisher.topic_path(storage_client.project, "forbidden-requests")

@functions_framework.http
def file_server(request: flask.Request) -> flask.typing.ResponseReturnValue:
    """HTTP Cloud Function.
    Args:
        request (flask.Request): The request object.
        <https://flask.palletsprojects.com/en/1.1.x/api/#incoming-request-data>
    Returns:
        The response text, or any set of values that can be turned into a
        Response object using `make_response`
        <https://flask.palletsprojects.com/en/1.1.x/api/#flask.make_response>.
    Note:
        For more information on how Flask integrates with Cloud
        Functions, see the `Writing HTTP functions` page.
        <https://cloud.google.com/functions/docs/writing/http#http_frameworks>
    """
    if request.method not in ("GET", "POST"):
        log_error(request, 501, "Method not implemented")
        return "Not implemented", 501

    # parse the file name
    bucket_name, blob_name = parse_target(request)
    target = f"{bucket_name}/{blob_name}"

    # block export-restricted countries
    if is_forbidden(request):
        log_error(request, 400, "Forbidden country", target)
        report_forbidden(request, target)
        return "Permission denied", 400
    
    if not bucket_name or not blob_name:
        log_error(request, 404, "File not found", target)
        return "Not found", 404

    # download and return
    try:
        contents = download_blob_into_memory(bucket_name, blob_name)
    except NotFound:
        log_error(request, 404, "File not found", target)
        return "Not found", 404
    return contents, 200

def parse_target(request:flask.Request):
    """get (bucket_name, blob_name) from the request"""
    if request.method == "GET":
        raw = request.path
    else:  # POST: filename is in the payload
        data = request.get_json(silent=True)
        raw = data.get("file", "") if isinstance(data, dict) else ""

    bucket_name, _, blob_name = str(raw).strip().lstrip("/").partition("/")
    return bucket_name, blob_name

def download_blob_into_memory(bucket_name:str, blob_name:str):
    """Downloads a blob into memory."""
    blob = storage_client.bucket(bucket_name).blob(blob_name)
    return blob.download_as_bytes()

def log_error(request:flask.Request, status:int, reason:str, target:str=""):
    """Logged erroneous errors to cloud logging using structured logs and simple print statements."""
    # print
    print(f"{status} {reason}: {request.method} {request.path} {target}")
    logger.log_struct(
        {
            "message": reason,
            "status": status,
            "method": request.method,
            "path": request.path,
            "target": target,
            "user_agent": request.headers.get("User-Agent"),
        },
        severity="WARNING",
    )

def is_forbidden(request: flask.Request) -> bool:
    """True if the X-country header names an export-restricted country."""
    country = request.headers.get("X-country", "")
    return country.strip().lower() in FORBIDDEN_COUNTRIES

def report_forbidden(request: flask.Request, target: str):
    message = {
        "country": request.headers.get("X-country", ""),
        "method": request.method,
        "target": target,
        "time": datetime.now(timezone.utc).isoformat(),
    }
    future = publisher.publish(topic_path, json.dumps(message).encode("utf-8"))
    future.result(timeout=10)