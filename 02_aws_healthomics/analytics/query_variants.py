"""
Query variants from an AWS HealthOmics Variant Store using the HealthOmics API
or Athena (for complex SQL queries).

HealthOmics Variant Store exposes two query mechanisms:
  1. HealthOmics GetVariant API — point lookups by position (fast, no SQL)
  2. Athena — full SQL over the Parquet-backed store; supports aggregations,
     filters, JOINs with annotation databases, etc.

This script demonstrates both approaches:
  - Direct API: look up variants in a genomic region
  - Athena: count PASS variants by type (SNP vs INDEL), compute Ti/Tv ratio

Prerequisites:
  - Variant Store must be in ACTIVE status with imported data
  - For Athena queries: the store must be linked to Athena via Lake Formation
    (this is set up automatically when you create a Variant Store)

Usage:
  python query_variants.py --store-name wgs-study-variants --region chr20:1000000-2000000
  python query_variants.py --store-name wgs-study-variants --athena-only
"""

import argparse
import time

import boto3


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--region", default="us-east-1")
    p.add_argument("--store-name", required=True)
    p.add_argument("--genomic-region", default="chr20:1000000-5000000",
                   help="Region in chr:start-end format")
    p.add_argument("--athena-output-uri", default=None,
                   help="S3 URI for Athena query results (e.g. s3://bucket/athena-results/)")
    p.add_argument("--athena-only", action="store_true")
    return p.parse_args()


def query_region_api(omics_client, store_name: str, region_str: str) -> None:
    """Use the HealthOmics filter API to retrieve variants in a genomic region."""
    chrom, coords = region_str.split(":")
    start, end = [int(x) for x in coords.split("-")]

    print(f"\n--- HealthOmics API: variants in {region_str} ---")
    paginator = omics_client.get_paginator("list_variant_stores")

    # Find the store ARN
    stores = omics_client.list_variant_stores(filter={"name": store_name})
    if not stores["variantStores"]:
        print(f"No variant store found with name: {store_name}")
        return
    store_id = stores["variantStores"][0]["id"]

    response = omics_client.get_variants(
        storeId=store_id,
        filter={
            "referenceLocations": [{
                "sequenceName": chrom,
                "position": {"start": start, "end": end},
            }]
        },
    )
    variants = response.get("items", [])
    print(f"Found {len(variants)} variants in {region_str}")
    for v in variants[:10]:
        print(f"  {v.get('referenceSequenceName')}:{v.get('position')} "
              f"{v.get('referenceAllele')}>{','.join(v.get('alternateAlleles', []))}")
    if len(variants) > 10:
        print(f"  ... and {len(variants) - 10} more")


def run_athena_query(athena_client, store_name: str, output_uri: str) -> None:
    """Run summary SQL queries via Athena against the Variant Store."""
    database = store_name.replace("-", "_")

    queries = {
        "Variant counts by type": f"""
            SELECT
                CASE
                    WHEN LENGTH(ref) = 1 AND LENGTH(alt) = 1 THEN 'SNP'
                    ELSE 'INDEL'
                END AS variant_type,
                COUNT(*) AS count
            FROM "{database}"."variants"
            WHERE filter = 'PASS'
            GROUP BY 1
            ORDER BY count DESC
        """,
        "Transition/Transversion ratio": f"""
            WITH snps AS (
                SELECT ref, alt
                FROM "{database}"."variants"
                WHERE filter = 'PASS'
                  AND LENGTH(ref) = 1 AND LENGTH(alt) = 1
            ),
            classified AS (
                SELECT
                    CASE
                        WHEN (ref IN ('A','G') AND alt IN ('A','G'))
                          OR (ref IN ('C','T') AND alt IN ('C','T'))
                        THEN 'Transition'
                        ELSE 'Transversion'
                    END AS type
                FROM snps
            )
            SELECT type, COUNT(*) AS count,
                   ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
            FROM classified
            GROUP BY type
        """,
    }

    for label, sql in queries.items():
        print(f"\n--- Athena: {label} ---")
        response = athena_client.start_query_execution(
            QueryString=sql,
            ResultConfiguration={"OutputLocation": output_uri},
        )
        execution_id = response["QueryExecutionId"]

        while True:
            status = athena_client.get_query_execution(
                QueryExecutionId=execution_id
            )["QueryExecution"]["Status"]["State"]
            if status in ("SUCCEEDED", "FAILED", "CANCELLED"):
                break
            time.sleep(2)

        if status != "SUCCEEDED":
            print(f"Query failed: {status}")
            continue

        results = athena_client.get_query_results(QueryExecutionId=execution_id)
        rows = results["ResultSet"]["Rows"]
        header = [c["VarCharValue"] for c in rows[0]["Data"]]
        print("\t".join(header))
        print("-" * 40)
        for row in rows[1:]:
            print("\t".join(c.get("VarCharValue", "") for c in row["Data"]))


def main():
    args = parse_args()

    session = boto3.Session(region_name=args.region)
    omics = session.client("omics")

    if not args.athena_only:
        query_region_api(omics, args.store_name, args.genomic_region)

    if args.athena_output_uri:
        athena = session.client("athena")
        run_athena_query(athena, args.store_name, args.athena_output_uri)
    else:
        print("\nTip: pass --athena-output-uri s3://bucket/athena/ to run SQL queries.")


if __name__ == "__main__":
    main()
