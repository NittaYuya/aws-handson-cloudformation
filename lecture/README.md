# レクチャー資料（手を動かして作る版）

CloudFormation を使わず、**自分の手で 1 つずつ AWS リソースを作る**ためのハンズオン資料です。
Notion の手順書と e-learning「CLI によるインフラ構築」の内容を、AWS を初めて触る人が **この 3 ファイルだけで最後まで進められる**ように書き直したものです。

| ファイル | 回 | 作るもの | ゴール |
|---|---|---|---|
| [day1.md](day1.md) | 第2回（Notion Day1） | VPC → サブネット → IGW → ルートテーブル → SG → EC2、Apache | ブラウザで **It works!** を出す |
| [day2.md](day2.md) | 第3回（Notion Day2） | プライベートサブネット → DB 用 EC2 → 踏み台 → NAT ゲートウェイ | 外から見えないサーバーが、**外に出られる** |
| [day3.md](day3.md) | 第4回（Notion Day3） | MariaDB → WordPress → sample.php | 自分の **ブログが動く** |

3 日分をつなげると、次の構成になります。

```mermaid
flowchart LR
    U["あなたの PC<br/>（ブラウザ / ターミナル）"]
    subgraph VPC["VPC 10.1.0.0/16 (kikagaku-cli-vpc)"]
        direction LR
        subgraph PUB["パブリックサブネット 10.1.1.0/24 (1a)"]
            WEB["Web サーバー<br/>Apache + PHP + WordPress<br/>= 踏み台"]
            NAT["NAT ゲートウェイ<br/>+ Elastic IP"]
        end
        subgraph PRV["プライベートサブネット 10.1.2.0/24 (1c)"]
            DB["DB サーバー<br/>MariaDB"]
        end
    end
    IGW["インターネット<br/>ゲートウェイ"]
    U -- "http:80 / ssh:22" --> IGW --> WEB
    WEB -- "ssh:22 / mysql:3306" --> DB
    DB -- "dnf などの外向き通信" --> NAT --> IGW
```

## 読み方

- 各ファイルは「今日のゴール → 準備 → 手順（コマンドと、それが何をしているか） → 確認 → 詰まったとき → 演習 → 片付けと次回への注意」の順です。
- コマンドの `（ ）` の中は自分の値に置き換えます。ID の貼り間違いを減らすため、CloudShell の**変数**に入れて使う書き方にしています。
- 各手順の「何をしているか」を読んでから打ってください。写すだけでも動きますが、後で「なぜ繋がらないか」を自分で切り分けられるようになるのはここを読んだ人です。

## 前の回を欠席した人

前の回の完成形を CloudFormation で一気に作れます（[../README.md](../README.md)）。`stage1-day1.yaml` を作れば day2.md から、`stage2-day2.yaml` を作れば day3.md から始められます。

## 全部消したいとき

[../docs/cleanup-manual.md](../docs/cleanup-manual.md) の CloudShell 1 行で、手で作ったものも含めて全部消えます。
