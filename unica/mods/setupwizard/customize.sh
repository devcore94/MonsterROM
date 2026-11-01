#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
SETUP_RESOURCES()
{
    "${BASH_SOURCE[0]%/*}/../../../scripts/run_xml_perl.sh" - "$@" <<'PERL'
use strict;
use warnings;
use File::Find;
use File::Path qw(make_path);
use File::Basename qw(dirname basename);
use File::Temp qw(tempfile tempdir);
use XML::Parser;
sub need($$) { die "UN1CA: $_[1]\n" unless $_[0] }
sub raw { open my $f,'<:raw',$_[0] or die "$_[0]: $!\n"; local $/; return <$f>//'' }
sub put {
    my($path,$data)=@_; return if -f $path && raw($path) eq $data;
    make_path(dirname($path)); my($f,$name)=tempfile('.unica-native-XXXXXX',DIR=>dirname($path),UNLINK=>0);
    binmode $f; print $f $data or die "write $path: $!"; close $f or die "close $path: $!";
    chmod((-e $path ? (stat($path))[2]&0777 : 0644),$name) or die "chmod $name: $!";
    rename($name,$path) or die "rename $path: $!";
}
sub walk { my($root)=@_; my @paths; find({no_chdir=>1,wanted=>sub {push @paths,$File::Find::name if -f $_||-l $_}},$root) if -d $root; return sort @paths }
sub rel { my($path,$root)=@_; $path =~ s/^\Q$root\E\/// or die "Outside $root: $path"; return $path }
sub tag_end {
    my($data,$start)=@_; my $quote=''; for(my $i=$start;$i<length($data);$i++) {my $c=substr($data,$i,1);
        if(length $quote) {$quote='' if $c eq $quote} elsif($c eq chr(34)||$c eq chr(39)) {$quote=$c} elsif($c eq '>') {return $i+1} }
    die "Unterminated XML tag at byte $start of ".length($data).": ".substr($data,$start,80);
}
sub xml {
    my($data,$namespaces)=@_; my($root,@stack);
    if($namespaces) {XML::Parser->new(Namespaces=>1,Handlers=>{Doctype=>sub {die 'DOCTYPE is not allowed'},ExternEnt=>sub {die 'External entities are not allowed'}})->parse($data)}
    XML::Parser->new(Handlers=>{
        Doctype=>sub {die 'DOCTYPE is not allowed'},ExternEnt=>sub {die 'External entities are not allowed'},
        Start=>sub {my($p,$tag,%attrs)=@_; my $n={tag=>$tag,attrs=>\%attrs,start=>$p->current_byte,open=>tag_end($data,$p->current_byte),children=>[],text=>''};
            if(@stack) {push @{$stack[-1]{children}},$n} else {$root=$n} push @stack,$n},
        End=>sub {my($p)=@_; my $n=pop @stack; my $empty=substr($data,$n->{open}-2,2) eq '/>';
            $n->{close}=$empty?$n->{open}:$p->current_byte; $n->{end}=$empty?$n->{open}:tag_end($data,$p->current_byte)},
        Char=>sub {my($p,$text)=@_; $stack[-1]{text}.=$text if @stack},
    })->parse($data); need($root,'Missing XML root'); return {data=>$data,root=>$root};
}
sub node_raw { my($doc,$node)=@_; return substr($doc->{data},$node->{start},$node->{end}-$node->{start}) }
sub edit_xml { my($doc,$edits)=@_; my $data=$doc->{data}; for my $e(sort {$b->[0]<=>$a->[0]} @$edits) {substr($data,$e->[0],$e->[1]-$e->[0])=$e->[2]} xml($data,0); return $data }
sub append_xml {
    my($doc,$parent,$content)=@_; my $tag=$parent->{tag}; utf8::encode($tag) if utf8::is_utf8($tag);
    return edit_xml($doc,[[substr($doc->{data},$parent->{open}-2,2) eq '/>' ?
        ($parent->{open}-2,$parent->{open},">\n$content\n</$tag>") : ($parent->{close},$parent->{close},"$content\n")]]);
}
my($decoded,$overlay)=@ARGV; my $res="$decoded/res";
need(-f "$res/values/arrays.xml","Missing decoded Setup Wizard res/values/arrays.xml");
need(-f "$overlay/$_","Missing required Setup Wizard overlay: $_") for ("res/values/strings.xml","res/drawable-xxhdpi/suw_ic_unica.webp");
my %writes;
sub document {my($p)=@_; my $d=xml(exists($writes{$p})?$writes{$p}:raw($p),0); need($d->{root}{tag} eq "resources","Expected resources root: $p"); return $d}
for my $path(grep {m{/values[^/]*/arrays\.xml$}} walk($res)) {
    my $doc=document($path); my @edits;
    for my $array(@{$doc->{root}{children}}) {next unless $array->{tag} eq "string-array" && ($array->{attrs}{name}//"") =~ /^sequence_list/;
        for my $item(@{$array->{children}}) {my $value=$item->{text}; $value =~ s/^\s+|\s+$//g;
            if($item->{tag} eq "item" && ($value =~ /^\@string\/sequenceitem_omcagent_setup(?:_for_fota)?$/ || $value =~ /^omc_agent_setup(?:_for_fota)?(?:;|$)/)) {push @edits,[$item->{start},$item->{end},""]}}
    } $writes{$path}=edit_xml($doc,\@edits) if @edits;
}
for my $source(walk($overlay)) {
    my $relative=rel($source,$overlay); need($relative =~ m{^res/([^/]+)/([^/]+)$},"Unsupported Setup Wizard overlay: $relative"); my($q,$name)=($1,$2); my $target="$decoded/$relative";
    if($q =~ /^drawable/ && $name =~ /\.webp$/) {$writes{$target}=raw($source); next}
    need($q =~ /^values/ && $name eq "strings.xml","Unsupported Setup Wizard resource: $relative");
    my $payload=xml(raw($source),0); my $root=$payload->{root};
    need($root->{tag} eq "resources" && !keys(%{$root->{attrs}}) && @{$root->{children}}==1,"Expected isolated disclaimer resource");
    my $string=$root->{children}[0]; need($string->{tag} eq "string" && ($string->{attrs}{name}//"") eq "disclaimer_unica_description","Unexpected owned disclaimer resource");
    my $raw=node_raw($payload,$string); my @matches;
    for my $path(grep {/\.xml$/} walk("$res/$q")) {my $doc=document($path); for my $node(@{$doc->{root}{children}}) {
        push @matches,[$path,$doc,$node] if $node->{tag} eq "string" && ($node->{attrs}{name}//"") eq "disclaimer_unica_description"}}
    if(@matches) {my(%changes,%docs); for my $i(0..$#matches) {my($path,$doc,$node)=@{$matches[$i]}; $docs{$path}=$doc; push @{$changes{$path}},[$node->{start},$node->{end},$i==0?$raw:""]}
        $writes{$_}=edit_xml($docs{$_},$changes{$_}) for keys %changes;
    } elsif(-f $target || exists $writes{$target}) {my $doc=document($target); $writes{$target}=append_xml($doc,$doc->{root},"    $raw")}
    else {$writes{$target}=$payload->{data}}
}
for my $path(keys %writes) {xml($writes{$path},1) if $path =~ /\.xml$/}
put($_,$writes{$_}) for sort keys %writes;
PERL
}
"${BASH_SOURCE[0]%/*}/../../../scripts/run_xml_perl.sh" --check || return 1
DECODE_APK "system" "system/priv-app/SecSetupWizard_Global/SecSetupWizard_Global.apk"
LOG "- Enabling navigation bar type settings step"
SMALI_PATCH "system" "system/priv-app/SecSetupWizard_Global/SecSetupWizard_Global.apk" \
    "smali/e7/f.smali" "replace" \
    "d(Landroid/content/Context;Z)Ljava/util/ArrayList;" \
    "navigationbar_setting" "this_string_does_not_exist" > /dev/null
SMALI_PATCH "system" "system/priv-app/SecSetupWizard_Global/SecSetupWizard_Global.apk" \
    "smali/com/sec/android/app/SecSetupWizard/SecSetupWizardActivity.smali" "replace" \
    'e(Ljava/lang/String;)Z' "navigationbar_setting" "this_string_does_not_exist" > /dev/null
LOG "- Disabling Recommended apps step"
SETUP_RESOURCES "$APKTOOL_DIR/system/priv-app/SecSetupWizard_Global/SecSetupWizard_Global.apk" \
    "$MODPATH/SecSetupWizard_Global.apk" || return 1
