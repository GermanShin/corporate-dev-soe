#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Build a multi-architecture SOE image (Apple Silicon + Intel) and push it to
# ECR. Used by CodeBuild (buildspec.yml) and can be run by the platform team
# from a Mac for testing.
#
#   ./scripts/publish.sh 1.0.0            build + push 1.0.0
#   ./scripts/publish.sh 1.0.0 --promote  also move the 'stable' tag to 1.0.0
#
# Requires: AWS_ACCOUNT_ID, AWS_REGION (or AWS_DEFAULT_REGION) and docker buildx.
# -----------------------------------------------------------------------------
set -euo pipefail

VERSION="${1:?usage: publish.sh <version> [--promote]}"
PROMOTE="${2:-}"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:?set AWS_REGION}}"
ACCOUNT="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
REPO="${SOE_REPOSITORY:-corporate-dev-soe}"
REGISTRY="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"
CLAUDE_CODE_VERSION="${CLAUDE_CODE_VERSION:-stable}"
PLATFORMS="${PLATFORMS:-linux/arm64,linux/amd64}"

cd "$(dirname "$0")/.."

echo "==> Logging in to ${REGISTRY}"
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

docker buildx inspect soe-builder >/dev/null 2>&1 \
  || docker buildx create --name soe-builder --driver docker-container >/dev/null
docker buildx use soe-builder

tags=(-t "${REGISTRY}/${REPO}:${VERSION}")
[ "$PROMOTE" = "--promote" ] && tags+=(-t "${REGISTRY}/${REPO}:stable")

echo "==> Building ${REPO}:${VERSION} for ${PLATFORMS}"
docker buildx build \
  --platform "$PLATFORMS" \
  --build-arg "SOE_VERSION=${VERSION}" \
  --build-arg "CLAUDE_CODE_VERSION=${CLAUDE_CODE_VERSION}" \
  --provenance=false \
  "${tags[@]}" \
  --push .

echo "==> Published ${REGISTRY}/${REPO}:${VERSION}"
[ "$PROMOTE" = "--promote" ] && echo "==> 'stable' now points to ${VERSION}"
