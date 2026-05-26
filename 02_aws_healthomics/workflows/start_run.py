"""
Start an AWS HealthOmics workflow run.

A workflow run:
  - Associates a workflow definition with specific input parameters and a role
  - Provisions compute automatically (no EC2 management)
  - Streams logs to CloudWatch at /aws/omics/WorkflowLog/<run-id>
  - Outputs go to the S3 location you specify in --output-uri

Run storage tiers (--storage-type):
  - STATIC: Fixed storage allocated upfront; predictable cost; good for large inputs
  - DYNAMIC: Storage scales with actual usage; good for variable workflows

Usage:
  python start_run.py \\
    --workflow-id <id> \\
    --role-arn arn:aws:iam::123456789:role/HealthOmicsWorkflowRole \\
    --output-uri s3://my-bucket/results/ \\
    --reads "s3://my-bucket/reads/*_R{1,2}.fastq.gz" \\
    --reference omics://123456789/referencestore/store-id/source/ref-id \\
    --known-sites s3://my-bucket/resources/dbsnp_chr20.vcf.gz
"""

import argparse
import json
import boto3


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--region", default="us-east-1")
    p.add_argument("--workflow-id", required=True)
    p.add_argument("--role-arn", required=True,
                   help="IAM role ARN that HealthOmics assumes to run the workflow")
    p.add_argument("--output-uri", required=True,
                   help="S3 URI prefix for workflow outputs (e.g. s3://bucket/runs/)")
    p.add_argument("--reads", required=True)
    p.add_argument("--reference", required=True)
    p.add_argument("--known-sites", required=True)
    p.add_argument("--run-name", default="wgs-germline-run")
    p.add_argument("--storage-type", choices=["STATIC", "DYNAMIC"], default="DYNAMIC")
    return p.parse_args()


def main():
    args = parse_args()
    client = boto3.client("omics", region_name=args.region)

    parameters = {
        "reads": args.reads,
        "reference": args.reference,
        "known_sites": args.known_sites,
        "outdir": args.output_uri,
    }

    print("Starting HealthOmics workflow run...")
    print(f"  Workflow: {args.workflow_id}")
    print(f"  Parameters: {json.dumps(parameters, indent=4)}")

    response = client.start_run(
        workflowId=args.workflow_id,
        workflowType="PRIVATE",
        name=args.run_name,
        roleArn=args.role_arn,
        parameters=parameters,
        outputUri=args.output_uri,
        storageType=args.storage_type,
        tags={"project": "wgs-study"},
    )

    run_id = response["id"]
    run_arn = response["arn"]

    print(f"\nRun started!")
    print(f"  Run ID:  {run_id}")
    print(f"  Run ARN: {run_arn}")
    print(f"  Status:  {response['status']}")
    print(f"\nMonitor with: python monitor_run.py --run-id {run_id}")
    print(f"Logs: aws logs tail /aws/omics/WorkflowLog --follow")


if __name__ == "__main__":
    main()
