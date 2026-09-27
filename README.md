# クラウドインフラ基礎講座 フォローアップ会 追いつき用 CloudFormation テンプレート

フォローアップ会（第2回〜第4回）の各回の「終了時点の環境」を、AWS CloudFormation で一度に作るためのテンプレートです。
欠席した回がある人、途中で詰まって環境が崩れた人、もう一度きれいな状態から始めたい人向けです。

| ファイル | 作られる環境 | こんな人向け |
|---|---|---|
| `stage1-day1.yaml` | **第2回（Notion Day1）終了時点**: VPC / パブリックサブネット / IGW / ルートテーブル / SG / Web サーバー（Apache 起動済み） | 第2回を欠席し、第3回から参加する人 |
| `stage2-day2.yaml` | **第3回（Notion Day2）終了時点**: 上記 ＋ プライベートサブネット / DB サーバー / NAT ゲートウェイ ＋ Elastic IP | 第3回を欠席し、第4回から参加する人 |
| `stage3-day3.yaml` | **第4回（Notion Day3）終了時点**: 上記 ＋ MariaDB（wordpress DB 作成済み） / PHP ＋ WordPress / 演習3 の sample.php | 第4回を欠席した人、完成形をもう一度見たい人 |

リソース名・IP アドレス（`kikagaku-cli-vpc`、`10.1.0.0/16`、`10.1.1.0/24`、`10.1.2.0/24` など）は Notion の手順書と同じにしてあるので、作成後にコンソールで見たときに手順書のスクリーンショットと同じ景色になります。

削除は **スタックの削除 1 回** で、そのテンプレートが作ったリソースが全部消えます。削除用のファイルは要りません。

---

## 0. 使う前に決めておくルール

1. **手動で作った環境と混ぜない。** 自分で作った `kikagaku-cli-vpc` が残っている状態でテンプレートを実行すると、名前が同じリソースが 2 組できて混乱します。先に「6. 手動で作った環境の片付け」で消してから使ってください。
2. **テンプレートで作った環境の上に、手で足すのは OK。** たとえば `stage1` で作った VPC に、第3回の手順どおり手でプライベートサブネットを足して構いません。ただし **スタックを消すときは、手で足したものを先に消してください**（残っていると VPC が消せず、削除が失敗します）。
3. **リージョンは東京（ap-northeast-1）。** 他のリージョンではテンプレートがエラーを出して止まります。
4. **NAT ゲートウェイは時間課金です**（1 時間あたり約 0.062 USD、放置すると月 6,000〜7,000 円）。`stage2` と `stage3` を作ったら、その日のうちにスタックを削除するか、`stage2` は `EnableNat=false` で作り直してください。

---

## 1. 事前準備（初回だけ・5 分）

### 1-1. キーペアを 1 つ作る

テンプレートは「既存のキーペア名」を受け取ります。まだ持っていない人は次の手順で作ってください。

1. AWS コンソール → **EC2** → 左メニュー「キーペア」→「キーペアを作成」
2. 名前: `kikagaku-cli-key`、タイプ: RSA、形式: `.pem`
3. 「作成」を押すと `kikagaku-cli-key.pem` が自動でダウンロードされます。**分かる場所に保存**してください（後で ssh に使います）
4. 権限を絞ります（Notion 3 章と同じ）

```bash
# Mac
chmod 600 kikagaku-cli-key.pem
```

```powershell
# Windows (PowerShell)
icacls "kikagaku-cli-key.pem" /inheritance:r /grant:r "$($env:USERNAME):R"
```

第2回に出席して `kikagaku-cli-key` をすでに作った人は、そのまま使えます。

### 1-2. 自宅のグローバル IP を調べる

ブラウザで https://checkip.amazonaws.com/ を開き、表示された数字（例: `113.147.224.53`）をメモします。
テンプレートはこの IP からだけ SSH（22）と HTTP（80）を許可します。ルーターの再起動やテザリングで変わるので、繋がらなくなったら再確認してください。

---

## 2. 作る（コンソールから・約 5 分）

