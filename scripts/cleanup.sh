#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# cleanup.sh — kikagaku-cli-vpc の中身を「手動で作ったか、スタックで作ったか」に関係なく全部消す
#
# 使い方:
#   scripts/cleanup.sh            # 消す対象を一覧表示し、yes と入力したら実行
#   scripts/cleanup.sh --yes      # 確認なしで実行
#   scripts/cleanup.sh vpc-0123…  # VPC ID を直接指定（同名 VPC が複数あるとき）
#
# 消す順番（依存の葉 → 根）:
#   1. EC2 インスタンスを終了
#   2. NAT ゲートウェイを削除（消えるまで待つ）
#   3. Elastic IP を解放（NAT に付いていたもの＋ kikagaku の名前が付いた未使用のもの）
#   4. 残ったネットワークインターフェース・VPC エンドポイントを削除
#   5. この VPC を参照している CloudFormation スタックを削除（中身は消えているので記録だけが消える）
#   6. それでも VPC が残っていれば SG・サブネット・IGW・ルートテーブル・VPC を削除
#
# 触らないもの: デフォルト VPC、キーペア、他の名前の VPC
# ------------------------------------------------------------------------------
set -uo pipefail

REGION="ap-northeast-1"
TARGET="kikagaku-cli-vpc"
YES=0
for a in "$@"; do
  case "$a" in
    --yes) YES=1 ;;
    *) TARGET="$a" ;;
  esac
done

aws() { command aws --region "$REGION" "$@"; }
say() { echo "== $*"; }

# ---------- VPC を特定 ----------
if [[ "$TARGET" == vpc-* ]]; then
  VPC="$TARGET"
else
  VPC=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$TARGET" --query 'Vpcs[].VpcId' --output text)
fi
if [ -z "$VPC" ] || [ "$VPC" = "None" ]; then
  say "VPC「$TARGET」は見つかりませんでした（すでに削除済みかもしれません）"
  STACK_ONLY=1
else
  STACK_ONLY=0
  if [ "$(wc -w <<<"$VPC")" -gt 1 ]; then
    echo "同じ名前の VPC が複数あります: $VPC"
    echo "どれを消すか、VPC ID を引数で指定してください。例: scripts/cleanup.sh vpc-0123456789abcdef0"
    exit 1
  fi
  if [ "$(aws ec2 describe-vpcs --vpc-ids "$VPC" --query 'Vpcs[0].IsDefault' --output text)" = "True" ]; then
    echo "$VPC はデフォルト VPC です。安全のため触りません。"
    exit 1
  fi
fi

