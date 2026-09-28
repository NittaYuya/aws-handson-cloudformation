#!/usr/bin/env bash
# ==============================================================================
# cleanup.sh — ハンズオンで作った AWS リソースを一括削除する（CloudShell 用）
#
# Day1 / Day2 / Day3 のどの時点でも、手動で作ったものも CloudFormation で作ったものも、
# 名前に「kikagaku」を含む VPC の中身をまとめて消します。
#
# CloudShell での実行（コンソール右上の >_ アイコン）:
#   bash <(curl -fsSL https://raw.githubusercontent.com/NittaYuya/aws-handson-cloudformation/main/scripts/cleanup.sh)
#
# 確認なしで実行:   YES=1 bash <(curl -fsSL ...)
# 対象の名前を変更: KEYWORD=kikagaku bash <(curl -fsSL ...)
#
# 消す順番（依存の葉 → 根）。各段階で「消え終わる」のを待ってから次へ進みます。
#   1. EC2 インスタンスを終了（終了完了まで待つ）
#   2. NAT ゲートウェイを削除（「削除済み」になるまで待つ）
#   3. Elastic IP を解放（NAT に付いていたもの ＋ 名前に kikagaku を含むもの）
#   4. VPC エンドポイント・残ったネットワークインターフェースを削除
#   5. IGW → セキュリティグループ → サブネット → ルートテーブル → VPC
#   6. CloudFormation スタック（kikagaku-*）の記録を削除
#
# 触らないもの: デフォルト VPC、名前に kikagaku を含まない VPC、キーペア
# 何度実行しても安全です（途中で失敗したら、そのままもう一度実行してください）
# ==============================================================================
set -uo pipefail

export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-ap-northeast-1}"
export AWS_PAGER=""
KEYWORD="${KEYWORD:-kikagaku}"
YES="${YES:-0}"

say()  { echo; echo "== $*"; }
note() { echo "   $*"; }

# ------------------------------------------------------------------------------
# 対象を集める
# ------------------------------------------------------------------------------
VPC_IDS=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=*${KEYWORD}*" "Name=is-default,Values=false" \
  --query 'Vpcs[].VpcId' --output text)

STACKS=$(aws cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE ROLLBACK_COMPLETE DELETE_FAILED CREATE_FAILED UPDATE_ROLLBACK_COMPLETE \
  --query "StackSummaries[?contains(StackName,'${KEYWORD}')].StackName" --output text)

TAGGED_EIPS=$(aws ec2 describe-addresses \
  --filters "Name=tag:Name,Values=*${KEYWORD}*" \
  --query 'Addresses[].AllocationId' --output text)

INSTANCES=""; NATS=""; NAT_ALLOCS=""; ENDPOINTS=""
for vpc in $VPC_IDS; do
  INSTANCES="$INSTANCES $(aws ec2 describe-instances \
    --filters "Name=vpc-id,Values=$vpc" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].InstanceId' --output text)"
  NATS="$NATS $(aws ec2 describe-nat-gateways \
    --filter "Name=vpc-id,Values=$vpc" "Name=state,Values=pending,available,failed" \
    --query 'NatGateways[].NatGatewayId' --output text)"
  NAT_ALLOCS="$NAT_ALLOCS $(aws ec2 describe-nat-gateways \
    --filter "Name=vpc-id,Values=$vpc" "Name=state,Values=pending,available,failed" \
    --query 'NatGateways[].NatGatewayAddresses[].AllocationId' --output text)"
  ENDPOINTS="$ENDPOINTS $(aws ec2 describe-vpc-endpoints \
    --filters "Name=vpc-id,Values=$vpc" --query 'VpcEndpoints[].VpcEndpointId' --output text)"
done
# 名前に kikagaku を含むが、上の VPC の外にあるインスタンス / NAT も拾う（VPC を作り直した等）
INSTANCES="$INSTANCES $(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*${KEYWORD}*" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].InstanceId' --output text)"
NATS="$NATS $(aws ec2 describe-nat-gateways \
  --filter "Name=tag:Name,Values=*${KEYWORD}*" "Name=state,Values=pending,available,failed" \
  --query 'NatGateways[].NatGatewayId' --output text)"

# 重複と None を除去
uniq_words() { tr ' ' '\n' | grep -v '^None$' | grep -v '^$' | sort -u | tr '\n' ' '; }
INSTANCES=$(echo "$INSTANCES" | uniq_words)
NATS=$(echo "$NATS" | uniq_words)
ALLOCS=$(echo "$NAT_ALLOCS $TAGGED_EIPS" | uniq_words)
ENDPOINTS=$(echo "$ENDPOINTS" | uniq_words)
VPC_IDS=$(echo "$VPC_IDS" | uniq_words)
STACKS=$(echo "$STACKS" | uniq_words)