1. このリポジトリの `stageN-dayN.yaml` をダウンロードする（ファイル名を開き、右上の「Download raw file」）
2. AWS コンソール → **CloudFormation** → 「スタックの作成」→「新しいリソースを使用（標準）」
3. 「テンプレートファイルのアップロード」でダウンロードした YAML を選び、「次へ」
4. パラメータを入れる

   | 項目 | 入れる値 |
   |---|---|
   | スタック名 | `kikagaku-stage1`（stage2 なら `kikagaku-stage2`、stage3 なら `kikagaku-stage3`） |
   | 自宅のグローバル IP アドレス | 1-2 でメモした値（`/32` は付けない） |
   | キーペア名 | `kikagaku-cli-key` |
   | NAT ゲートウェイを作る（stage2 のみ） | `true`（第3回終了時点）／`false`（宿題で NAT を消した状態） |
   | MariaDB の root パスワード（stage3 のみ） | 任意の英数字（初期値 `rootpasswd` のままでも可） |

5. 「次へ」→「次へ」→ 一番下の「送信」
6. ステータスが **CREATE_COMPLETE** になるまで待つ（stage1 は約 3 分、NAT がある stage2/3 は約 5 分）
7. 「出力」タブを開く。**ブラウザで開く URL と、ssh / scp のコマンドがそのまま書いてあります**

### CLI で作りたい人

```bash
aws cloudformation deploy \
  --stack-name kikagaku-stage1 \
  --template-file stage1-day1.yaml \
  --parameter-overrides MyIp=113.147.224.53 KeyName=kikagaku-cli-key

# 出力（URL・コマンド）を見る
aws cloudformation describe-stacks --stack-name kikagaku-stage1 \
  --query "Stacks[0].Outputs" --output table
```

`scripts/deploy.sh` に同じ内容をまとめてあります。

---

## 3. 作ったあと、各 stage で「手でやること」

テンプレートは環境を作るだけです。学習内容そのものである操作は残してあります。

### stage1（第2回終了時点）
- 出力の `WebUrl` をブラウザで開く → 「It works!」が出れば成功
- 出力の `SshCommand` で SSH → `sudo lsof -i -n -P` で 80 番の LISTEN を確認
- ペアワークをするなら、相手の IP を SG `kikagaku-cli-sg` に `/32` で追加

### stage2（第3回終了時点）
- 出力の `Step1CopyKeyToBastion` → `Step2SshToBastion` → `Step3SshToDb` の順に実行（Notion 4 章の「踏み台」）
- DB サーバーで `curl https://info.cern.ch/hypertext/WWW/TheProject.html` → NAT 経由で外に出られることを確認
- **DB サーバーには何もインストールしていません**（それは第4回の内容です）

### stage3（第4回終了時点）
- 出力の `WordPressUrl` を開く → 言語選択 → **サイト名・管理者ユーザー・パスワード**を決める画面から始まります（DB 情報は `wp-config.php` に設定済みなので、Notion 7 章の「さあ、始めましょう！」の DB 入力画面は出ません）
- 出力の `SamplePhpUrl` を開く → 「接続成功！」と記事一覧（演習3）
- DB の中を見たい人は踏み台経由で DB サーバーに入り `mysql -u root -p`（パスワードは作成時に入れた値）
- Notion 7 章の DB 入力画面を自分で体験したい人は、Web サーバーで `sudo rm /var/www/html/wp-config.php` してからブラウザを開き直してください

---

## 4. 失敗したとき（ROLLBACK_COMPLETE と出たら）

CloudFormation は途中で失敗すると **作ったものを全部巻き戻して** `ROLLBACK_COMPLETE` で止まります。そのスタックは削除しないと同じ名前で作り直せません。

1. スタックの「**イベント**」タブを開き、赤い `CREATE_FAILED` の行を **1 つだけ**探す（一番上の方にある、最初に失敗したもの）
2. 「状況の理由」を読む。よくあるもの:
   - `The key pair 'kikagaku-cli-key' does not exist` → キーペアを作っていない（1-1）
   - `Parameter validation failed ... MyIp` → IP に `/32` を付けた、または空欄
   - `AssertDescription: このテンプレートは東京リージョン専用` → リージョンが東京ではない
   - `VPC limit exceeded` → アカウントの VPC 上限（5 個）。古い VPC を消す
