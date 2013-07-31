#!/usr/bin/perl

# GGRNA (ググルナ)： 遺伝子をGoogleのように検索するサービス
# http://GGRNA.dbcls.jp/
#
# Accession番号からGBFFを生成して出力する
#
# 必要なモジュール：
# HTML::Template
# ./Sedue.pm
#   LWP::Simple (Sedue.pm内で使用)
#   JSON::XS    (Sedue.pm内で使用)
#
# 2013-07-08 Yuki Naito (@meso_cacase) GGRNA.v2リリース

#- ▼ モジュール読み込みと変数の初期化
use warnings ;
use strict ;

eval 'use HTML::Template ; 1' or  # HTMLをテンプレート化
	print_html('ERROR : cannot load HTML::Template') ;

eval 'use Sedue ; 1' or           # Sedueに問い合わせを行うためのモジュール
	print_html('ERROR : cannot load Sedue') ;

my $refseq_version = 'RefSeq release 60 (Jul, 2013)' ;
my $ddbj_version   = 'DDBJ release 92.0 (Feb, 2013)' ;

my $timestamp = timestamp() ;     # CGIを実行した時刻
#- ▲ モジュール読み込みと変数の初期化

#- ▼ リクエストからパラメータを取得
my %query = get_query_parameters() ;  # HTTPリクエストからクエリを取得

my $accession = $query{'accession'} // '' ;  # Accession番号
my $highlight = $query{'highlight'} // '' ;  # ハイライトする検索ワード
my @highlight = split /\+/, $highlight ;
map {$_ = url_decode($_)} @highlight ;
#- ▲ リクエストからパラメータを取得

#- ▼ GBFFデータ取得および出力
# クエリがAccession番号のパターンにマッチするかチェック
$accession =~ /^\w+(\.\d+)?$/i or print_html('ERROR : Not found.') ;

# SSDサーバからGBFFを取得
my $hit = Sedue::sedue_get_gbff($accession) ;

my $gbf   = $hit->{gbf}   // '' ;
my $ntseq = $hit->{ntseq} // '' ;

# ヒットなしの場合はエラーメッセージを出力
($gbf and $ntseq) or print_html('ERROR : Not found.') ;

# ハイライト、アミノ酸配列スタイル指定
$gbf =~ s/
	(\A.*^\ *\/translation=\")(.*?\")\n?(.*\Z)
	/@{[emtext_regexp($1, \@highlight)]
	  }<\/pre>\n<pre class=aa>@{[emtext_regexp($2, \@highlight)]
	  }<\/pre>\n<pre>@{[emtext_regexp($3, \@highlight)]
	  }/xsmg or
$gbf = emtext_regexp($gbf, \@highlight) ;  # アミノ酸配列を含まないエントリ

# 最後の // を除く
$gbf =~ s{\n//\Z}{} ;

# 塩基配列のハイライト
$ntseq = emtext_regexp($ntseq, \@highlight) ;

# HTML生成
my $html =
"<div>
<pre>$gbf</pre>
<pre class=seq>$ntseq</pre>
<pre>//</pre>
</div>" ;

# 最初のハイライト箇所にアンカーを挿入
$html =~ s{(?=(.|\n\ {10})*<em)}{<a name=em></a>}m ;

# HTML出力
print_html($html, $accession) ;
#- ▲ GBFFデータ取得および出力

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
		print_html('ERROR : get_query_parameters() : read failed') ;
} elsif (defined $ENV{'QUERY_STRING'}){
	$buffer = $ENV{'QUERY_STRING'} ;
}
my %query ;
my @query = split /&/, $buffer ;
foreach (@query){
	my ($name, $value) = split /=/ ;
	if (defined $name and defined $value){
		# $name  = url_decode($name) ;
		# $value = url_decode($value) ;
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
sub print_html {  # HTMLを出力

my $html  = $_[0] // '' ;
my $title = $_[1] // '' ;

# 引数が空欄の場合はエラーメッセージを出力
$html ||= 'ERROR : Not found.' ;

# 引数がERRORで始まる場合はエラーメッセージを出力
$html   =~ s{^(ERROR.*)$}{<p><font color=red>$1</font></p>}s and
$title  = 'GGRNA | Error' ;

#- ▼ HTML出力
my $template_gbff = HTML::Template->new(filename => 'template/gbff.tmpl') ;

$template_gbff->param(
	TITLE      => $title     // 'GGRNA',
	TIMESTAMP  => $timestamp // '0000-00-00 00:00:00',
	REFSEQ_VER => $refseq_version,
	HTML       => $html
) ;

print "Content-type: text/html; charset=utf-8\n\n" ;
print $template_gbff->output ;
#- ▲ HTML出力

exit ;
} ;
# ====================
