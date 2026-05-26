"""
Poll an AWS HealthOmics workflow run until it completes and print a task timeline.

Run statuses:
  PENDING       → Waiting for resources to be allocated
  STARTING      → Initializing the workflow executor
  RUNNING       → Tasks are executing
  STOPPING      → Received a stop request
  COMPLETED     → All tasks finished successfully
  DELETED       → Run was deleted
  CANCELLED     → Run was cancelled before completion
  FAILED        → One or more tasks failed

Task-level statuses (visible in get_run_task):
  PENDING, STARTING, RUNNING, STOPPED, COMPLETED, FAILED

Usage:
  python monitor_run.py --run-id <run-id>
  python monitor_run.py --run-id <run-id> --poll-interval 30
"""

import argparse
import time
from datetime import datetime, timezone

import boto3


TERMINAL_STATUSES = {"COMPLETED", "FAILED", "CANCELLED", "DELETED"}


def format_duration(start, end=None) -> str:
    if end is None:
        end = datetime.now(timezone.utc)
    if not start:
        return "—"
    delta = end - start
    minutes, seconds = divmod(int(delta.total_seconds()), 60)
    return f"{minutes}m {seconds}s"


def print_run_summary(run: dict) -> None:
    print(f"\n{'='*60}")
    print(f"Run ID:     {run['id']}")
    print(f"Name:       {run.get('name', '—')}")
    print(f"Status:     {run['status']}")
    print(f"Started:    {run.get('startTime', '—')}")
    print(f"Duration:   {format_duration(run.get('startTime'), run.get('stopTime'))}")
    if run["status"] == "FAILED":
        print(f"Failure:    {run.get('statusMessage', 'No details available')}")
    print(f"{'='*60}\n")


def print_tasks(client, run_id: str) -> None:
    paginator = client.get_paginator("list_run_tasks")
    tasks = []
    for page in paginator.paginate(id=run_id):
        tasks.extend(page.get("items", []))

    if not tasks:
        print("No tasks found.")
        return

    print(f"{'Task Name':<30} {'Status':<12} {'Duration'}")
    print("-" * 60)
    for task in sorted(tasks, key=lambda t: t.get("startTime") or ""):
        detail = client.get_run_task(id=run_id, taskId=task["taskId"])
        name = detail.get("name", task["taskId"])[:30]
        status = detail.get("status", "—")
        duration = format_duration(detail.get("startTime"), detail.get("stopTime"))
        print(f"{name:<30} {status:<12} {duration}")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--region", default="us-east-1")
    p.add_argument("--run-id", required=True)
    p.add_argument("--poll-interval", type=int, default=20,
                   help="Seconds between status polls (default: 20)")
    args = p.parse_args()

    client = boto3.client("omics", region_name=args.region)

    print(f"Monitoring run: {args.run_id}")
    print(f"Polling every {args.poll_interval}s — press Ctrl+C to stop watching")

    last_status = None
    while True:
        run = client.get_run(id=args.run_id)
        status = run["status"]

        if status != last_status:
            ts = datetime.now().strftime("%H:%M:%S")
            print(f"[{ts}] Status: {status}")
            last_status = status

        if status in TERMINAL_STATUSES:
            print_run_summary(run)
            print("Task timeline:")
            print_tasks(client, args.run_id)
            break

        time.sleep(args.poll_interval)


if __name__ == "__main__":
    main()
