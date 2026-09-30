#!/usr/bin/env bash
# Creates what one environment's Terraform state lives in: a versioned,
# private bucket encrypted with its own KMS key. It has to exist before the
# first terraform init, so it cannot be part of the stack. Run once per
# account with admin credentials; running it again changes nothing.
set -euo pipefail

env=${1:?usage: scripts/bootstrap-state.sh <staging|prod>}
backend=infra/aws/stack/env/$env.s3.tfbackend
value() { awk -F'"' -v key="$1" '$1 ~ "^" key " " { print $2 }' "$backend"; }

bucket=$(value bucket)
region=$(value region)
key_id=$(value kms_key_id)
alias=alias/${key_id#*:alias/}

# The bucket name ends with the account id, so credentials for the wrong
# account fail here instead of creating prod's bucket in staging.
account=$(aws sts get-caller-identity --query Account --output text)
if [[ $bucket != *-"$account" ]]; then
  echo "bootstrap-state: $bucket belongs to another account than $account" >&2
  exit 1
fi

if ! aws kms describe-key --region "$region" --key-id "$alias" >/dev/null 2>&1; then
  key=$(aws kms create-key --region "$region" --description "terraform state" \
    --query KeyMetadata.KeyId --output text)
  aws kms enable-key-rotation --region "$region" --key-id "$key"
  aws kms create-alias --region "$region" --alias-name "$alias" --target-key-id "$key"
fi
key_arn=$(aws kms describe-key --region "$region" --key-id "$alias" --query KeyMetadata.Arn --output text)

if ! aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
  aws s3api create-bucket --bucket "$bucket" --region "$region" \
    --create-bucket-configuration LocationConstraint="$region" >/dev/null
fi

aws s3api put-public-access-block --bucket "$bucket" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
# Versions are how a broken state gets restored.
aws s3api put-bucket-versioning --bucket "$bucket" --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$bucket" --server-side-encryption-configuration "$(jq -cn --arg key "$key_arn" \
  '{Rules: [{ApplyServerSideEncryptionByDefault: {SSEAlgorithm: "aws:kms", KMSMasterKeyID: $key}, BucketKeyEnabled: true}]}')"
aws s3api put-bucket-policy --bucket "$bucket" --policy "$(jq -cn --arg bucket "$bucket" '{
  Version: "2012-10-17",
  Statement: [{
    Sid: "TLSOnly", Effect: "Deny", Principal: "*", Action: "s3:*",
    Resource: ["arn:aws:s3:::\($bucket)", "arn:aws:s3:::\($bucket)/*"],
    Condition: {Bool: {"aws:SecureTransport": "false"}}
  }]
}')"

echo "bootstrap-state: $bucket ready, encrypted with $key_arn"
