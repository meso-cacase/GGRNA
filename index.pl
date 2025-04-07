#!/usr/bin/perl

# GGRNA (ググルナ)： 遺伝子をGoogleのように検索するサービス
# https://GGRNA.dbcls.jp/
#
# SSD検索サーバに問い合わせを行い、結果を HTML, TXT, JSON 形式で出力する
#
# 必要なモジュール：
# HTML::Template
# JSON::XS
# ./Sedue.pm
#   LWP::Simple (Sedue.pm内で使用)
#   JSON::XS    (Sedue.pm内で使用)
#
# 2013-07-08 Yuki Naito (@meso_cacase) GGRNA.v2リリース

#- ▼ モジュール読み込みと変数の初期化
use warnings ;
use strict ;
use Time::HiRes ;

eval 'use HTML::Template ; 1' or  # HTMLをテンプレート化
	printresult('ERROR : cannot load HTML::Template') ;

eval 'use JSON::XS ; 1' or        # hit_positionsのデコードに使用
	printresult('ERROR : cannot load JSON::XS') ;

eval 'use Sedue ; 1' or           # Sedueに問い合わせを行うためのモジュール
	printresult('ERROR : cannot load Sedue') ;

my $refseq_version = 'RefSeq release 229 (Mar, 2025)' ;
my $ddbj_version   = 'DDBJ release 92.0 (Feb, 2013)' ;

my @timer ;                       # 実行時間計測用
my $timestamp = timestamp() ;     # CGIを実行した時刻
my $max_hit_html   = 50 ;         # 検索を打ち切るヒット件数、HTMLの場合
my $max_hit_api    = 10000 ;      # 検索を打ち切るヒット件数、TXTまたはJSONの場合
my $min_seq_length = 6 ;          # 塩基配列クエリの最低の長さ

my %spe_fullname = (              # 生物種の正式名
	'hs' => 'Homo sapiens (human)',
	'mm' => 'Mus musculus (house mouse)',
	'rn' => 'Rattus norvegicus (Norway rat)',
	'gg' => 'Gallus gallus (chicken)',
	'xt' => 'Xenopus tropicalis (tropical clawed frog)',
	'dr' => 'Danio rerio (zebrafish)',
	'ci' => 'Ciona intestinalis (vase tunicate)',
	'dm' => 'Drosophila melanogaster (fruit fly)',
	'ce' => 'Caenorhabditis elegans',
	'at' => 'Arabidopsis thaliana (thale cress)',
	'os' => 'Oryza sativa Japonica Group (Japanese rice)',
	'sc' => 'Saccharomyces cerevisiae S288C',
	'sp' => 'Schizosaccharomyces pombe (fission yeast)'
) ;
#- ▲ モジュール読み込みと変数の初期化

#- ▼ リクエストからパラメータを取得
push @timer, [Time::HiRes::time(), 'start;'] ;                       #===== 実行時間計測 =====

#-- ▽ 使用するパラメータ一覧
my $lang         = '' ;  # HTMLの場合の日本語/英語: ja, en
my $div          = '' ;  # Division: PRI, PAT, ...
my $spe          = '' ;  # 生物種: hs, mm, ...
my $query_string = '' ;  # 検索クエリ: 1つまたは複数の検索ワード
my $format       = '' ;  # 出力フォーマット: html, txt, json
my $download     = '' ;  # ファイルとしてダウンロードするか: (boolean)
#-- △ 使用するパラメータ一覧

#-- ▽ URIからパラメータを取得
# 例：/en/PAT/dm/GCAAGAGAGATTGCTTAGCG.txt.download
#
my $request_uri = $ENV{'REQUEST_URI'} // '' ;
$request_uri =~ s/\?.*// ;  # '?' 以降のQUERY_STRING部分を除去

#--- ▽ スラッシュ間 (/param/) のパラメーターを処理
while ($request_uri =~ m{([^/]+)(/?)}g){
	my ($param, $slash) = ($1, $2) ;
	$param =~ s/^human$/hs/i ;  # RefExからのリンク対応: human → hs にリダイレクト
	$param =~ s/^mouse$/mm/i ;  # RefExからのリンク対応: mouse → mm にリダイレクト
	$param =~ s/^rat$/rn/i ;    # RefExからのリンク対応: rat   → rn にリダイレクト

	($param =~ /^(ja|en)$/i) ?
		$lang = lc $1 :

	($param =~ /^(HUM|PRI|ROD|MAM|VRT|INV|PLN|BCT|VRL|PHG|
	              PAT|ENV|SYN|EST|TSA|GSS|HTC|HTG|STS|UNA|
	              CON|REFSEQ|ALL)$/xi) ?
		$div = uc $1 :

	($param =~ /^(hs|mm|dm|ce|rn|gg|dr|at|sc|sp|xt|os|ci|zoo)$/i) ?
		$spe = lc $1 :

	(not $slash) ?  # 上記に当てはまらず最後の要素: $query_string へ
		$query_string = url_decode($param) :

	() ;  # 解釈できないものは無視
}
#--- △ スラッシュ間 (/param/) のパラメーターを処理

#--- ▽ パスの最後の要素 (query.format) を処理
if ($query_string =~ s/(?:\.(html|txt|json)|\.(download))+$//i){
	$1 and $format   = lc $1 ;
	$2 and $download = 'true' ;
}
#--- △ パスの最後の要素 (query.format) を処理
#-- △ URIからパラメータを取得

#-- ▽ QUERY_STRINGからパラメータを取得
my %query = get_query_parameters() ;  # HTTPリクエストからクエリを取得

$query_string =                       # 検索クエリ
	$query{'query'} //                # 1) QUERY_STRINGから
	$query_string   //                # 2) QUERY_STRING未指定 → URIから
	'' ;                              # 3) URI未指定 → 空欄

$lang =                               # HTMLの場合の日本語/英語
	(defined $query{'lang'} and $query{'lang'} =~ /^(ja|en)?$/i) ?
	lc($query{'lang'}) :              # 1) QUERY_STRINGから
	$lang //                          # 2) QUERY_STRING未指定 → URIから
	'' ;                              # 3) URI未指定 → 空欄

$div = uc(                            # Division
	$query{'div'} //                  # 1) QUERY_STRINGから
	$div          //                  # 2) QUERY_STRING未指定 → URIから
	'') ;                             # 3) URI未指定 → 空欄

$spe = lc(                            # 生物種
	$query{'spe'} //                  # 1) QUERY_STRINGから
	$spe          //                  # 2) QUERY_STRING未指定 → URIから
	'') ;                             # 3) URI未指定 → 空欄

$format =                             # 出力フォーマット
	(defined $query{'format'} and $query{'format'} =~ /^(html|txt|json)?$/i) ?
	lc($query{'format'}) :            # 1) QUERY_STRINGから
	$format //                        # 2) QUERY_STRING未指定 → URIから
	'' ;                              # 3) URI未指定 → 空欄