echo "------------------------------------------------------------"
echo " 削除対象  リージョン: $AWS_DEFAULT_REGION  キーワード: *${KEYWORD}*"
echo "------------------------------------------------------------"
echo " VPC                : ${VPC_IDS:-なし}"
echo " EC2 インスタンス   : ${INSTANCES:-なし}"
echo " NAT ゲートウェイ   : ${NATS:-なし}"
echo " Elastic IP         : ${ALLOCS:-なし}"
echo " VPC エンドポイント : ${ENDPOINTS:-なし}"
echo " CloudFormation     : ${STACKS:-なし}"
echo " （VPC の中のサブネット・IGW・SG・ルートテーブルも一緒に消えます）"
echo "------------------------------------------------------------"
if [ -z "$VPC_IDS$INSTANCES$NATS$ALLOCS$STACKS" ]; then
  echo "消すものはありません。"
  exit 0
fi
if [ "$YES" != "1" ]; then
  read -r -p "上のリソースをすべて削除します。よければ yes と入力: " ans
  [ "$ans" = "yes" ] || { echo "中止しました"; exit 0; }
fi

# ------------------------------------------------------------------------------
# 1. EC2 インスタンスの終了（完了まで待つ）
# ------------------------------------------------------------------------------
if [ -n "$INSTANCES" ]; then
  say "1/6 EC2 インスタンスを終了: $INSTANCES"
  aws ec2 terminate-instances --instance-ids $INSTANCES >/dev/null
  note "終了完了を待っています（1〜2 分）"
  aws ec2 wait instance-terminated --instance-ids $INSTANCES
  note "終了しました"
else
  say "1/6 EC2 インスタンス: なし"
fi

# ------------------------------------------------------------------------------
# 2. NAT ゲートウェイの削除（「削除済み」になるまで待つ）
# ------------------------------------------------------------------------------
if [ -n "$NATS" ]; then
  say "2/6 NAT ゲートウェイを削除: $NATS"
  for n in $NATS; do aws ec2 delete-nat-gateway --nat-gateway-id "$n" >/dev/null 2>&1 || true; done
  note "削除完了を待っています（2〜5 分）"
  for i in $(seq 1 60); do
    remaining=$(aws ec2 describe-nat-gateways --nat-gateway-ids $NATS \
      --query "NatGateways[?state!='deleted'].NatGatewayId" --output text 2>/dev/null)
    [ -z "$remaining" ] && break
    sleep 10
  done
  note "削除されました"
else
  say "2/6 NAT ゲートウェイ: なし"
fi

# ------------------------------------------------------------------------------
# 3. Elastic IP の解放（NAT の解放待ちで失敗したら少し待って再試行）
# ------------------------------------------------------------------------------
if [ -n "$ALLOCS" ]; then
  say "3/6 Elastic IP を解放: $ALLOCS"
  for a in $ALLOCS; do
    for i in 1 2 3 4 5 6; do
      if aws ec2 release-address --allocation-id "$a" >/dev/null 2>&1; then
        note "解放: $a"; break
      fi
      if ! aws ec2 describe-addresses --allocation-ids "$a" >/dev/null 2>&1; then
        note "すでに解放済み: $a"; break
      fi
      [ "$i" = 6 ] && note "解放できませんでした（まだ使用中）: $a  → 数分後にもう一度このスクリプトを実行してください"
      sleep 15
    done
  done
else
  say "3/6 Elastic IP: なし"
fi

# ------------------------------------------------------------------------------
# 4. VPC エンドポイントと、残ったネットワークインターフェース
# ------------------------------------------------------------------------------
say "4/6 VPC エンドポイント・ネットワークインターフェースの後片付け"
if [ -n "$ENDPOINTS" ]; then
  aws ec2 delete-vpc-endpoints --vpc-endpoint-ids $ENDPOINTS >/dev/null 2>&1 || true
  note "エンドポイント削除: $ENDPOINTS"
fi
for vpc in $VPC_IDS; do
  for i in $(seq 1 30); do
    ENIS=$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$vpc" \
      --query 'NetworkInterfaces[].NetworkInterfaceId' --output text)
    [ -z "$ENIS" ] && break
    for e in $ENIS; do aws ec2 delete-network-interface --network-interface-id "$e" >/dev/null 2>&1 || true; done
    sleep 10
  done
done
note "完了"

