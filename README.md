# クラウドインフラ基礎講座 フォローアップ会 追いつき用 CloudFormation テンプレート

フォローアップ会（第2回〜第4回）の各回の「終了時点の環境」を、AWS CloudFormation で一度に作るためのテンプレートです。
欠席した回がある人、途中で詰まって環境が崩れた人、もう一度きれいな状態から始めたい人向けです。

| ファイル | 作られる環境 | こんな人向け |
|---|---|---|
| `stage1-day1.yaml` | **第2回（Notion Day1）終了時点**: VPC / パブリックサブネット / IGW / ルートテーブル / SG / Web サーバー（Apache 起動済み） | 第2回を欠席し、第3回から参加する人 |
| `stage2-day2.yaml` | **第3回（Notion Day2）終了時点**: 上記 ＋ プライベートサブネット / DB サーバー / NAT ゲートウェイ ＋ Elastic IP | 第3回を欠席し、第4回から参加する人 |
| `stage3-day3.yaml` | **第4回（Notion Day3）終了時点**: 上記 ＋ MariaDB（wordpress DB 作成済み） / PHP ＋ WordPress / 演習3 の sample.php | 第4回を欠席した人、完成形をもう一度見たい人 |

> **自分の手で作りながら学びたい人へ**: CloudFormation を使わず 1 つずつ作る手順は [lecture/](lecture/README.md)（[day1.md](lecture/day1.md) / [day2.md](lecture/day2.md) / [day3.md](lecture/day3.md)）にあります。各コマンドが何をしているかの説明、詰まったときの表、演習まで、この 3 ファイルだけでハンズオンが完結します。

リソース名・IP アドレス（`kikagaku-cli-vpc`、`10.1.0.0/16`、`10.1.1.0/24`、`10.1.2.0/24` など）は Notion の手順書と同じにしてあるので、作成後にコンソールで見たときに手順書のスクリーンショットと同じ景色になります。

削除は「5. 消す」の手順で、**手で作ったものもテンプレートで作ったものも同じ順番で消えます**。全自動で消したい人向けに `scripts/cleanup.sh` も用意しています。`scripts/` にある 3 つのスクリプトの使い分けは「7.」にまとめています。

---

## 0. 使う前に決めておくルール

1. **手動で作った環境と混ぜない。** 自分で作った `kikagaku-cli-vpc` が残っている状態でテンプレートを実行すると、名前が同じリソースが 2 組できて混乱します。先に「5. 消す」の手順で消してから使ってください。
2. **テンプレートで作った環境の上に、手で足すのは OK。** たとえば `stage1` で作った VPC に、第3回の手順どおり手でプライベートサブネットや NAT を足して構いません。消すときは「5. 消す」の順番どおりに進めれば、手で足したものもスタックが作ったものも区別せずに消えます。
3. **リージョンは東京（ap-northeast-1）。** 他のリージョンではテンプレートがエラーを出して止まります。
4. **NAT ゲートウェイは時間課金です**（1 時間あたり約 0.062 USD、放置すると月 6,000〜7,000 円）。`stage2` と `stage3` を作ったら、その日のうちにスタックを削除するか、`stage2` は `EnableNat=false` で作り直してください。

---

## 1. 事前準備（初回だけ・5 分）

### 1-1. キーペアを 1 つ作る

テンプレートは「既存のキーペア名」を受け取ります。まだ持っていない人は次の手順で作ってください。