$download =                           # ファイルとしてダウンロードするか
	($format =~ /^(txt|json)$/) ?     # ダウンロードはtxt,jsonの場合に限る
	$query{'download'} //             # 1) QUERY_STRINGから
	$download //                      # 2) QUERY_STRING未指定 → URIから
	'' :                              # 3) URI未指定 → 空欄
	'' ;                              # txt,json以外 → 空欄
#-- △ QUERY_STRINGからパラメータを取得
#- ▲ リクエストからパラメータを取得

#- ▼ パラメータからURIを生成してリダイレクト
my $redirect_uri = '/' ;
$redirect_uri .= ($request_uri =~ m{^/test/}) ? 'test/' : '' ;  # テストページ /test/ 対応
$redirect_uri .= $lang ? "$lang/" : '' ;
$redirect_uri .= $div  ? "$div/"  : '' ;
$redirect_uri .= $spe  ? "$spe/"  : '' ;
$redirect_uri .= url_encode($query_string) ;
$redirect_uri .= $format   ? ".$format"  : '' ;
$redirect_uri .= $download ? '.download' : '' ;

my $QUERY_STRING = $ENV{'QUERY_STRING'} // ''; #ADD tyamamot
$QUERY_STRING =~ s/offset=[0-9]*//g;           #ADD tyamamot
$QUERY_STRING =~ s/(&){2,}/$1/g;               #ADD tyamamot
if ($ENV{'HTTP_HOST'} and              # HTTP経由のリクエストで、かつ
	($request_uri ne $redirect_uri or  # 現在のURIと異なる場合にリダイレクト
	 $QUERY_STRING)                            #CHANGE tyamamot
){
	$ENV{'HTTPS'} ? redirect_page("https://$ENV{'HTTP_HOST'}$redirect_uri") :  # HTTPS経由
	                redirect_page("http://$ENV{'HTTP_HOST'}$redirect_uri")  ;  # HTTP経由
}
#- ▲ パラメータからURIを生成してリダイレクト

#- ▼ defaultパラメータ設定
$lang     ||= ($0 =~ /ja$/) ? 'ja' :  # lang が未定義で実行ファイルが index.cgi.ja の場合
              ($0 =~ /en$/) ? 'en' :  # lang が未定義で実行ファイルが index.cgi.en の場合
                              'en' ;  # default: en
$div      ||= '' ;
$spe      ||= '' ;
$format   ||= 'html' ;
$download ||= '' ;
#- ▲ defaultパラメータ設定

#- ▼ リクエストから検索ワードリストを生成、ヒット件数を取得
push @timer, [Time::HiRes::time(), 'search_start;'] ;                #===== 実行時間計測 =====

my @query_array = split_query($query_string)  # 検索ワードリスト
	or printresult() ;    # クエリが空欄の場合はトップページを表示
my @expand_query_array ;  # comp: や iub: で展開された検索ワードのリスト、ハイライトに使用
my @sedue_query_array ;   # 検索ワードごとに生成されたsedueクエリリスト
my @hit_num ;             # 検索ワードごとのヒット件数
foreach (@query_array){

	#- ▼ 検索ワードのパターンに応じてクエリ生成
	my ($tag, $q) = ('', '') ;
	my $sedue_query = '' ;

	#-- ▽ refid:NM_001518 ▽
	if (s/^(?:refid:|refseqid:|refseq:|(?:id:)?(?=[NX][MR]_))([^\.]*)(?:\..*)?$/refid:$1/i){
		$tag = 'refid:' ;
		$q   = $1 or next ;
		$sedue_query = "(accession:exact:@{[escape_sedueq($q)]})" ;

	#-- ▽ gi:240849334 ▽
	} elsif (s/^gi:(.*)$/gi:$1/i){
		$tag = 'gi:' ;
		$q   = $1 or next ;
		$sedue_query = "(gi:exact:@{[escape_sedueq($q)]})" ;

	#-- ▽ spe:"Homo sapiens" ▽
	} elsif (s/^(?:spe:|species:|source:|organism:)(.*)$/spe:$1/i){
		$tag = 'spe:' ;
		$q   = $1 or next ;
		$sedue_query = "(full_search:source:@{[escape_sedueq($q)]})" ;

	#-- ▽ geneid:10579 ▽
	} elsif (s/^(?:geneid:|(?:gene:|id:)?(?=\d+$))0*(.*)$/geneid:$1/i){
		$tag = 'geneid:' ;
		$q   = $1 or next ;
		$sedue_query = "(geneid:exact:@{[escape_sedueq($q)]})" ;

	#-- ▽ symbol:VIM ▽
	} elsif (s/^(?:symbol:|name:|gene:(?=[A-Za-z]))(.*)$/symbol:$1/i){
		$tag = 'symbol:' ;
		$q   = $1 or next ;
		$sedue_query = "(full_search:symbol,synonym:@{[escape_sedueq($q)]})" ;

	#-- ▽ aa:KLQEEM ▽
	} elsif (s/^aa:(.*)$/aa:$1/i){
		$tag = 'aa:' ;
		$q   = $1 or next ;
		$sedue_query = "(aa:@{[escape_sedueq($q)]})" ;

	#-- ▽ ref:Naito ▽
	} elsif (s/^(?:ref:|reference:)(.*)$/ref:$1/i){
		$tag = 'ref:' ;
		$q   = $1 or next ;
		$sedue_query = "(full_search:reference:@{[escape_sedueq($q)]})" ;

	#-- ▽ seq:caagaagagattgc ▽
	} elsif (
		s/^(?:seq:|sequence:)(.*)$/seq:$1/i or
		s/^([atgcu]{$min_seq_length,})$/seq:$1/i
	){
		$tag = 'seq:' ;
		$q   = $1 or next ;
		$sedue_query = "(nt:@{[escape_sedueq(rna2dna($q))]})" ;

	#-- ▽ comp:caagaagagattgc ▽
	} elsif (s/^(?:comp:|complementary:)(.*)$/comp:$1/i){
		$tag = 'comp:' ;
		$q   = $1 or next ;
		$sedue_query = "(nt:@{[escape_sedueq(comp(rna2dna($q)))]})" ;
		push @expand_query_array, comp(rna2dna($q)) ;

	#-- ▽ both:caagaagagattgc ▽
	} elsif (s/^(?:both:|bothseq:)(.*)$/both:$1/i){
		$tag = 'both:' ;
		$q   = $1 or next ;
		$sedue_query =
			"((nt:@{[escape_sedueq(rna2dna($q))]})%7C" .  # %7C = |
			"(nt:@{[escape_sedueq(comp(rna2dna($q)))]}))" ;
		push @expand_query_array, comp(rna2dna($q)) ;

	#-- ▽ iub:caagaagagattgc ▽
	} elsif (s/^iub(?:seq)?:(.*)$/iub:$1/i){
		$tag = 'iub:' ;
		$q   = $1 // '' ;
		my @exq = iub_expand(flatsequence(rna2dna($q))) or next ;
		push @expand_query_array, @exq ;
		map { $_ = "(nt:@{[escape_sedueq($_)]})" } @exq ;
		$sedue_query = '(' . join('%7C', @exq) . ')' ;  # %7C = |

	#-- ▽ iubcomp:caagaagagattgc ▽
	} elsif (s/^iubcomp:(.*)$/iubcomp:$1/i){
		$tag = 'iubcomp:' ;
		$q   = $1 // '' ;
		my @exq = iub_expand(flatsequence(comp(rna2dna($q)))) or next ;
		push @expand_query_array, @exq ;
		map { $_ = "(nt:@{[escape_sedueq($_)]})" } @exq ;
		$sedue_query = '(' . join('%7C', @exq) . ')' ;  # %7C = |

	#-- ▽ iubboth:caagaagagattgc ▽
	} elsif (s/^iubboth:(.*)$/iubboth:$1/i){
		$tag = 'iubboth:' ;
		$q   = $1 // '' ;
		my @exq = (
			iub_expand(flatsequence(rna2dna($q))),
			iub_expand(flatsequence(comp(rna2dna($q))))
		) or next ;
		push @expand_query_array, @exq ;
		map { $_ = "(nt:@{[escape_sedueq($_)]})" } @exq ;
		$sedue_query = '(' . join('%7C', @exq) . ')' ;  # %7C = |

	#-- ▽ その他フリーワード検索 ▽
	} else {
		$q = $_ or next ;
		$sedue_query =
			'(' .
			"(full_search:*:@{[escape_sedueq($q)]})%7C" .  # %7C = |
			"(nt:@{[escape_sedueq($q)]})%7C" .
			"(aa:@{[escape_sedueq($q)]})" .
			')' ;
	}
	#- ▲ 検索ワードのパターンに応じてクエリ生成

	#- ▼ ヒット件数を取得
	$sedue_query or next ;  # 空欄の場合はパス

	push @sedue_query_array, $sedue_query ;

	$spe_fullname{$spe} and $sedue_query .= "?source=$spe_fullname{$spe}" ;
	$div and $sedue_query .= "?division=$div" ;

	my $hit = Sedue::sedue_hit_num($sedue_query) or
		printresult('ERROR : cannot connect to searcher (1)') ;

	my $hit_num = $hit->{hit_num} // '' ;
	my $uri     = $hit->{uri}     // '' ;

	push @timer, [Time::HiRes::time(), "count_done; $uri"] ;         #===== 実行時間計測 =====
	#- ▲ ヒット件数を取得

	#- ▼ 検索ワードごとのヒット件数
	push @hit_num, {
		tag     => $tag,
		q       => $q,
		hit_num => $hit_num
	} ;
	#- ▲ 検索ワードごとのヒット件数
}
#- ▲ リクエストから検索ワードリストを生成、ヒット件数を取得

