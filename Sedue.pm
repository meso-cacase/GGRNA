package Sedue ;

# Sedueに問い合わせを行うためのモジュール
#
# 必要なモジュール：
# LWP::Simple
# JSON::XS
#
# 2013-07-30 Yuki Naito (@meso_cacase)

use warnings ;
use strict ;
use LWP::Simple ;  # SSD検索サーバとの接続に使用
use JSON::XS ;     # SSD検索サーバとの接続に使用

# ====================
sub arrayprobe2seq {  # マイクロアレイのprobe IDを塩基配列に変換
my $probeid  = $_[0] or return () ;
my $q        = lc($probeid) ;
my $host     = '172.18.8.70' ;  # ssd.dbcls.jp (SSD検索サーバ)
my $port     = '7700' ;
my $instance = 'arrayprsub' ;
my $limit    = 50 ;
my $uri      = "http://$host:$port/v1/$instance/query?" .
               "q=(probeid_norm:exact:$q)?to=$limit?get=targetseq&format=json" ;
my $json     = get($uri) or return () ;
my $hit      = decode_json($json) // () ;
my @probeseq ;
if ($hit->{hit_num}){  # ヒットする場合のみ変換を実行
	foreach (@{$hit->{docs}}){
		my $targetseq = $_->{fields}->{targetseq} ;
		$targetseq and push @probeseq, "seq:$targetseq" ;
	}
	return @probeseq ;
} else {
	return ($probeid) ;  # 変換できない場合はprobe IDのまま返す
}
} ;
# ====================
sub sedue_hit_num {  # sedue検索を行いヒット件数を返す
my $q        = $_[0] or return () ;
my $host     = '172.18.8.70' ;  # ssd.dbcls.jp (SSD検索サーバ)
my $port     = '7700' ;
my $instance = 'refsub' ;
my $limit    = 0 ;
my $uri      = "http://$host:$port/v1/$instance/query?" .
               "q=$q?to=$limit&format=json" ;
my $json     = get($uri) or return () ;
my $hit      = decode_json($json) // () ;
my $exact    = $hit->{hit_exact}  // '' ;
my $hit_num  = $hit->{hit_num}    // '' ;
$hit_num =~ s/^(\d{2})(\d*)/'~' . $1 . 0 x length($2)/e
	unless $exact ;  # 予測値の場合先頭"~"＋有効2桁
return { hit_num => $hit_num, uri => $uri } ;
} ;
# ====================
sub sedue_q {  # sedue検索を行う
my $q        = $_[0] or return () ;
my $host     = '172.18.8.70' ;  # ssd.dbcls.jp (SSD検索サーバ)
my $port     = '7700' ;
my $instance = 'refsub' ;
my $offset   = $_[1] // 0 ;                                                              #ADD tyamamot
my $limit    = $_[2] // $ENV{'MAX_HIT'} // 50 ;                                          #CHANGE tyamamot
$limit += $offset - 1 ;                                                                  #ADD tyamamot
my $uri      = "http://$host:$port/v1/$instance/query?" .
               "q=$q?to=$limit?from=$offset?snippet=full_search?drilldown=source?get=" . #CHANGE tyamamot
               join(',', qw/
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
               /) .
               '&format=json' ;
my $json     = get($uri) or return () ;
my $result   = decode_json($json) // () ;
$result->{uri} = $uri ;
return $result ;
} ;
# ====================
sub sedue_get_gbff {  # sedue検索を行う
my $version  = $_[0] or return () ;
my $host     = '172.18.8.70' ;  # ssd.dbcls.jp (SSD検索サーバ)
my $port     = '7700' ;
my $instance = 'refsub' ;
my $limit    = 0 ;
my $uri      = "http://$host:$port/v1/$instance/query?" .
               "q=(version:exact:$version)?to=$limit?get=gbf,reference,ntseq&format=json" ;
my $json     = get($uri) or return () ;
my $hit      = decode_json($json) // () ;

$hit->{hit_num} == 1 and $hit->{hit_exact} == 1 or return () ;

my $gbf   = $hit->{docs}->[0]->{fields}->{gbf}       // '' ;
my $ref   = $hit->{docs}->[0]->{fields}->{reference} // '' ;
my $ntseq = $hit->{docs}->[0]->{fields}->{ntseq}     // '' ;

$gbf =~ tr/\t/\n/ ;  # タブを改行に置換
$ref =~ tr/\t/\n/ ;  # タブを改行に置換
$gbf =~ s/\nREFERENCE\n/\n$ref/ ;  # 文献部分をマージ

return { gbf => $gbf, ntseq => $ntseq } ;
} ;
# ====================

return 1 ;