# ---------- 消す対象を集める ----------
if [ "$STACK_ONLY" = 0 ]; then
  INSTANCES=$(aws ec2 describe-instances \
    --filters "Name=vpc-id,Values=$VPC" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].InstanceId' --output text)
  NATS=$(aws ec2 describe-nat-gateways \
    --filter "Name=vpc-id,Values=$VPC" "Name=state,Values=pending,available,failed" \
    --query 'NatGateways[].NatGatewayId' --output text)
  NAT_ALLOCS=$(aws ec2 describe-nat-gateways \
    --filter "Name=vpc-id,Values=$VPC" "Name=state,Values=pending,available,failed" \
    --query 'NatGateways[].NatGatewayAddresses[].AllocationId' --output text)
  ENDPOINTS=$(aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC" --query 'VpcEndpoints[].VpcEndpointId' --output text)
  SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC" --query 'Subnets[].SubnetId' --output text)
  IGWS=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC" --query 'InternetGateways[].InternetGatewayId' --output text)
fi
# kikagaku の名前が付いた未使用 Elastic IP（NAT を手で消して EIP だけ残した場合）
ORPHAN_EIPS=$(aws ec2 describe-addresses \
  --filters "Name=tag:Name,Values=kikagaku*" \
  --query 'Addresses[?AssociationId==null].AllocationId' --output text)
# この VPC を作った CloudFormation スタック（出力 VpcId が一致するもの）
STACKS=""
for s in $(aws cloudformation list-stacks \
    --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE ROLLBACK_COMPLETE DELETE_FAILED UPDATE_ROLLBACK_COMPLETE CREATE_FAILED \
    --query "StackSummaries[?starts_with(StackName,'kikagaku-')].StackName" --output text); do
  if [ "$STACK_ONLY" = 1 ]; then
    STACKS="$STACKS $s"
  else
    v=$(aws cloudformation describe-stacks --stack-name "$s" --query "Stacks[0].Outputs[?OutputKey=='VpcId'].OutputValue" --output text 2>/dev/null || true)
    [ "$v" = "$VPC" ] && STACKS="$STACKS $s"
  fi
done

echo "------------------------------------------------------------"
echo " 削除対象（リージョン: $REGION）"
echo "------------------------------------------------------------"
echo " VPC                : ${VPC:-なし}"
echo " EC2 インスタンス   : ${INSTANCES:-なし}"
echo " NAT ゲートウェイ   : ${NATS:-なし}"
echo " Elastic IP         : ${NAT_ALLOCS:-} ${ORPHAN_EIPS:-}"
echo " VPC エンドポイント : ${ENDPOINTS:-なし}"
echo " サブネット         : ${SUBNETS:-なし}"
echo " IGW                : ${IGWS:-なし}"
echo " CloudFormation     : ${STACKS:-なし}"
echo "------------------------------------------------------------"
if [ "$YES" = 0 ]; then
  read -r -p "上のリソースをすべて削除します。よければ yes と入力: " ans
  [ "$ans" = "yes" ] || { echo "中止しました"; exit 0; }
fi

if [ "$STACK_ONLY" = 0 ]; then
  # ---------- 1. インスタンス終了 ----------
  if [ -n "$INSTANCES" ]; then
    say "1/6 EC2 インスタンスを終了: $INSTANCES"
    aws ec2 terminate-instances --instance-ids $INSTANCES >/dev/null
    aws ec2 wait instance-terminated --instance-ids $INSTANCES
  fi

  # ---------- 2. NAT 削除 ----------
  if [ -n "$NATS" ]; then
    say "2/6 NAT ゲートウェイを削除: $NATS（数分かかります）"
    for n in $NATS; do aws ec2 delete-nat-gateway --nat-gateway-id "$n" >/dev/null; done
    for i in $(seq 1 60); do
      remaining=$(aws ec2 describe-nat-gateways --nat-gateway-ids $NATS --query "NatGateways[?state!='deleted'].NatGatewayId" --output text)
      [ -z "$remaining" ] && break
      sleep 10
    done
  fi

  # ---------- 3. Elastic IP 解放 ----------
  for a in $NAT_ALLOCS $ORPHAN_EIPS; do
    say "3/6 Elastic IP を解放: $a"
    aws ec2 release-address --allocation-id "$a" 2>/dev/null || echo "   （すでに解放済み、または使用中のためスキップ: $a）"
  done

  # ---------- 4. エンドポイント・残った ENI ----------
  if [ -n "$ENDPOINTS" ]; then
    say "4/6 VPC エンドポイントを削除: $ENDPOINTS"
    aws ec2 delete-vpc-endpoints --vpc-endpoint-ids $ENDPOINTS >/dev/null
  fi
  say "4/6 ネットワークインターフェースが消えるのを待っています"
  for i in $(seq 1 30); do
    ENIS=$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC" --query 'NetworkInterfaces[].NetworkInterfaceId' --output text)
    [ -z "$ENIS" ] && break
    for e in $ENIS; do aws ec2 delete-network-interface --network-interface-id "$e" 2>/dev/null || true; done
    sleep 10
  done
fi

# ---------- 5. スタック削除 ----------
for s in $STACKS; do
  say "5/6 CloudFormation スタックを削除: $s"
  aws cloudformation delete-stack --stack-name "$s"
  aws cloudformation wait stack-delete-complete --stack-name "$s" 2>/dev/null \
    || echo "   （$s の削除が完了しませんでした。最後にもう一度試します）"
done

# ---------- 6. VPC が残っていれば中身ごと削除 ----------
if [ "$STACK_ONLY" = 0 ] && aws ec2 describe-vpcs --vpc-ids "$VPC" >/dev/null 2>&1; then
  say "6/6 残ったネットワークリソースを削除"
  # SG: 相互参照ルールを先に外してから、default 以外を削除
  SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)
  for g in $SGS; do
    perms=$(aws ec2 describe-security-groups --group-ids "$g" --query 'SecurityGroups[0].IpPermissions' --output json)
    [ "$perms" != "[]" ] && aws ec2 revoke-security-group-ingress --group-id "$g" --ip-permissions "$perms" >/dev/null 2>&1 || true
  done
  for g in $SGS; do aws ec2 delete-security-group --group-id "$g" 2>/dev/null || echo "   （SG $g はスキップ）"; done
  for sn in $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC" --query 'Subnets[].SubnetId' --output text); do
    aws ec2 delete-subnet --subnet-id "$sn" 2>/dev/null || echo "   （サブネット $sn はスキップ）"
  done
  for ig in $(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC" --query 'InternetGateways[].InternetGatewayId' --output text); do
    aws ec2 detach-internet-gateway --internet-gateway-id "$ig" --vpc-id "$VPC" 2>/dev/null || true
    aws ec2 delete-internet-gateway --internet-gateway-id "$ig" 2>/dev/null || true
  done
  for rt in $(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC" --query "RouteTables[?Associations[?Main==\`true\`]==\`[]\`].RouteTableId" --output text); do
    for assoc in $(aws ec2 describe-route-tables --route-table-ids "$rt" --query 'RouteTables[0].Associations[].RouteTableAssociationId' --output text); do
      aws ec2 disassociate-route-table --association-id "$assoc" 2>/dev/null || true
    done
    aws ec2 delete-route-table --route-table-id "$rt" 2>/dev/null || true
  done
  aws ec2 delete-vpc --vpc-id "$VPC" && say "VPC $VPC を削除しました" || echo "   VPC $VPC を削除できませんでした。コンソールの VPC → 「VPC の削除」で残っている依存リソースを確認してください"

  # スタックが DELETE_FAILED で残っていれば、依存が消えた今もう一度
  for s in $STACKS; do
    st=$(aws cloudformation describe-stacks --stack-name "$s" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo GONE)
    if [ "$st" != "GONE" ]; then
      say "スタック $s を再度削除（状態: $st）"
      aws cloudformation delete-stack --stack-name "$s"
      aws cloudformation wait stack-delete-complete --stack-name "$s" 2>/dev/null || echo "   $s はまだ残っています。コンソールのイベントタブを確認してください"
    fi
  done
fi

echo
say "完了。翌日以降に請求ダッシュボード（右上のアカウント名 → 請求とコスト管理）で EC2 / NAT / EIP の行が増えていないことを確認してください"