#- ▼ AND検索
@sedue_query_array or printresult() ;  # クエリが空欄の場合はトップページを表示
my $sedue_query = join('%26', @sedue_query_array) ;

$spe_fullname{$spe} and $sedue_query .= "?source=$spe_fullname{$spe}" ;
$div and $sedue_query .= "?division=$div" ;

my $limit = $ENV{'MAX_HIT'} = ($format eq 'txt' or $format eq 'json') ?  #CHANGE tyamamot
	$max_hit_api : $max_hit_html ;

my $offset = $query{'offset'} // 0;                 #ADD tyamamot offsetの追加
my $hit = Sedue::sedue_q($sedue_query, $offset) or  #CHANGE tyamamot offsetの追加
	printresult('ERROR : cannot connect to searcher (2)') ;

my $uri     = $hit->{uri}       // '' ;
my $exact   = $hit->{hit_exact} // '' ;
my $hit_num = $hit->{hit_num}   // '' ;
my $total   = $hit_num ;                            #ADD tyamamot totalの追加
$hit_num =~ s/^(\d{2})(\d*)/'~' . $1 . 0 x length($2)/e
	unless $exact ;  # 予測値は有効数字2桁とし先頭に~を付加

push @hit_num, {
	tag     => 'INTERSECTION:',
	q       => 'INTERSECTION',
	hit_num => $hit_num
} ;

push @timer, [Time::HiRes::time(), "search_done; $uri"] ;            #===== 実行時間計測 =====
#- ▲ AND検索

