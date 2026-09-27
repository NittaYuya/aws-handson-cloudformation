#!/usr/bin/env bash
# 使い方: scripts/delete.sh <1|2|3>
# スタックを削除し、完了まで待ちます。手で足したリソースがあると失敗するので、先に消してください。
set -euo pipefail

STAGE="${1:?stage 番号 (1/2/3) を指定してください}"
STACK="kikagaku-stage${STAGE}"
REGION="ap-northeast-1"

echo "== $STACK を削除します（NAT がある場合は 3〜5 分かかります）"
aws cloudformation delete-stack --region "$REGION" --stack-name "$STACK"
aws cloudformation wait stack-delete-complete --region "$REGION" --stack-name "$STACK"
echo "== 削除完了。翌日以降に請求ダッシュボードも確認してください"