1. AWS コンソール → **EC2** → 左メニュー「キーペア」→「キーペアを作成」
2. 名前: `kikagaku-cli-key`、タイプ: RSA、形式: `.pem`
3. 「作成」を押すと `kikagaku-cli-key.pem` が自動でダウンロードされます。**分かる場所に保存**してください（後で ssh に使います）
4. 権限を絞ります

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
4. パラメータを入れる。**入力が必要な項目はファイルごとに違います。** 画面には英語のラベルで出ます（日本語にするとコンソールが「????」と表示するため）。

   **スタック名**（全ファイル共通）: `kikagaku-stage1` / `kikagaku-stage2` / `kikagaku-stage3` のように、ファイルに合わせて付けてください。

   ### stage1-day1.yaml（第2回終了時点）: 入力 2 つ

   | 画面のラベル | 意味 | 入れる値 |
   |---|---|---|
   | Home IP address (from checkip.amazonaws.com) | 自宅のグローバル IP | 1-2 でメモした値。`/32` は付けない（例 `113.147.224.53`） |
   | Key pair name | SSH に使うキーペア | 1-1 で作った `kikagaku-cli-key`（プルダウンから選ぶ） |
   | LatestAmiId | OS のイメージ | **変更不要**（そのまま） |

   ### stage2-day2.yaml（第3回終了時点）: 入力 3 つ

   | 画面のラベル | 意味 | 入れる値 |
   |---|---|---|
   | Home IP address (from checkip.amazonaws.com) | 自宅のグローバル IP | stage1 と同じ |
   | Key pair name | SSH に使うキーペア（Web・DB 共通） | stage1 と同じ |
   | Create NAT gateway (true / false) | NAT ゲートウェイと Elastic IP を作るか | `true` = 第3回終了時点そのもの（時間課金あり）。`false` = 宿題で NAT と EIP を消した状態 |
   | LatestAmiId | OS のイメージ | **変更不要** |

   ### stage3-day3.yaml（第4回終了時点）: 入力 3 つ

   | 画面のラベル | 意味 | 入れる値 |
   |---|---|---|
   | Home IP address (from checkip.amazonaws.com) | 自宅のグローバル IP | stage1 と同じ |
   | Key pair name | SSH に使うキーペア（Web・DB 共通） | stage1 と同じ |
   | MariaDB root password | DB の root パスワード（Notion 6 章で自分で決める値に相当） | 英数字 8〜32 文字。初期値 `rootpasswd` のままでも可。**後で `mysql -u root -p` に使うのでメモ** |
   | LatestAmiId | OS のイメージ | **変更不要** |

   stage3 に NAT の有無の選択はありません（DB サーバーが MariaDB を取りに外へ出るため、NAT は必ず作ります）。

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

## 5. 消す（手動で作ったものも、テンプレートで作ったものも同じ手順）

「どちらで作ったか」は気にしなくて大丈夫です。**中身を葉から順に消して、最後にスタックの記録を消す**、の順番だけ守ってください。CloudFormation は「すでに存在しないリソース」の削除を成功として扱うので、先に手で消しておいても問題ありません。

### 5-1. コンソールで消す（5 手順）

| 順番 | 消すもの | 場所 |
|---|---|---|
| 1 | EC2 インスタンス（Web / DB / 自分で足したもの）を「**終了**」 | EC2 → インスタンス（停止ではなく終了） |
| 2 | NAT ゲートウェイ（自分で足したものも） | VPC → NAT ゲートウェイ（「削除済み」になるまで数分待つ） |
| 3 | Elastic IP を「**解放**」 | VPC → Elastic IP（NAT 削除後でないと解放できない） |
| 4 | VPC `kikagaku-cli-vpc` | VPC → お使いの VPC → 「VPC の削除」（サブネット・IGW・ルートテーブル・SG も一緒に消えます） |
| 5 | スタック（テンプレートを使った人だけ） | CloudFormation → スタック → 「削除」。中身はもう無いので数十秒で `DELETE_COMPLETE` になります |

翌日以降に **請求ダッシュボード**（右上のアカウント名 → 請求とコスト管理）を一度見て、EC2・NAT・EIP の行が増えていないことを確認してください。キーペア `kikagaku-cli-key` は課金されないので残して構いません。

手順 4 で「依存関係があるので削除できません」と出たら、手順 1〜3 で消し忘れたものがあります。ダイアログに残っているリソースが表示されるので、それを消してからもう一度 4 を実行してください。

### 5-2. CloudShell で 1 コマンドで消す（おすすめ）