3. スタックを**削除**し、原因を直してから、もう一度「2. 作る」

`CREATE_COMPLETE` なのにブラウザで表示されない場合は、サーバー内の起動スクリプトが失敗しています。SSH で入って次を見てください。

```bash
sudo cat /var/log/cloud-init-output.log   # stage1
sudo cat /var/log/user-data.log           # stage2 / stage3
```

「タイムアウト」なら自宅 IP が変わっている可能性が高いので、checkip で再確認して SG を直してください。

---

## 5. 消す（スタックの削除）

1. **手で足したものがあれば先に消す**（手で作ったサブネット、EC2、NAT など）
2. CloudFormation → スタックを選び「削除」
3. `DELETE_COMPLETE` になるまで待つ（NAT があると 3〜5 分）。スタックが一覧から消えれば完了
4. 翌日以降に **請求ダッシュボード**（右上のアカウント名 → 請求とコスト管理）を一度見て、EC2・NAT・EIP の行が増えていないことを確認

```bash
# CLI の場合
aws cloudformation delete-stack --stack-name kikagaku-stage1
aws cloudformation wait stack-delete-complete --stack-name kikagaku-stage1
```

`DELETE_FAILED` になったら、イベントタブで「どのリソースが消せなかったか」を見て、それを手で消してから再度「削除」を押してください。ほとんどの場合、手で足したリソースが VPC に残っているのが原因です。

---

## 6. 手動で作った環境の片付け（スタックを使っていない人）

第2回・第3回に出席して手で作った環境には、スタックがありません。次の順に消してください。順番を間違えると「依存関係があるので消せない」と言われます。

| 順番 | 消すもの | 場所 |
|---|---|---|
| 1 | EC2 インスタンス（Web / DB）を「**終了**」 | EC2 → インスタンス（停止ではなく終了） |
| 2 | NAT ゲートウェイ | VPC → NAT ゲートウェイ（「削除済み」になるまで数分待つ） |
| 3 | Elastic IP を「**解放**」 | VPC → Elastic IP（NAT 削除後でないと解放できない） |
| 4 | VPC | VPC → お使いの VPC（サブネット・IGW・ルートテーブル・SG も一緒に消えます） |
| 5 | 請求ダッシュボードを確認 | 右上のアカウント名 → 請求とコスト管理 |

キーペア `kikagaku-cli-key` は課金されないので残して構いません。

---

## 7. よくある質問

**Q. 第2回を手で作った状態から、第3回の分だけテンプレートで足せますか？**
できません。各テンプレートは単独で完結する設計です。手で作った環境を「6.」で消してから `stage2` を作るか、手で作った環境の上に Notion の手順で手動で進めてください。

**Q. 停止（stop）して翌日起動したら繋がらなくなりました。**
パブリック IP は停止→起動で変わります。EC2 コンソールで新しい IP を確認してください。スタックの「出力」タブは作成時の値のままで更新されません。DB サーバーのプライベート IP は変わりません。

**Q. 出力の URL を開いても「タイムアウト」になります。**
自宅 IP が変わった可能性が高いです。checkip で確認し、SG `kikagaku-cli-sg` のソースを新しい IP/32 に直してください。`https://` ではなく `http://` で開いているかも確認してください。

**Q. テンプレートの中身を読みたい。**
YAML の `Resources:` 以下が、第2回に CLI で打ったコマンド 1 つ 1 つに対応しています（`create-vpc` → `AWS::EC2::VPC`、`create-subnet` → `AWS::EC2::Subnet` …）。コメントも入れてあるので、Notion の手順書と並べて読んでみてください。

---

## 補足: 料金の目安（東京リージョン、2026 年 9 月時点）

| リソース | 目安 |
|---|---|
| EC2 t2.micro × 2 | 無料枠（月 750 時間まで、アカウント作成から 12 か月） |
| NAT ゲートウェイ | 約 0.062 USD/時 ＋ データ処理 約 0.062 USD/GB |
| Elastic IP | 約 0.005 USD/時（NAT に付いていても課金） |
| CloudFormation | 無料 |

最新の料金は AWS 公式の料金表で確認してください。
