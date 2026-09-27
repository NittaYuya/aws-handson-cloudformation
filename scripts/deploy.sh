#!/usr/bin/env bash
# 使い方: scripts/deploy.sh <1|2|3> <自宅IP> [キーペア名] [EnableNat(true|false, stage2のみ)]
# 例:     scripts/deploy.sh 1 113.147.224.53
#         scripts/deploy.sh 2 113.147.224.53 kikagaku-cli-key false
set -euo pipefail

STAGE="${1:?stage 番号 (1/2/3) を指定してください}"
MYIP="${2:?自宅のグローバル IP を指定してください (checkip.amazonaws.com)}"
KEYNAME="${3:-kikagaku-cli-key}"
ENABLE_NAT="${4:-true}"
REGION="ap-northeast-1"

case "$STAGE" in
  1) TEMPLATE="stage1-day1.yaml" ;;
  2) TEMPLATE="stage2-day2.yaml" ;;
  3) TEMPLATE="stage3-day3.yaml" ;;
  *) echo "stage は 1, 2, 3 のどれか"; exit 1 ;;
esac
STACK="kikagaku-stage${STAGE}"
cd "$(dirname "$0")/.."

PARAMS=(MyIp="$MYIP" KeyName="$KEYNAME")
if [ "$STAGE" = "2" ]; then PARAMS+=(EnableNat="$ENABLE_NAT"); fi

echo "== $TEMPLATE を $STACK として作成します（リージョン: $REGION）"
aws cloudformation deploy \
  --region "$REGION" \
  --stack-name "$STACK" \
  --template-file "$TEMPLATE" \
  --parameter-overrides "${PARAMS[@]}"

echo
echo "== 出力（URL・コマンド）"
aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK" \
  --query "Stacks[0].Outputs[].[OutputKey,OutputValue]" --output table
