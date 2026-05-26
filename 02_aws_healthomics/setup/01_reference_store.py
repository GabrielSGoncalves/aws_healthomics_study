"""
Create an AWS HealthOmics Reference Store and import hg38 chr20 as a reference genome.

AWS HealthOmics Reference Store:
  - Stores reference genomes in an optimized compressed format (ORAv2)
  - Provides a stable URI (omics://account/referencestore/store-id/source/ref-id)
    that HealthOmics Workflows can use directly — no S3 URIs needed inside the workflow
  - Handles indexing automatically (no need to manage .fai or .dict files separately)

Steps:
  1. Create a Reference Store in your region
  2. Upload hg38 chr20 FASTA to S3
  3. Start an import job from S3 into the Reference Store
  4. Wait for import to complete and print the reference ARN

Usage:
  python 01_reference_store.py
  python 01_reference_store.py --region eu-west-1 --bucket my-genomics-bucket
"""

import argparse
import time
import boto3

def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--region", default="us-east-1")
    p.add_argument("--bucket", required=True, help="S3 bucket for staging the FASTA before import")
    p.add_argument("--fasta", default="../../01_local_pipeline/data/reference/chr20.fa",
                   help="Local path to hg38 chr20 FASTA")
    p.add_argument("--store-name", default="wgs-study-references")
    p.add_argument("--reference-name", default="hg38-chr20")
    return p.parse_args()


def create_reference_store(client, name: str) -> str:
    """Create a Reference Store and return its ID."""
    response = client.create_reference_store(name=name)
    store_id = response["id"]
    print(f"Created Reference Store: {store_id}")
    return store_id


def upload_fasta_to_s3(s3_client, local_path: str, bucket: str, key: str) -> str:
    """Upload a local FASTA to S3 and return the s3:// URI."""
    print(f"Uploading {local_path} -> s3://{bucket}/{key}")
    s3_client.upload_file(local_path, bucket, key)
    return f"s3://{bucket}/{key}"


def import_reference(client, store_id: str, reference_name: str,
                      s3_uri: str, role_arn: str) -> str:
    """Start a reference import job and poll until complete."""
    response = client.start_reference_import_job(
        referenceStoreId=store_id,
        roleArn=role_arn,
        sources=[{
            "sourceFile": s3_uri,
            "name": reference_name,
            "description": "hg38 chromosome 20 for WGS germline pipeline study",
            "tags": {"project": "wgs-study", "genome": "hg38", "contig": "chr20"},
        }],
    )
    job_id = response["id"]
    print(f"Import job started: {job_id}")

    while True:
        status_resp = client.get_reference_import_job(
            referenceStoreId=store_id, id=job_id
        )
        status = status_resp["status"]
        print(f"  Status: {status}")
        if status == "COMPLETED":
            return status_resp["sources"][0]["referenceId"]
        if status in ("FAILED", "CANCELLED"):
            raise RuntimeError(f"Import job {job_id} ended with status: {status}")
        time.sleep(15)


def main():
    args = parse_args()

    session = boto3.Session(region_name=args.region)
    omics = session.client("omics")
    s3 = session.client("s3")
    iam = session.client("iam")

    role_arn = iam.get_role(RoleName="HealthOmicsWorkflowRole")["Role"]["Arn"]

    store_id = create_reference_store(omics, args.store_name)

    s3_key = f"healthomics-imports/references/{args.reference_name}.fa"
    s3_uri = upload_fasta_to_s3(s3, args.fasta, args.bucket, s3_key)

    ref_id = import_reference(omics, store_id, args.reference_name, s3_uri, role_arn)

    print(f"\nReference import complete!")
    print(f"  Store ID:     {store_id}")
    print(f"  Reference ID: {ref_id}")
    print(f"  Workflow URI: omics://{store_id}/reference/{ref_id}")
    print(f"\nSave these values — you'll need them in start_run.py")


if __name__ == "__main__":
    main()