#- ▼ 検索結果出力
#-- ▽ TXT(タブ区切りテキスト)形式
if ($format eq 'txt'){
	my @summary ;   # 検索ワードごとのヒット件数
	push @summary, "# [ GGRNA.v2 | $timestamp ]" ;
	push @summary, "#" ;

	# 検索ワードごとのヒット件数
	foreach (@hit_num){
		my $tag     = $_->{tag}     // '' ;
		my $q       = $_->{q}       // '' ;
		my $hit_num = $_->{hit_num} // '' ;
		($tag eq 'INTERSECTION:') ?
			push @summary, "# [INTERSECTION]	$hit_num" :
			push @summary, "# $tag$q	$hit_num" ;
	}
	push @summary, '#' ;

	# 検索結果
	my @hit_list ;  # 検索結果のリスト
	foreach (@{$hit->{docs}}){
		push @hit_list, show_hit_txt($_) ;
	}

	push @summary,
		'# ' .
		join("\t", qw/
			accession
			version
			gi
			length
			symbol
			synonym
			geneid
			division
			source
			definition
			nt_position
			aa_position
		/) ;
	@hit_list or push @hit_list, '### No items found. ###' ;  # ヒットがゼロ件
	print_txt(join "\n", (@summary, @hit_list)) ;
#-- △ TXT(タブ区切りテキスト)形式

#-- ▽ JSON形式
} elsif ($format eq 'json'){
	# 検索ワードごとのヒット件数
	my @summary ;  # 検索ワードごとのヒット件数
	foreach (@hit_num){
		my $tag     = $_->{tag}     // '' ;
		my $q       = $_->{q}       // '' ;
		my $hit_num = $_->{hit_num} // '' ;
		($tag eq 'INTERSECTION:') ?
			push @summary, {
				keyword => '[INTERSECTION]',
				count   => $hit_num
			} :
			push @summary, {
				keyword => "$tag$q",
				count   => $hit_num
			} ;
	}

	# 検索結果
	my @hit_list ;  # 検索結果のリスト
	foreach (@{$hit->{docs}}){
		push @hit_list, @{ show_hit_json($_) } ;
	}

	my $json_result = JSON::XS->new->canonical->utf8->encode({
		time     => $timestamp,
		version  => "GGRNA.v2 : $refseq_version",
		summary  => \@summary,
		results  => \@hit_list,
		error    => 'none'
	}) ;
	print_json($json_result) ;
#-- △ JSON形式

#-- ▽ HTML形式
} else {  # default: html
	#--- ▽ 【Summary】検索ワードごとのヒット件数を出力
	my @summary ;
	foreach (@hit_num){
		my $tag     = $_->{tag}     // '' ;
		my $q       = $_->{q}       // '' ;
		my $hit_num = $_->{hit_num} // '' ;
		my $q_url   = $tag . $q ;
		($q_url =~ /\ |,/) and $q_url = qq/"$q_url"/ ;
		$q_url = url_encode($q_url) ;
		$q = escape_char($q) ;
		my $summary_html =
			($tag eq 'INTERSECTION:') ?
				"	<li><font color=maroon><b>INTERSECTION ($hit_num)</b></font>" .  #CHANGE tyamamot
				"<input type=hidden name='total' value='$total' />"   .  #ADD tyamamot <input type=hidden>タグの追記
				"<input type=hidden name='count' value='$hit_num' />" .  #ADD tyamamot <input type=hidden>タグの追記
				"<input type=hidden name='limit' value='$limit' />"   .  #ADD tyamamot <input type=hidden>タグの追記
				"<input type=hidden name='offset' value='$offset' />" :  #ADD tyamamot <input type=hidden>タグの追記
			($tag eq '') ?
				"	<li><a class=k href='?query=$q_url'>" .
				"$q ($hit_num)</a>" :
			($tag =~ /^(seq|comp|both|iub(comp|both)?|aa):/) ?
				"	<li><a class=k href='?query=$q_url'>" .
				"<cite>$tag</cite><span class=mono>$q</span> ($hit_num)</a>" :
			# それ以外の場合
				"	<li><a class=k href='?query=$q_url'>" .
				"<cite>$tag</cite>$q ($hit_num)</a>" ;
		push @summary, $summary_html ;
	}
	#--- △ 【Summary】検索ワードごとのヒット件数を出力

	#--- ▽ 【Results】ヒットしたエントリを出力
	my @hit_list ;  # 検索結果のリスト
	foreach (@{$hit->{docs}}){
		push @hit_list, show_hit_html($_) ;
	}
	unless ($hit_num){
		@hit_list = ('<div class=gene><p>No items found.</p></div>') ;  # ヒットがゼロ件
	}
	#--- △ 【Results】ヒットしたエントリを出力

	#--- ▽ 【Data Export】TXT/JSON出力のbase URIを生成
	my $linkbase_uri = '/' ;
	$linkbase_uri .= ($request_uri =~ m{^/test/}) ? 'test/' : '' ;  # テストページ /test/ 対応
	$linkbase_uri .= $div ? "$div/" : '' ;
	$linkbase_uri .= $spe ? "$spe/" : '' ;
	$linkbase_uri .= url_encode($query_string) ;
	#--- △ 【Data Export】TXT/JSON出力のbase URIを生成

	push @timer, [Time::HiRes::time(), 'cgi_end;'] ;                 #===== 実行時間計測 =====

	#--- ▽ 実行時間計測データの処理
	my @timelog ;
	my $start_time = ${shift @timer}[0] ;
	my $last_time = $start_time ;  # 初期値
	foreach (@timer){
		push @timelog,
			sprintf("%.3f", $$_[0] - $start_time) . ' | ' .  # 累積タイム
			sprintf("%.3f", $$_[0] - $last_time ) . ' | ' .  # 区間タイム
			$$_[1] ;  # コメント
		$last_time = $$_[0] ;
	}
	#--- △ 実行時間計測データの処理

	$query_string = escape_char($query_string // '') ;  # 結果ページに表示するためXSS対策
	$query_string =~ s/(^\s+|\s+$)//g ;                 # 先頭または末尾の空白文字を除去

	my $template_search_file = ($lang eq 'ja') ?
	                           'template/search_ja.tmpl' :  # Japanese HTML
	                           'template/search_en.tmpl' ;  # default: English HTML

	my $template_search = HTML::Template->new(filename => $template_search_file) ;

	$" = "\n" ;
	$template_search->param(
		TIMESTAMP    => $timestamp,
		REFSEQ_VER   => $refseq_version,
		SUMMARY      => "@summary",
		HIT_LIST     => "@hit_list",
		MAX_HIT_API  => $max_hit_api,
		LINKBASE_URI => $linkbase_uri,
		HTTP_HOST    => $ENV{'HTTP_HOST'},
		REDIRECT_URI => $redirect_uri,
		LANG         => $lang,
		DIV          => $div,
		SPE          => $spe,
		QUERY        => $query_string,
		FORMAT       => $format,
		DOWNLOAD     => $download,
		TIMELOG      => "@timelog"
	) ;

	($lang eq 'ja') ? print_html_ja($template_search->output) :  # Japanese HTML
	                  print_html_en($template_search->output) ;  # default: English HTML
}
#-- △ HTML形式
#- ▲ 検索結果出力

exit ;

# ====================
sub timestamp {  # タイムスタンプを 2000-01-01 00:00:00 の形式で出力
my ($sec, $min, $hour, $mday, $mon, $year) = localtime ;
return sprintf("%04d-%02d-%02d %02d:%02d:%02d",
	$year+1900, $mon+1, $mday, $hour, $min, $sec) ;
} ;
# ====================
sub get_query_parameters {  # CGIが受け取ったパラメータの処理
my $buffer = '' ;
if (defined $ENV{'REQUEST_METHOD'} and
	$ENV{'REQUEST_METHOD'} eq 'POST' and
	defined $ENV{'CONTENT_LENGTH'}
){
	eval 'read(STDIN, $buffer, $ENV{"CONTENT_LENGTH"})' or
		printresult('ERROR : get_query_parameters() : read failed') ;
} elsif (defined $ENV{'QUERY_STRING'}){
	$buffer = $ENV{'QUERY_STRING'} ;
}
my %query ;
my @query = split /&/, $buffer ;
foreach (@query){
	my ($name, $value) = split /=/ ;
	if (defined $name and defined $value){
		$name  = url_decode($name) ;
		$value = url_decode($value) ;
		$query{lc($name)} = $value ;
	}
}
return %query ;
} ;
# ====================
sub url_decode {  # URLデコード
my $str = $_[0] or return '' ;
$str =~ tr/+/ / ;
$str =~ s/%([0-9A-F]{2})/pack('C', hex($1))/ieg ;
return $str ;
} ;
# ====================
sub url_encode {  # URLエンコード
my $str = $_[0] or return '' ;
$str =~ s/([^\w\-\.\_\~\ ])/'%' . unpack('H2', $1)/eg ;
$str =~ tr/ /+/ ;
return $str ;
} ;
# ====================
sub redirect_page {  # リダイレクトする
my $uri = $_[0] // '' ;
print "Location: $uri\n\n" ;
exit ;
} ;
# ====================
sub split_query {  # クエリを検索ワードごとに分割してリスト化
my $query = $_[0] // '' ;
$query =~ s/\"(.*?)\"/escape_space($1)/eg ;  # "" 内のカンマ・スペースを実態参照に置換
my @query = split /[, \t]+/, $query ;
my @query_out ;
foreach (@query){
	$_ =~ s/&nbsp;/\ /g ;  # 実態参照を戻す
	$_ =~ s/&\#x2c;/,/g ;  # 実態参照を戻す
	#- ▼ probe: を塩基配列に展開
	if ($_ =~ s/
		^(probe:|probeid:)?
		(
			([^:]+_[as]t) |                     # Affymetrix
			((A_|ERCC-|Os|osa-|P..Control).*?)  # Agilent
		)
	$//xi){
		my @probeseq = Sedue::arrayprobe2seq(escape_sedueq($2)) or
			printresult('ERROR : cannot connect to searcher (3)') ;
		push @query_out, @probeseq ;
	}
	# probe: データベースに存在せず、seqに変換できない場合
	$_ =~ s/^(probe:|probeid:)//i ;
	#- ▲ probe: を塩基配列に展開
	#- ▼ 不正な検索ワードを除去
	unless ($_ =~ /^[;()_\[\]]?$/){
		push @query_out, $_ ;
	}
	#- ▲ 不正な検索ワードを除去
}
return @query_out ;
} ;
# ====================
sub escape_space {  # 空白文字とカンマを実態参照に変換
my $str = $_[0] // '' ;
$str =~ s/\s/&nbsp;/g ;  # 空白文字はスペースとみなす
$str =~ s/,/&\#x2c;/g ;
return $str ;
} ;
# ====================
sub flatsequence {  # 塩基構成文字以外を除去
my $seq = $_[0] or return '' ;
$seq =~ s/[^ATGCUNRYMKSWHBVD-]//gi ;
return $seq ;
} ;
# ====================
sub rna2dna {  # 塩基配列中のUをTに置換
my $seq = $_[0] or return '' ;
$seq =~ tr/Uu/Tt/ ;
return $seq ;
} ;
# ====================
sub comp {  # 相補鎖を求める
# DNA配列(A,T,G,C)を出力するが、もとの配列にUが含まれるときはRNA配列(A,U,G,C)を出力
my $seq = flatsequence($_[0]) ;
my $comp = '' ;
if ($seq =~ /U/i){  # 配列にUが含まれる → RNAの場合
	($comp = reverse $seq) =~
		tr/GATUCRYMKSWHBVDNgatucrymkswhbvdn/CUAAGYRKMSWDVBHNcuaagyrkmswdvbhn/ ;
} else {  # それ以外 → DNAの場合
	($comp = reverse $seq) =~
		tr/GATUCRYMKSWHBVDNgatucrymkswhbvdn/CTAAGYRKMSWDVBHNctaagyrkmswdvbhn/ ;
}
return $comp ;
} ;
# ====================
sub iub_expand {  # 塩基配列のIUBコードを展開してリストを返す
my @in = @_ ;
my @out ;
while (my $seq = shift @in){
	if (
		$seq =~ s/^(.*?)R(.*)$/$1A$2,$1G$2/             or  # R = A/G
		$seq =~ s/^(.*?)r(.*)$/$1a$2,$1g$2/             or
		$seq =~ s/^(.*?)Y(.*)$/$1T$2,$1C$2/             or  # Y = T/C
		$seq =~ s/^(.*?)y(.*)$/$1t$2,$1c$2/             or
		$seq =~ s/^(.*?)K(.*)$/$1T$2,$1G$2/             or  # K = T/G
		$seq =~ s/^(.*?)k(.*)$/$1t$2,$1g$2/             or
		$seq =~ s/^(.*?)M(.*)$/$1A$2,$1C$2/             or  # M = A/C
		$seq =~ s/^(.*?)m(.*)$/$1a$2,$1c$2/             or
		$seq =~ s/^(.*?)S(.*)$/$1G$2,$1C$2/             or  # S = G/C
		$seq =~ s/^(.*?)s(.*)$/$1g$2,$1c$2/             or
		$seq =~ s/^(.*?)W(.*)$/$1A$2,$1T$2/             or  # W = A/T
		$seq =~ s/^(.*?)w(.*)$/$1a$2,$1t$2/             or
		$seq =~ s/^(.*?)B(.*)$/$1T$2,$1G$2,$1C$2/       or  # B = T/G/C
		$seq =~ s/^(.*?)b(.*)$/$1t$2,$1g$2,$1c$2/       or
		$seq =~ s/^(.*?)D(.*)$/$1A$2,$1T$2,$1G$2/       or  # D = A/T/G
		$seq =~ s/^(.*?)d(.*)$/$1a$2,$1t$2,$1g$2/       or
		$seq =~ s/^(.*?)H(.*)$/$1A$2,$1T$2,$1C$2/       or  # H = A/T/C
		$seq =~ s/^(.*?)h(.*)$/$1a$2,$1t$2,$1c$2/       or
		$seq =~ s/^(.*?)V(.*)$/$1A$2,$1G$2,$1C$2/       or  # V = A/G/C
		$seq =~ s/^(.*?)v(.*)$/$1a$2,$1g$2,$1c$2/       or
		$seq =~ s/^(.*?)N(.*)$/$1A$2,$1T$2,$1G$2,$1C$2/ or  # N = A/T/G/C
		$seq =~ s/^(.*?)n(.*)$/$1a$2,$1t$2,$1g$2,$1c$2/
	){
		unshift @in, split(/,/, $seq) ;
	} else {
		push @out, $seq ;
	}
}
return @out ;
} ;
# ====================
sub escape_sedueq {  # 「&[]|-\()?:」をエスケープする
my $str = $_[0] // '' ;
$str =~ s/(?=[\&\[\]\|\-\\\(\)\?\:])/\\/g ;
$str = url_encode($str) ;
return $str ;
} ;
# ====================
sub show_hit_txt {  # ヒットしたエントリをタブ区切りテキストで出力
my $gene = $_[0] or return '' ;

#- ▼ 塩基配列、アミノ酸配列のhit position出力
my $position = $gene->{fields}->{hit_positions} // '' ;
my $pos_json = eval 'decode_json($position)' // () ;
my @ntpos ;
my @aapos ;
foreach (@$pos_json){
	$_->{index} eq 'nt' and push @ntpos, @{$_->{positions}} ;
	$_->{index} eq 'aa' and push @aapos, @{$_->{positions}} ;
}
{my %count ; @ntpos = grep(!$count{$_}++, @ntpos)}  # 重複を除去
{my %count ; @aapos = grep(!$count{$_}++, @aapos)}  # 重複を除去
@ntpos = map {$_ + 1} @ntpos ;  # 0-based startを1-based startに変換
@aapos = map {$_ + 1} @aapos ;  # 0-based startを1-based startに変換
@ntpos = sort {$a <=> $b} @ntpos ;
@aapos = sort {$a <=> $b} @aapos ;
#- ▲ 塩基配列、アミノ酸配列のhit position出力

return join "\t", (
	($gene->{fields}->{accession}  // ''),
	($gene->{fields}->{version}    // ''),
	($gene->{fields}->{gi}         // ''),
	($gene->{fields}->{length}     // ''),
	($gene->{fields}->{symbol}     // ''),
	($gene->{fields}->{synonym}    // ''),
	($gene->{fields}->{geneid}     // ''),
	($gene->{fields}->{division}   // ''),
	($gene->{fields}->{source}     // ''),
	($gene->{fields}->{definition} // ''),
	join (' ', @ntpos),
	join (' ', @aapos)
);
} ;
# ====================
sub show_hit_json {  # ヒットしたエントリをJSONで出力
my $gene = $_[0] or return '' ;

#- ▼ 塩基配列、アミノ酸配列のhit position出力
my $position = $gene->{fields}->{hit_positions} // '' ;
my $pos_json = eval 'decode_json($position)' // () ;
my @ntpos ;
my @aapos ;
foreach (@$pos_json){
	$_->{index} eq 'nt' and push @ntpos, @{$_->{positions}} ;
	$_->{index} eq 'aa' and push @aapos, @{$_->{positions}} ;
}
{my %count ; @ntpos = grep(!$count{$_}++, @ntpos)}  # 重複を除去
{my %count ; @aapos = grep(!$count{$_}++, @aapos)}  # 重複を除去
@ntpos = map {$_ + 1} @ntpos ;  # 0-based startを1-based startに変換
@aapos = map {$_ + 1} @aapos ;  # 0-based startを1-based startに変換
@ntpos = sort {$a <=> $b} @ntpos ;
@aapos = sort {$a <=> $b} @aapos ;
#- ▲ 塩基配列、アミノ酸配列のhit position出力

return [{
	accession   => ($gene->{fields}->{accession}  // ''),
	version     => ($gene->{fields}->{version}    // ''),
	gi          => ($gene->{fields}->{gi}         // ''),
	length      => ($gene->{fields}->{length}     // ''),
	division    => ($gene->{fields}->{division}   // ''),
	definition  => ($gene->{fields}->{definition} // ''),
	source      => ($gene->{fields}->{source}     // ''),
	symbol      => ($gene->{fields}->{symbol}     // ''),
	synonym     => ($gene->{fields}->{synonym}    // ''),
	geneid      => ($gene->{fields}->{geneid}     // ''),
	snippet     => ($gene->{snippets}->[0]        // ''),
	nt_position => \@ntpos,
	aa_position => \@aapos
}] ;
} ;
# ====================
sub show_hit_html {  # ヒットしたエントリをHTMLで出力
my $gene = $_[0] or return '' ;

my $version  = $gene->{fields}->{version}       // '' ;
my $length   = $gene->{fields}->{length}        // '' ;
my $def      = $gene->{fields}->{definition}    // '' ;
my $species  = $gene->{fields}->{source}        // '' ;
my $geneid   = $gene->{fields}->{geneid}        // '' ;
my $symbol   = $gene->{fields}->{symbol}        // '' ;
my $synonym  = $gene->{fields}->{synonym}       // '' ;
my $position = $gene->{fields}->{hit_positions} // '' ;
my $snippet  = $gene->{snippets}->[0]           // '' ;

# ハイライトする文字列のリスト
my @highlight = (@query_array, @expand_query_array) ;

# refid, def, snippetに検索語がマッチした場合にハイライト
my $version_html = emtext_regexp($version, \@highlight) ;
my $def_html     = emtext_regexp($def,     \@highlight) ;
my $snippet_html = emtext_regexp($snippet, \@highlight) ;

# synonymが存在する場合に表示。マッチした場合にハイライト
my $synonym_html = ($synonym) ?
	'Synonym: ' . emtext_regexp($synonym, \@highlight) . '<br>' :
	'' ;

#- ▼ 塩基配列、アミノ酸配列のhit position出力
my $pos_json = eval 'decode_json($position)' // () ;
my @ntpos ;
my @aapos ;
foreach (@$pos_json){
	$_->{index} eq 'nt' and push @ntpos, @{$_->{positions}} ;
	$_->{index} eq 'aa' and push @aapos, @{$_->{positions}} ;
}
{my %count ; @ntpos = grep(!$count{$_}++, @ntpos)}  # 重複を除去
{my %count ; @aapos = grep(!$count{$_}++, @aapos)}  # 重複を除去
@ntpos = map {$_ + 1} @ntpos ;  # 0-based startを1-based startに変換
@aapos = map {$_ + 1} @aapos ;  # 0-based startを1-based startに変換
@ntpos = sort {$a <=> $b} @ntpos and unshift @ntpos, "<span class=position>position</span>" ;
@aapos = sort {$a <=> $b} @aapos and unshift @aapos, "<span class=position>AA_position</span>" ;
my $pos_html = (@ntpos or @aapos) ?
	'<div class=b>' . join(' ', (@ntpos, @aapos)) . "</div>\n\t" :
	'' ;
#- ▲ 塩基配列、アミノ酸配列のhit position出力

# GBFFへのリンクにハイライト箇所を埋め込む
map {$_ = url_encode($_)} @highlight ;
map {$_ =~ s/\+/%20/g   } @highlight ;
my $highlight = join('+', @highlight) ;

# 外部データベースへのリンクを付加
my @extlink = map {$_ = "<a href='$_->{url}' class=a target='_blank'>$_->{name}</a>"}
                  external_link($gene) ;
my $extlink = join " -\n\t", @extlink ;

return
"<div class=gene><!-- ==================== -->
	<div class=t>
	<a target='_blank' href='$version.gbff?highlight=${highlight}#em'>
		$def_html</a>
	<small>($length bp)</small>
	</div>
	<div class=b>
	$snippet_html
	</div>
	$pos_html<div class=g>
	$synonym_html
	<cite>$version_html</cite> -
	<cite>$species</cite> -
	$extlink
	</div>
</div>" ;
} ;
# ====================
sub emtext_regexp {  # 検索語をハイライト：emtext_regexp($text, \@query_array)
my $text = $_[0] // '' ;
my @query_array = ($_[1] and ref $_[1] eq 'ARRAY') ? @{$_[1]} : return $text ;
#- ▼ マッチ開始／終了位置をマークする
my %flag  ;
my %depth ;
foreach (@query_array){
	my $q = $_ ;
	$q =~ s/^(refid|gi|spe|geneid|symbol|aa|ref|
	          seq|comp|both|iub|iubcomp|iubboth)://x ;  # タグを除去
	$q =~ s/([\\\[\]|()^?+*])/\\$1/g ;                  # 正規表現中の特殊文字をエスケープ
	$q =~ s/\ /\\s\+/g ;    # クエリ中のスペースをGBFF中の改行・連続スペースにもマッチさせる

	next if $flag{lc $q} ;  # 既出チェック
	$flag{lc $q} ++ ;

	while ($text =~ /($q)/gi){
		$depth{$-[0]} ++ ;  # マッチ開始位置
		$depth{$+[0]} -- ;  # マッチ終了位置
	}
}
#- ▲ マッチ開始／終了位置をマークする
#- ▼ 開始／終了タグを挿入
my $d = 0 ;
foreach (sort {$b<=>$a} keys(%depth)){
	my $class = ($d == -1) ? 'lv1' :
	            ($d == -2) ? 'lv2' :
	            ($d == -3) ? 'lv3' :
	            ($d <= -4) ? 'lv4' :
	                         ''    ;
	substr($text, $_, 0) =
		($d < 0 and not ($d + $depth{$_} == 0)) ? "</em><em class=$class>" :
		($d < 0 and     ($d + $depth{$_} == 0)) ? "<em class=$class>"      :
		                                          '</em>' ;  # $d == 0
	$d += $depth{$_} ;
}
#- ▲ 開始／終了タグを挿入
return $text ;
} ;
# ====================
sub external_link {  # 生物種に応じて外部データベースへのリンクを付加
my $gene    = $_[0] or return () ;

my $version = $gene->{fields}->{version} // '' ;
my $species = $gene->{fields}->{source}  // '' ;
my $geneid  = $gene->{fields}->{geneid}  // '' ;
my $symbol  = $gene->{fields}->{symbol}  // '' ;
my @exlink ;

(my $refid  = $version) =~ s/\.\d+$// ;

#- ▼ 全生物種：NCBIへのリンク
push @exlink, {
	name => 'NCBI',
	url  => "https://www.ncbi.nlm.nih.gov/nuccore/$version"
} ;
#- ▲ 全生物種：NCBIへのリンク

#- ▼ 生物種ごとに各種外部データベースにリンク
if ($species eq $spe_fullname{'hs'}){
	push @exlink, {
		name => 'UCSC',
		url  => 'https://genome.ucsc.edu/cgi-bin/hgTracks' .
		        "?org=Human&position=$refid"
	} if $refid ;
	push @exlink, {
		name => 'RefEx(expression)',
		url  => 'https://refex.dbcls.jp/genelist.php' .
		        "?lang=en&db=human&idkind=4&ids=$geneid"
	} if $geneid ;
} elsif ($species eq $spe_fullname{'mm'}){
	push @exlink, {
		name => 'UCSC',
		url  => 'https://genome.ucsc.edu/cgi-bin/hgTracks' .
		        "?org=Mouse&position=$refid"
	} if $refid ;
	push @exlink, {
		name => 'RefEx(expression)',
		url  => 'https://refex.dbcls.jp/genelist.php' .
		        "?lang=en&db=mouse&idkind=4&ids=$geneid"
	} if $geneid ;
} elsif ($species eq $spe_fullname{'rn'}){
	push @exlink, {
		name => 'UCSC',
		url  => 'https://genome.ucsc.edu/cgi-bin/hgTracks' .
		        "?org=Rat&position=$refid"
	} if $refid ;
	push @exlink, {
		name => 'RefEx(expression)',
		url  => 'https://refex.dbcls.jp/genelist.php' .
		        "?lang=en&db=rat&idkind=4&ids=$geneid"
	} if $geneid ;
} elsif ($species eq $spe_fullname{'gg'}){
	push @exlink, {
		name => 'UCSC',
		url  => 'https://genome.ucsc.edu/cgi-bin/hgTracks' .
		        "?org=Chicken&position=$refid"
	} if $refid ;
} elsif ($species eq $spe_fullname{'xt'}){
	push @exlink, {
		name => 'UCSC',
		url  => 'https://genome.ucsc.edu/cgi-bin/hgTracks' .
		        "?org=X.+tropicalis&position=$refid"
	} if $refid ;
	push @exlink, {
		name => 'Xenbase',
		url  => 'https://www.xenbase.org/gene/searchGene.do' .
		        "?method=search&searchIn=0&searchType=0&searchValue=$refid"
	} if $refid ;
} elsif ($species eq $spe_fullname{'dr'}){
	push @exlink, {
		name => 'UCSC',
		url  => 'https://genome.ucsc.edu/cgi-bin/hgTracks' .
		        "?org=Zebrafish&position=$refid"
	} if $refid ;
} elsif ($species eq $spe_fullname{'ci'}){
	push @exlink, {
		name => 'UCSC',
		url  => 'https://genome.ucsc.edu/cgi-bin/hgTracks' .
		        "?org=C.+intestinalis&position=$refid"
	} if $refid ;
} elsif ($species eq $spe_fullname{'dm'}){
	push @exlink, {
		name => 'UCSC',
		url  => 'https://genome.ucsc.edu/cgi-bin/hgTracks' .
		        "?org=D.+melanogaster&position=$refid"
	} if $refid ;
	push @exlink, {
		name => 'FlyBase',
		url  => 'https://flybase.org/cgi-bin/uniq.html' .
		        "?species=Dmel&caller=genejump&context=$symbol"
	} if $symbol ;
} elsif ($species eq $spe_fullname{'ce'}){
	push @exlink, {
		name => 'UCSC',
		url  => 'https://genome.ucsc.edu/cgi-bin/hgTracks' .
		        "?org=C.+elegans&position=$refid"
	} if $refid ;
	push @exlink, {
		name => 'WormBase',
		url  => "https://www.wormbase.org/species/c_elegans/gene/$symbol"
	} if $symbol ;
} elsif ($species eq $spe_fullname{'at'}){
	push @exlink, {
		name => 'TAIR',
		url  => 'https://www.arabidopsis.org/servlets/Search' .
		        "?type=gene&action=search&name_type=accession&name=$refid"
	} if $refid ;
} elsif ($species eq $spe_fullname{'os'}){
	# なし
} elsif ($species eq $spe_fullname{'sc'}){
	push @exlink, {
		name => 'UCSC',
		url  => 'https://genome.ucsc.edu/cgi-bin/hgTracks' .
		        "?org=S.+cerevisiae&position=$refid"
	} if $refid ;
	push @exlink, {
		name => 'SGD',
		url  => 'https//www.yeastgenome.org/cgi-bin/search/luceneQS.fpl' .
		        "?query=$refid"
	} if $refid ;
} elsif ($species eq $spe_fullname{'sp'}){
	push @exlink, {
		name => 'PomBase',
		url  => "https://www.pombase.org/search/ensembl/$refid"
	} if $refid ;
}
#- ▲ 生物種ごとに各種外部データベースにリンク

return @exlink ;
} ;
# ====================
sub escape_char {  # < > & ' " の5文字を実態参照に変換
my $str = $_[0] // '' ;
$str =~ s/\&/&amp;/g ;
$str =~ s/</&lt;/g ;
$str =~ s/>/&gt;/g ;
$str =~ s/\'/&apos;/g ;
$str =~ s/\"/&quot;/g ;
return $str ;
} ;
# ====================
sub printresult {  # $format (global) にあわせて結果を出力
($format eq 'txt' ) ? print_txt($_[0])     :
($format eq 'json') ? print_json($_[0])    :
($lang   eq 'ja'  ) ? print_html_ja($_[0]) :  # default format: html
                      print_html_en($_[0]) ;  # default lang  : en
exit ;
} ;
# ====================
sub print_txt {  # TXTを出力

#- ▼ メモ
# ・検索結果をタブ区切りテキストで出力
# ・引数が ERROR で始まる場合はエラーを出力
# ・引数がない場合 → ERROR : query is empty
#- ▲ メモ

my $txt = $_[0] // '' ;

#- ▼ 検索結果を出力：default
# 引数をそのまま出力するので何もしなくてよい
#- ▲ 検索結果を出力：default

#- ▼ 引数がない場合 → ERROR : query is empty
(not $txt) and $txt = 'ERROR : query is empty' ;
#- ▲ 引数がない場合 → ERROR : query is empty

#- ▼ エラーを出力：引数が ERROR で始まる場合
$txt =~ s/^(ERROR.*)$/### $1 ###/s ;
#- ▲ エラーを出力：引数が ERROR で始まる場合

#- ▼ TXT出力
print "Content-type: text/plain; charset=utf-8\n" ;
print "Content-Disposition: attachment; filename=ggrna_result.txt\n"
	if $download ;  # ファイルとしてダウンロードする場合
print "\n" ;
print "$txt\n" ;
#- ▲ TXT出力

return ;
} ;
# ====================
sub print_json {  # JSONを出力

#- ▼ メモ
# ・検索結果をJSONで出力
# ・引数が ERROR で始まる場合はエラーをJSONで出力
# ・引数がない場合 → ERROR : query is empty
#- ▲ メモ

my $json_txt = $_[0] // '' ;

#- ▼ 検索結果を出力：default
# 引数をそのまま出力するので何もしなくてよい
#- ▲ 検索結果を出力：default

#- ▼ 引数がない場合 → ERROR : query is empty
(not $json_txt) and $json_txt = 'ERROR : query is empty' ;
#- ▲ 引数がない場合 → ERROR : query is empty

#- ▼ エラーを出力：引数が ERROR で始まる場合
($json_txt =~ /^ERROR[:\s]*(.*)$/s) and
$json_txt = JSON::XS->new->canonical->utf8->encode(
	{error => $1}
) ;
#- ▲ エラーを出力：引数が ERROR で始まる場合

#- ▼ JSON出力
print "Content-type: application/json; charset=utf-8\n" ;
print "Content-Disposition: attachment; filename=ggrna_result.json\n"
	if $download ;  # ファイルとしてダウンロードする場合
print "\n" ;
print "$json_txt\n" ;
#- ▲ JSON出力

return ;
} ;
# ====================
sub print_html_ja {  # HTMLを出力 (日本語)

#- ▼ メモ
# ・検索結果ページをHTMLで出力
# ・引数が ERROR で始まる場合はエラーページを出力
# ・引数がない場合はトップページを出力
#- ▲ メモ

my $html = $_[0] // '' ;

#- ▼ 検索結果ページを出力：default
my $title  = 'GGRNA | Results' ;
my $robots = "<meta name=robots content=NONE>\n" ;  # トップページ以外はロボット回避
#- ▲ 検索結果ページを出力：default

#- ▼ エラーページを出力：引数が ERROR で始まる場合
$html =~ s{^(ERROR.*)$}{<p><font color=red>$1</font></p>}s and
$title  = 'GGRNA | Error' and
$robots = "<meta name=robots content=NONE>\n" ;  # トップページ以外はロボット回避
#- ▲ エラーページを出力：引数が ERROR で始まる場合

#- ▼ トップページ：引数がない場合
my $template_top = HTML::Template->new(filename => 'template/top_ja.tmpl') ;

unless ($html){
	$html   = $template_top->output ;
	$title  = '統合遺伝子検索GGRNA' ;
	$robots = '' ;
}
#- ▲ トップページ：引数がない場合

#- ▼ メンテナンス画面の作成
my $chatafile = 'template/maintenance_ja.txt' ;

my $message = '' ;
if (-f $chatafile and -r $chatafile){
	open FILE, $chatafile ;
	$message = join '', <FILE> ;
	close FILE ;
}

my $chata = ($message =~ /\A\s*\z/) ? '' :  # 空白文字のみの場合
<<"--EOS--" ;
<div><font color=red>
$message
</font></div>

<img src='togopic/chata_ja.png' alt='ニャーン' border=0>

<hr> <!-- __________________________________________________ -->
--EOS--
#- ▲ メンテナンス画面の作成

#- ▼ HTML出力
my $template_index = HTML::Template->new(filename => 'template/index_ja.tmpl') ;

$template_index->param(
	ROBOTS => $robots,
	TITLE  => $title,
	QUERY  => $query_string,
	CHATA  => $chata,
	HTML   => $html
) ;

print "Content-type: text/html; charset=utf-8\n\n" ;
print $template_index->output ;
#- ▲ HTML出力

return ;
} ;
# ====================
sub print_html_en {  # HTMLを出力 (English)

#- ▼ メモ
# ・検索結果ページをHTMLで出力
# ・引数が ERROR で始まる場合はエラーページを出力
# ・引数がない場合はトップページを出力
#- ▲ メモ

my $html = $_[0] // '' ;

#- ▼ 検索結果ページを出力：default
my $title  = 'GGRNA | Results' ;
my $robots = "<meta name=robots content=NONE>\n" ;  # トップページ以外はロボット回避
#- ▲ 検索結果ページを出力：default

#- ▼ エラーページを出力：引数が ERROR で始まる場合
$html =~ s{^(ERROR.*)$}{<p><font color=red>$1</font></p>}s and
$title  = 'GGRNA | Error' and
$robots = "<meta name=robots content=NONE>\n" ;  # トップページ以外はロボット回避
#- ▲ エラーページを出力：引数が ERROR で始まる場合

#- ▼ トップページ：引数がない場合
my $template_top = HTML::Template->new(filename => 'template/top_en.tmpl') ;

unless ($html){
	$html   = $template_top->output ;
	$title  = 'GGRNA | gene search' ;
	$robots = '' ;
}
#- ▲ トップページ：引数がない場合

#- ▼ メンテナンス画面の作成
my $chatafile = 'template/maintenance_en.txt' ;

my $message = '' ;
if (-f $chatafile and -r $chatafile){
	open FILE, $chatafile ;
	$message = join '', <FILE> ;
	close FILE ;
}

my $chata = ($message =~ /\A\s*\z/) ? '' :  # 空白文字のみの場合
<<"--EOS--" ;
<div><font color=red>
$message
</font></div>

<img src='togopic/chata_en.png' alt='nyaan' border=0>

<hr> <!-- __________________________________________________ -->
--EOS--
#- ▲ メンテナンス画面の作成

#- ▼ HTML出力
my $template_index = HTML::Template->new(filename => 'template/index_en.tmpl') ;

$template_index->param(
	ROBOTS => $robots,
	TITLE  => $title,
	QUERY  => $query_string,
	CHATA  => $chata,
	HTML   => $html
) ;

print "Content-type: text/html; charset=utf-8\n\n" ;
print $template_index->output ;
#- ▲ HTML出力

return ;
} ;
# ====================