# ------------------------------------------------------------------------------
# 5. IGW → SG → サブネット → ルートテーブル → VPC
# ------------------------------------------------------------------------------
for vpc in $VPC_IDS; do
  say "5/6 VPC $vpc の中身を削除"

  for igw in $(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc" \
      --query 'InternetGateways[].InternetGatewayId' --output text); do
    aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$vpc" >/dev/null 2>&1 || true
    aws ec2 delete-internet-gateway --internet-gateway-id "$igw" >/dev/null 2>&1 && note "IGW 削除: $igw" || note "IGW を削除できませんでした: $igw"
  done

  # SG は相互参照があると消せないので、先にインバウンドルールを全部外す
  SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc" \
    --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)
  for g in $SGS; do
    perms=$(aws ec2 describe-security-groups --group-ids "$g" --query 'SecurityGroups[0].IpPermissions' --output json)
    [ "$perms" != "[]" ] && aws ec2 revoke-security-group-ingress --group-id "$g" --ip-permissions "$perms" >/dev/null 2>&1 || true
  done
  for g in $SGS; do
    aws ec2 delete-security-group --group-id "$g" >/dev/null 2>&1 && note "SG 削除: $g" || note "SG を削除できませんでした: $g"
  done

  for sn in $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc" --query 'Subnets[].SubnetId' --output text); do
    aws ec2 delete-subnet --subnet-id "$sn" >/dev/null 2>&1 && note "サブネット削除: $sn" || note "サブネットを削除できませんでした: $sn"
  done

  # メイン以外のルートテーブル（関連付けが 0 件のものも含む）
  for rt in $(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc" \
      --query 'RouteTables[?length(Associations[?Main==`true`])==`0`].RouteTableId' --output text); do
    for assoc in $(aws ec2 describe-route-tables --route-table-ids "$rt" \
        --query 'RouteTables[0].Associations[].RouteTableAssociationId' --output text); do
      aws ec2 disassociate-route-table --association-id "$assoc" >/dev/null 2>&1 || true
    done
    aws ec2 delete-route-table --route-table-id "$rt" >/dev/null 2>&1 && note "ルートテーブル削除: $rt" || note "ルートテーブルを削除できませんでした: $rt"
  done

  # VPC 本体（内部の解放待ちで失敗することがあるので 3 回まで再試行）
  for i in 1 2 3; do
    if aws ec2 delete-vpc --vpc-id "$vpc" >/dev/null 2>&1; then
      note "VPC 削除: $vpc"; break
    fi
    if [ "$i" = 3 ]; then
      note "VPC を削除できませんでした: $vpc"
      note "→ 2〜3 分待ってもう一度このスクリプトを実行してください。それでも残る場合はコンソールの VPC → 「VPC の削除」で残っている依存リソースを確認してください"
    else
      sleep 20
    fi
  done
done

# ------------------------------------------------------------------------------
# 6. CloudFormation スタックの記録を削除（中身はもう無いので短時間で終わる）
# ------------------------------------------------------------------------------
if [ -n "$STACKS" ]; then
  say "6/6 CloudFormation スタックを削除: $STACKS"
  for s in $STACKS; do
    aws cloudformation delete-stack --stack-name "$s"
    aws cloudformation wait stack-delete-complete --stack-name "$s" >/dev/null 2>&1 \
      && note "削除: $s" \
      || note "削除が完了しませんでした: $s → CloudFormation コンソールの「イベント」タブで理由を確認し、もう一度「削除」してください"
  done
else
  say "6/6 CloudFormation スタック: なし"
fi

# ------------------------------------------------------------------------------
# 残りものの確認
# ------------------------------------------------------------------------------
say "確認"
LEFT_EIPS=$(aws ec2 describe-addresses --query 'Addresses[?AssociationId==null].[AllocationId,PublicIp]' --output text)
if [ -n "$LEFT_EIPS" ]; then
  note "未使用の Elastic IP が残っています（名前が付いていないため自動では消しませんでした。不要なら解放してください。使っていなくても課金されます）:"
  echo "$LEFT_EIPS" | sed 's/^/     /'
fi
LEFT_VPCS=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=*${KEYWORD}*" --query 'Vpcs[].VpcId' --output text)
[ -n "$LEFT_VPCS" ] && note "まだ残っている VPC: $LEFT_VPCS（数分後にもう一度実行してください）"
note "キーペア（EC2 → キーペア）は課金されないので残して構いません。不要なら手で削除してください"
echo
say "完了。翌日以降に請求ダッシュボード（右上のアカウント名 → 請求とコスト管理）で EC2 / NAT / EIP の行が増えていないことを確認してください"
