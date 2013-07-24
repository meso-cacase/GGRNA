統合遺伝子検索GGRNA.v2
======================

遺伝子をGoogleのように検索できるウェブサービスです。

検索キーワードとして、遺伝子名やアクセッション番号など各種のIDをはじめ、  
遺伝子の機能やタンパク質のドメイン名、さらには、塩基配列やアミノ酸配列など、  
あらゆる語句を単一の検索窓に入力するだけでRefSeqに登録された転写産物を  
すばやく探し出すことができます。

+ 統合遺伝子検索GGRNA (http://GGRNA.dbcls.jp/)  
  本レポジトリにあるCGIが実際に稼働しています。

なお、本レポジトリはGGRNAのウェブインターフェース部分です。  
ユーザからのリクエストを受け付け、検索を実行するサーチャにクエリを発行し、  
得られたデータを処理してユーザに検索結果を返します。  

サーチャはプリファードインフラストラクチャー
([PFI](http://preferred.jp/)) の
[Sedue](http://preferred.jp/product/sedue/) を使用しています。  
Sedueは、接尾辞配列のインデックスをSSDに保持することによって、塩基配列や  
アミノ酸配列を含む検索語を、見落としなく、きわめて高速に検索します。


サンプル画像
-----

![スクリーンショット]
(http://g86.dbcls.jp/~meso/meme/wp-content/uploads/2013/07/GGRNA.v2.jpg
"GGRNAスクリーンショット")

トップページ (左図) の検索窓に、[```Argonaute "PAZ domain"```]
(http://GGRNA.dbcls.jp/hs/Argonaute+%22PAZ+domain%22)
と入力して  
ヒトの遺伝子を検索した例 (右図)。キーワードは緑色にハイライトされます。  
また、マイクロアレイのプローブID [```1552311_a_at```]
(http://GGRNA.dbcls.jp/1552311_a_at)
を検索した例 (下図)。  
AffymetrixのプローブIDは、対応する25 merのプローブ配列×11本に変換され、  
塩基配列による検索が行われます。


文献
--------

+ GGRNAの[ヘルプページ](http://GGRNA.dbcls.jp/help.html)

+ 内藤雄樹・坊農秀雅 (2012)  
[統合遺伝子検索GGRNA：遺伝子をGoogleのように検索できるウェブサーバ.]
(http://first.lifesciencedb.jp/from_dbcls/e0001)  
ライフサイエンス 新着論文レビュー (DBCLSからの成果発信). [ [PDF] ]
(http://g86.dbcls.jp/~meso/meme/wp-content/uploads/2012/06/GGRNAreviewJ1.pdf)

+ Yuki Naito & Hidemasa Bono (2012)  
[GGRNA: an ultrafast, transcript-oriented search engine 
for genes and transcripts.]
(http://nar.oxfordjournals.org/content/40/W1/W592.full)  
*Nucleic Acids Res.* **40**, W592-W596.


関連プロジェクト
--------

+ 高速塩基配列検索GGGenome (http://GGGenome.dbcls.jp/)


更新履歴
--------

### 2013年7月8日 ###

+ GGRNA.v2をリリース。

従来のGGRNAは、インメモリの圧縮接尾辞配列インデックスを利用していたため、  
メモリ容量の制約から13種類のモデル生物に限ってサービスを提供してきた。  
また、ヒット件数が極端に多い場合は圧縮接尾辞配列の解凍に時間がかかるという  
課題があった。そこで、サーチャを最新版のSedueに置き換えて、非圧縮の  
接尾辞配列インデックスをSSDに載せる方針 (SSD方式) に変更した。


ライセンス
--------

Copyright &copy; 2012-2013 Yuki Naito
 ([@meso_cacase](http://twitter.com/meso_cacase))  
This software is distributed under [modified BSD license]
 (http://www.opensource.org/licenses/bsd-license.php).
