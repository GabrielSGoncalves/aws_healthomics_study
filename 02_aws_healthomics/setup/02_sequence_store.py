"""
Create an AWS HealthOmics Sequence Store and import paired-end FASTQ files as a ReadSet.

AWS HealthOmics Sequence Store:
  - Stores raw sequencing data (FASTQ, BAM, CRAM) in a compressed, indexed format
  - Each import becomes a "ReadSet" — a versioned, immutable record of the data
  - ReadSets have a stable URI for use in workflow inputs:
      omics://account/sequencestore/store-id/readset/readset-id
  - Supports parallel multi-file imports and automatic quality validation

Metadata on import:
  - sampleId, subjectId: tie the ReadSet to a sample in your data model
  - referenceArn: links the ReadSet to the reference it was aligned to (optional for FASTQ)

Usage:
  python 02_sequence_store.py --bucket my-bucket --store-name wgs-study-reads \\
      --r1 data/reads/NA12878_chr20_R1.fastq.gz \\
      --r2 data/reads/NA12878_chr20_R2.fastq.gz \\
      --sample-id NA12878
"""

import argparse
import time
import boto3


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--region", default="us-east-1")
    p.add_argument("--bucket", required=True)
    p.add_argument("--store-name", default="wgs-study-reads")
    p.add_argument("--r1", default="../../01_local_pipeline/data/reads/NA12878_chr20_R1.fastq.gz")
    p.add_argument("--r2", default="../../01_local_pipeline/data/reads/NA12878_chr20_R2.fastq.gz")
    p.add_argument("--sample-id", default="NA12878")
    return p.parse_args()


def create_sequence_store(client, name: str) -> str:
    response = client.create_sequence_store(
        name=name,
        description="WGS germline study sequence data",
        tags={"project": "wgs-study"},
    )
    store_id = response["id"]
    print(f"Created Sequence Store: {store_id}")
    return store_id


def upload_fastqs(s3_client, r1: str, r2: str, bucket: str, sample_id: str) -> tuple[str, str]:
    for local, key_suffix in [(r1, "R1"), (r2, "R2")]:
        s3_key = f"healthomics-imports/reads/{sample_id}_{key_suffix}.fastq.gz"
        print(f"Uploading {local} -> s3://{bucket}/{s3_key}")
        s3_client.upload_file(local, bucket, s3_key)
    return (
        f"s3://{bucket}/healthomics-imports/reads/{sample_id}_R1.fastq.gz",
        f"s3://{bucket}/healthomics-imports/reads/{sample_id}_R2.fastq.gz",
    )


def import_read_set(client, store_id: str, sample_id: str,
                    r1_uri: str, r2_uri: str, role_arn: str) -> str:
    response = client.start_read_set_import_job(
        sequenceStoreId=store_id,
        roleArn=role_arn,
        sources=[{
            "sourceFiles": {"source1": r1_uri, "source2": r2_uri},
            "sourceFileType": "FASTQ",
            "subjectId": sample_id,
            "sampleId": sample_id,
            "name": f"{sample_id}-chr20",
            "description": f"NA12878 WGS paired-end reads, chr20 subset",
            "tags": {"sample": sample_id, "project": "wgs-study"},
        }],
    )
    job_id = response["id"]
    print(f"Import job started: {job_id}")

    while True:
        status_resp = client.get_read_set_import_job(
            sequenceStoreId=store_id, id=job_id
        )
        status = status_resp["status"]
        print(f"  Status: {status}")
        if status == "COMPLETED":
            return status_resp["sources"][0]["readSetId"]
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

    store_id = create_sequence_store(omics, args.store_name)
    r1_uri, r2_uri = upload_fastqs(s3, args.r1, args.r2, args.bucket, args.sample_id)
    readset_id = import_read_set(omics, store_id, args.sample_id, r1_uri, r2_uri, role_arn)

    print(f"\nReadSet import complete!")
    print(f"  Sequence Store ID: {store_id}")
    print(f"  ReadSet ID:        {readset_id}")
    print(f"\nSave these values — you'll need them in start_run.py")


if __name__ == "__main__":
    main()
