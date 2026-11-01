SETTINGS_INJECT()
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
my($decoded,$overlay)=@ARGV; need(-d $decoded && -f "$decoded/AndroidManifest.xml","Missing decoded Settings manifest");
my @sources=walk($overlay); need(scalar(@sources),"Missing/empty Settings payload overlay"); my(%writes,%resources);
sub document {my($p)=@_; return xml(exists $writes{$p}?$writes{$p}:raw($p),0)}
sub resource_key {my($n)=@_; my $kind=$n->{tag} eq "item"?$n->{attrs}{type}:$n->{tag}; my $name=$n->{attrs}{name}; need(defined($kind) && defined($name) && length($name) && $kind ne "public","Expected named non-public payload resource"); return "$kind\0$name"}
for my $source(@sources) {
    my $relative=rel($source,$overlay); my $target="$decoded/$relative"; my $data=raw($source);
    if($source !~ /\.xml$/) {$writes{$target}=$data; next}
    if($relative =~ m{^res/(values(?:-[^/]+)?)/[^/]+$}) {my $q=$1; my $payload=xml($data,0); need($payload->{root}{tag} eq "resources","Expected resources root: $relative");
        for my $n(@{$payload->{root}{children}}) {my $key=resource_key($n); need(!exists $resources{$q}{$key},"Duplicate payload resource $relative"); $resources{$q}{$key}=[$target,node_raw($payload,$n)]} next}
    if($data =~ /^\s*</) {xml($data,0); $writes{$target}=$data; next}
    my($directive,$content)=split /\n/,$data,2;
    need(defined($content) && -f $target && (($relative eq "AndroidManifest.xml" && $directive eq "/application>/i") ||
        ($relative eq "res/xml/sec_top_level_settings.xml" && ($directive eq "/TopLevelAdvancedFeatures/a" || $directive eq "/sec_ic_settings_user_manual/i"))),"Unsupported/missing Settings injection target: $relative");
    my $payload=xml("<payload>$content</payload>",0); my $doc=document($target); my $manifest=$relative eq "AndroidManifest.xml";
    my $parent=$manifest?(grep {$_->{tag} eq "application"} @{$doc->{root}{children}})[0]:$doc->{root}; need($parent,"Missing manifest application");
    my $attr=$manifest?"android:name":"android:key"; my(%owned,@edits,@pending);
    for my $node(@{$payload->{root}{children}}) {my $identity=$node->{attrs}{$attr}; need(defined($identity) && length($identity) && !$owned{$identity}++,"Missing/duplicate injected identity: $relative");
        my @matches=grep {($_->{attrs}{$attr}//"") eq $identity} @{$parent->{children}}; my $raw=node_raw($payload,$node);
        if(@matches) {for my $i(0..$#matches) {push @edits,[$matches[$i]{start},$matches[$i]{end},$i==0?$raw:""]}} else {push @pending,$raw}}
    $writes{$target}=edit_xml($doc,\@edits);
    if(@pending) {$doc=document($target);
        if($manifest) {$parent=(grep {$_->{tag} eq "application"} @{$doc->{root}{children}})[0]; $writes{$target}=append_xml($doc,$parent,join("\n",@pending))}
        else {my $after=$directive =~ m{/a$}; my $marker=$after?"TopLevelAdvancedFeatures":"sec_ic_settings_user_manual";
            my @matches=grep {my $n=$_; scalar grep {index($_,$marker)>=0} values %{$n->{attrs}}} @{$doc->{root}{children}};
            need(@matches==1,"Expected one Settings anchor $marker, got ".scalar(@matches)); my $off=$after?$matches[0]{end}:$matches[0]{start};
            $writes{$target}=edit_xml($doc,[[$off,$off,"\n".join("\n",@pending)."\n"]])}
    }
}
for my $q(sort keys %resources) {
    my %docs=map {$_=>document($_)} grep {/\.xml$/} walk("$decoded/res/$q"); my %matches;
    for my $path(sort keys %docs) {my $doc=$docs{$path}; need($doc->{root}{tag} eq "resources","Expected resources root: $path");
        for my $node(@{$doc->{root}{children}}) {next unless defined $node->{attrs}{name}; my $kind=$node->{tag} eq "item"?$node->{attrs}{type}:$node->{tag}; push @{$matches{"$kind\0$node->{attrs}{name}"}},[$path,$node]}}
    my(%edits,%adds);
    for my $key(sort keys %{$resources{$q}}) {my($target,$raw)=@{$resources{$q}{$key}}; my @found=@{$matches{$key}//[]};
        if(@found) {for my $i(0..$#found) {my($path,$node)=@{$found[$i]}; push @{$edits{$path}},[$node->{start},$node->{end},$i==0?$raw:""]}} else {push @{$adds{$target}},$raw}}
    for my $path(keys %edits) {$writes{$path}=edit_xml($docs{$path},$edits{$path})}
    for my $path(keys %adds) {my $doc=exists($writes{$path}) || -f $path?document($path):xml("<resources/>",0); $writes{$path}=append_xml($doc,$doc->{root},join("\n",@{$adds{$path}}))}
}
for my $path(keys %writes) {xml($writes{$path},1) if $path =~ /\.xml$/}
put($_,$writes{$_}) for sort keys %writes;
PERL
}
if [[ "${BASH_SOURCE[0]}" == "$0" && "${1:-}" == "--inject" ]]; then
    shift; SETTINGS_INJECT "$@"; exit $?
fi

# Refuse a missing/corrupt host parser before any Settings mutations.
"${BASH_SOURCE[0]%/*}/../../../scripts/run_xml_perl.sh" --check || return 1

# Show battery regulatory info in Settings
# Requires SEM_BATTERY_PROPERTY_IC_AUTHENTICATION_RESULT support
if [ "$(GET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_BATTERY_SUPPORT_BSOH_SETTINGS")" ]; then
    SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_BATTERY_SUPPORT_BSOH_SETTINGS" --delete
fi
SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_SETTINGS_ENABLE_EU_BATTERY_REGULATORY" "TRUE"

SMALI_PATCH "system" "system/framework/framework.jar" \
    "smali/android/app/Instrumentation.smali" "replace" \
    'newApplication(Ljava/lang/Class;Landroid/content/Context;)Landroid/app/Application;' \
    'invoke-virtual {p0, p1}, Landroid/app/Application;->attach(Landroid/content/Context;)V' \
    '    invoke-virtual {p0, p1}, Landroid/app/Application;->attach(Landroid/content/Context;)V\n\n    invoke-static {p1}, Lio/mesalabs/unica/SamsungPropsHooks;->init(Landroid/content/Context;)V' \
    > /dev/null
SMALI_PATCH "system" "system/framework/framework.jar" \
    "smali/android/app/Instrumentation.smali" "replace" \
    'newApplication(Ljava/lang/ClassLoader;Ljava/lang/String;Landroid/content/Context;)Landroid/app/Application;' \
    'invoke-virtual {p0, p3}, Landroid/app/Application;->attach(Landroid/content/Context;)V' \
    '    invoke-virtual {p0, p3}, Landroid/app/Application;->attach(Landroid/content/Context;)V\n\n    invoke-static {p3}, Lio/mesalabs/unica/SamsungPropsHooks;->init(Landroid/content/Context;)V' \
    > /dev/null

DECODE_APK "system" "system/priv-app/SecSettings/SecSettings.apk"

# Disable stock OTA references
if [ ! -f "$WORK_DIR/system/system/priv-app/ChoiDujour/ChoiDujour.apk" ]; then
    APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
        "$MODPATH/ota/SecSettings.apk/0001-Hide-unsupported-stock-OTA.patch"
fi

LOG_STEP_IN "- Adding UN1CA Settings"

# Payload text is never embedded in shell/sed commands. The local injector
# validates literal XML and handles the historical first-line directives.
SETTINGS_INJECT "$APKTOOL_DIR/system/priv-app/SecSettings/SecSettings.apk" "$MODPATH/SecSettings.apk" || return 1

# Keep the Android 17 search registry and native Settings-owned switch layout.
for SETTINGS_ARCHIVE in SecSettings SecSettingsIntelligence; do
    for SETTINGS_PATCH in "$MODPATH/patches/$SETTINGS_ARCHIVE.apk/"*.patch; do
        APPLY_PATCH "system" "system/priv-app/$SETTINGS_ARCHIVE/$SETTINGS_ARCHIVE.apk" "$SETTINGS_PATCH"
    done
done

# Show Vulkan renderer toggle if required
if [[ "$(GET_PROP "ro.hwui.use_vulkan")" != "true" ]]; then
    SET_PROP "system" "persist.sys.unica.vulkan" "false"
fi

# Apply these before the safety overlay, preserving the existing build order.
# The module runner will discover smali/ automatically after customize.sh, so
# these explicitly ordered patches remain under patches/ instead.
for SETTINGS_ARCHIVE in "system/framework/framework.jar" "system/framework/services.jar" \
        "system/priv-app/MultiSoundSetting/MultiSoundSetting.apk"; do
    APPLY_SMALI_PATCHES "$MODPATH/patches/smali" "$SETTINGS_ARCHIVE"
done

(
    MODPATH="$MODPATH/safety_center"
    source "$MODPATH/customize.sh"
) || return 1

unset SETTINGS_ARCHIVE SETTINGS_PATCH

LOG_STEP_OUT
