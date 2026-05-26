"""
Package and register the Nextflow pipeline as an AWS HealthOmics Workflow.

AWS HealthOmics Workflows:
  - Accept a ZIP archive containing the workflow definition files
  - Support Nextflow (DSL2) and WDL natively — no wrapper needed
  - Each registration creates a versioned, immutable workflow with a unique ID
  - Workflows can define typed parameters (parameter template) that are validated
    at run time before the workflow starts

The parameter template (--parameter-template) describes the expected inputs:
  - Required vs optional
  - Type hints (String, File, Int, Float, Boolean)
  - Description shown in the console

Usage:
  python register_workflow.py
  python register_workflow.py --region eu-west-1 --workflow-name wgs-germline-v1
"""

import argparse
import io
import json
import os
import zipfile
import boto3


NEXTFLOW_DIR = os.path.join(
    os.path.dirname(__file__),
    "../../01_local_pipeline/nextflow"
)

PARAMETER_TEMPLATE = {
    "reads": {
        "description": "S3 URI glob pattern for paired-end FASTQ files (e.g. s3://bucket/reads/*_R{1,2}.fastq.gz)",
        "optional": False,
    },
    "reference": {
        "description": "HealthOmics Reference Store URI or S3 URI for the reference FASTA",
        "optional": False,
    },
    "known_sites": {
        "description": "S3 URI for the known variant sites VCF (dbSNP) used in BQSR",
        "optional": False,
    },
    "outdir": {
        "description": "S3 output prefix for workflow results",
        "optional": True,
    },
    "threads": {
        "description": "Number of CPU threads per process",
        "optional": True,
    },
}


def bundle_workflow(nextflow_dir: str) -> bytes:
    """Zip the Nextflow directory into memory and return the bytes."""
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, _, files in os.walk(nextflow_dir):
            for fname in files:
                full_path = os.path.join(root, fname)
                arcname = os.path.relpath(full_path, nextflow_dir)
                zf.write(full_path, arcname)
    buf.seek(0)
    print(f"Workflow bundle: {buf.getbuffer().nbytes / 1024:.1f} KB")
    return buf.read()


def register_workflow(client, name: str, bundle: bytes) -> dict:
    response = client.create_workflow(
        name=name,
        engine="NEXTFLOW",
        definitionZip=bundle,
        parameterTemplate=PARAMETER_TEMPLATE,
        description="WGS germline variant calling: BWA-MEM2 + GATK4 HaplotypeCaller",
        tags={"project": "wgs-study"},
    )
    return response


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--region", default="us-east-1")
    p.add_argument("--workflow-name", default="wgs-germline-v1")
    args = p.parse_args()

    client = boto3.client("omics", region_name=args.region)

    print("==> Bundling workflow...")
    bundle = bundle_workflow(NEXTFLOW_DIR)

    print("==> Registering workflow with HealthOmics...")
    response = register_workflow(client, args.workflow_name, bundle)

    workflow_id = response["id"]
    workflow_arn = response["arn"]

    print(f"\nWorkflow registered!")
    print(f"  ID:   {workflow_id}")
    print(f"  ARN:  {workflow_arn}")
    print(f"  Name: {args.workflow_name}")
    print(f"\nSave the workflow ID — you'll need it in start_run.py: --workflow-id {workflow_id}")


if __name__ == "__main__":
    main()
