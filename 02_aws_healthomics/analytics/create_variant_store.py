"""
Create an AWS HealthOmics Variant Store and import a VCF file.

AWS HealthOmics Variant Store:
  - Stores variants in an Apache Parquet-backed columnar format optimized for queries
  - Supports import from VCF, BCF, and TSV formats
  - Integrates with Athena for SQL queries and Lake Formation for access control
  - Annotates variants with reference genome coordinates automatically
  - Supports population-scale datasets (millions of samples, billions of variants)

The Variant Store is schema-on-import: INFO and FORMAT fields from your VCF become
queryable columns. You can query by position, gene, sample, allele frequency, etc.

Usage:
  python create_variant_store.py \\
    --reference-arn arn:aws:omics:us-east-1:123456789:referenceStore/store-id/reference/ref-id \\
    --vcf s3://my-bucket/results/NA12878.final.vcf.gz \\
    --sample-id NA12878
"""

import argparse
import time

import boto3


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--region", default="us-east-1")
    p.add_argument("--store-name", default="wgs-study-variants")
    p.add_argument("--reference-arn", required=True,
                   help="ARN of the HealthOmics reference genome to link the store to")
    p.add_argument("--vcf", required=True, help="S3 URI of the VCF to import")
    p.add_argument("--sample-id", default="NA12878")
    return p.parse_args()


def create_variant_store(client, name: str, reference_arn: str) -> str:
    response = client.create_variant_store(
        name=name,
        reference={"referenceArn": reference_arn},
        description="WGS germline study variant data",
        tags={"project": "wgs-study"},
    )
    store_id = response["id"]
    print(f"Created Variant Store: {store_id}")
    return store_id


def wait_for_store_active(client, store_name: str) -> None:
    print("Waiting for Variant Store to become ACTIVE...")
    while True:
        response = client.get_variant_store(name=store_name)
        status = response["status"]
        print(f"  Status: {status}")
        if status == "ACTIVE":
            return
        if status in ("FAILED", "DELETING"):
            raise RuntimeError(f"Variant Store entered unexpected status: {status}")
        time.sleep(10)


def import_vcf(client, store_name: str, vcf_uri: str, sample_id: str, role_arn: str) -> str:
    response = client.start_variant_import_job(
        destinationName=store_name,
        roleArn=role_arn,
        items=[{"source": vcf_uri}],
        runLeftNormalization=True,
    )
    job_id = response["jobId"]
    print(f"Import job started: {job_id}")

    while True:
        status_resp = client.get_variant_import_job(jobId=job_id)
        status = status_resp["status"]
        print(f"  Status: {status}")
        if status == "COMPLETED":
            return job_id
        if status in ("FAILED", "CANCELLED"):
            raise RuntimeError(f"Import job failed: {status_resp.get('statusMessage')}")
        time.sleep(20)


def main():
    args = parse_args()

    session = boto3.Session(region_name=args.region)
    omics = session.client("omics")
    iam = session.client("iam")

    role_arn = iam.get_role(RoleName="HealthOmicsWorkflowRole")["Role"]["Arn"]

    store_id = create_variant_store(omics, args.store_name, args.reference_arn)
    wait_for_store_active(omics, args.store_name)
    job_id = import_vcf(omics, args.store_name, args.vcf, args.sample_id, role_arn)

    print(f"\nVariant import complete!")
    print(f"  Store name: {args.store_name}")
    print(f"  Job ID: {job_id}")
    print(f"\nQuery variants with: python query_variants.py --store-name {args.store_name}")


if __name__ == "__main__":
    main()