コンソール右上の CloudShell（`>_`）を開き、リージョンが東京であることを確認して、次の 1 行を貼り付けます。

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kikagaku/aws-handson-cloudformation/main/scripts/cleanup.sh)
```

名前に `kikagaku` を含む VPC の中身を上の順番で全部消し（各段階の完了を待ちながら進みます）、`kikagaku-*` のスタックも削除します。実行前に消す対象を一覧表示して `yes` を待つので、内容を見てから確定してください。デフォルト VPC、他の名前の VPC、キーペアには触りません。途中で止まっても、もう一度同じコマンドを実行すれば続きから消えます。

詳しい説明と、コンソールだけで消す手順は [docs/cleanup-manual.md](docs/cleanup-manual.md) を見てください。

スタックだけを消したい場合（中身は自分で消した後など）は `scripts/delete.sh 1` か、コンソールの「削除」で構いません。

---

## 6. 補足: なぜ「順番」が必要なのか

AWS のリソースは「VPC の中にサブネット、サブネットの中に EC2」のように入れ子になっていて、中に何かが残っている箱は消せません。だから消すときは一番内側（EC2、NAT）から外側（VPC）へ向かいます。第2回の「作る順番は外側から内側へ」の逆です。CloudFormation のスタック削除はこの順番を自動でやってくれていますが、スタックの外で足したものは知らないので、手順 1〜4 で自分が消す、という関係になります。

---

## 7. scripts フォルダの 3 つのスクリプトの使い分け

役割は「作る」「スタックだけ消す」「全部消す」の 3 つです。**受講生に必要なのは、作るのはコンソール、消すのは `cleanup.sh` の 2 つだけ**です。残りは CLI に慣れた人向けの補助です。

| スクリプト | 何をするか | 使う場面 | 前提 |
|---|---|---|---|
| `scripts/cleanup.sh` | 名前に `kikagaku` を含む VPC の中身を依存の順番どおりに待ちながら全部消し、最後にスタックの記録も消す | 手動で作った環境、スタックの上に手で NAT やサブネットを足した環境、何が残っているか分からなくなったとき。**迷ったらこれ** | CloudShell に 1 行貼るだけ（clone 不要） |
| `scripts/deploy.sh` | テンプレートをアップロードしてスタックを作り、完成後に「出力」（URL・ssh コマンド）を表で出す | 「2. 作る」のコンソール操作をコマンド 1 行で済ませたいとき | AWS CLI が動く環境（PC または CloudShell）にこのリポジトリを clone してあること |
| `scripts/delete.sh` | 指定した stage のスタックを削除し、消え終わるまで待つ。コンソールの「スタックを削除」ボタンと同じ | テンプレートで作った環境に**手で何も足していない**と自分で判断できるとき | 同上 |

```bash
# 作る（stage 番号と自宅 IP。3 つ目以降は省略可）
scripts/deploy.sh 1 113.147.224.53
scripts/deploy.sh 2 113.147.224.53 kikagaku-cli-key false   # stage2 を NAT なしで

# スタックだけ消す（手で何も足していないときだけ）
scripts/delete.sh 1

# 全部消す（CloudShell に貼る。clone していなくてよい）
bash <(curl -fsSL https://raw.githubusercontent.com/kikagaku/aws-handson-cloudformation/main/scripts/cleanup.sh)
```

`delete.sh` は、スタックの上に手で足したものがあると `DELETE_FAILED` になります。その判断に自信がなければ `cleanup.sh` を使ってください。`cleanup.sh` は `delete.sh` の機能を含んでいるので、消すときは常に `cleanup.sh` で構いません。

---

## 8. よくある質問

**Q. 第2回を手で作った状態から、第3回の分だけテンプレートで足せますか？**
できません。各テンプレートは単独で完結する設計です。手で作った環境を「5.」で消してから `stage2` を作るか、手で作った環境の上に Notion の手順で手動で進めてください。

**Q. スタックで作った VPC に、自分で NAT やサブネットを足して実験しました。消すときは？**
「5.」の手順のままで大丈夫です。足したものも含めて葉から順に消し、最後にスタックを削除します。`scripts/cleanup.sh` なら区別せずに全部消します。

**Q. 停止（stop）して翌日起動したら繋がらなくなりました。**
パブリック IP は停止→起動で変わります。EC2 コンソールで新しい IP を確認してください。スタックの「出力」タブは作成時の値のままで更新されません。DB サーバーのプライベート IP は変わりません。

**Q. 出力の URL を開いても「タイムアウト」になります。**
自宅 IP が変わった可能性が高いです。checkip で確認し、SG `kikagaku-cli-sg` のソースを新しい IP/32 に直してください。`https://` ではなく `http://` で開いているかも確認してください。

**Q. パラメータ画面の文字が「????」になります。**
CloudFormation のコンソールは、パラメータの説明文やラベルに日本語があると「????」と表示します（S3 経由でアップロードしても同じです）。そのためテンプレートの説明文は英語にしてあります。リソース定義やタグ、サーバー内で動くスクリプトの日本語は問題なく通ります。

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
