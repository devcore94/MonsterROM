#!/usr/bin/env bash
# Repack only the native ARM32 additions, using UN1CA's existing image/sign tools.
set -euo pipefail
KIND="${1:?Expected runtime or i18n}"
case "$KIND" in
    runtime)
        SOURCE_SHA=0e1941d33200a01c12f45ff9ed6439ae60c1b3a8880c95f074f58544b1633793
        ARM32_SHA=a4bd1cbfcb34d206db1bb6482b33818c4aff5a3e2e8a5b80d011c04e53b88cf6
        CACHE_ROOT="$OUT_DIR/compat32-cache"
        ;;
    i18n)
        SOURCE_SHA=57823da4c0eac7009b1a486bb2a5b181f99a13c7a9ff4afcb2e510a1fb12d7f1
        ARM32_SHA=425a2bcfdd941f137c7ccb67ffb06241b5a84beadda489da69e9baf7c9309927
        CACHE_ROOT="$OUT_DIR/compat32-i18n-cache"
        ;;
    *) exit 1 ;;
esac
NAME="com.android.$KIND.apex"
SOURCE_ROOT="$FW_DIR/${SOURCE_FIRMWARE%%/*}_$(cut -d / -f 2 <<< "$SOURCE_FIRMWARE")"
SOURCE_APEX="$SOURCE_ROOT/system/system/apex/$NAME"
ARM32_APEX="$FW_DIR/SM-G990E_THL/system/system/apex/$NAME"
[ "$(sha256sum "$SOURCE_APEX" | cut -d ' ' -f 1)" = "$SOURCE_SHA" ]
[ "$(sha256sum "$ARM32_APEX" | cut -d ' ' -f 1)" = "$ARM32_SHA" ]
cmp -s "$SOURCE_APEX" "$WORK_DIR/system/system/apex/$NAME"

CERT=aosp
$ROM_IS_OFFICIAL && CERT=unica
TEMP="$(mktemp -d "$OUT_DIR/compat32-$KIND.XXXXXX")"
cleanup_compat32()
{
    local FAILED=false
    for POINT in output source arm32; do
        if mountpoint -q "$TEMP/$POINT"; then
            sudo umount "$TEMP/$POINT" || FAILED=true
        fi
    done
    if ! $FAILED; then
        # TEMP is an owned mktemp directory, never a caller-supplied tree.
        sudo rm -rf -- "$TEMP"
    fi
}
trap cleanup_compat32 EXIT

# The seal binds the actual firmware, recipe, tools, and BOTH signing keys.
# A certificate-only key would silently reuse output after private/AVB-key or
# firmware changes. No private key bytes are recorded, only their digests.
sha256sum "$SOURCE_APEX" "$ARM32_APEX" "$SOURCE_ROOT/.extracted" "$FW_DIR/SM-G990E_THL/.extracted" \
    "$SRC_DIR/unica/patches/vndk/customize.sh" "${BASH_SOURCE[0]}" \
    "$SRC_DIR/scripts/build_fs_image.sh" "$SRC_DIR/scripts/utils/build_utils.sh" \
    "$SRC_DIR/scripts/utils/common_utils.sh" \
    "$SRC_DIR/security/${CERT}_platform.x509.pem" "$SRC_DIR/security/${CERT}_platform.pk8" \
    "$SRC_DIR/security/avb/testkey_rsa4096.pem" \
    "$TOOLS_DIR/bin/apktool.jar" "$TOOLS_DIR/bin/signapk.jar" "$TOOLS_DIR/bin/mke2fs.conf" \
    "$(command -v apktool)" "$(command -v signapk)" "$(command -v avbtool)" \
    "$(command -v mkuserimg_mke2fs)" "$TOOLS_DIR/bin/mkuserimg_mke2fs.py" \
    "$(command -v mke2fs)" "$(command -v e2fsdroid)" "$(command -v java)" \
    "$(command -v python3)" "$(command -v perl)" "$(command -v getfattr)" \
    "$(command -v openssl)" "$(command -v jarsigner)" "$(command -v debugfs)" \
    "$(command -v unzip)" > "$TEMP/inputs.sha256"
KEY="$(sha256sum "$TEMP/inputs.sha256" | cut -d ' ' -f 1)"
CACHE="$CACHE_ROOT/$KEY"
mkdir -p "$CACHE_ROOT" "$TEMP/source" "$TEMP/arm32" "$TEMP/output"

unzip -p "$SOURCE_APEX" apex_payload.img > "$TEMP/source.img"
unzip -p "$ARM32_APEX" apex_payload.img > "$TEMP/arm32.img"
sudo mount -o ro "$TEMP/source.img" "$TEMP/source"
sudo mount -o ro "$TEMP/arm32.img" "$TEMP/arm32"

# Inventory exact source/addition bytes, symlinks, ownership, modes and labels.
# Runtime additions (including crash_dump32/linker) must be sealed too, not just
# the original ARM64 files. ICU's old data is added beside the untouched new data.
sudo perl - "$KIND" "$TEMP" <<'PERL'
use strict;
use warnings;
use Digest::SHA;
use File::Find;
use Fcntl ':mode';
use JSON::PP;
sub need { die "$_[1]\n" unless $_[0] }
sub sha { open my $f,'<:raw',$_[0] or die "$!: $_[0]\n"; return Digest::SHA->new(256)->addfile($f)->hexdigest }
sub save { open my $f,'>:raw',$_[0] or die "$!: $_[0]\n"; print $f $_[1]; close $f or die "$!: $_[0]\n" }
sub inventory {
    my($root)=@_; my %nodes;
    need(-d $root,"Missing APEX directory: $root");
    find({no_chdir=>1,wanted=>sub {
        my $p=$File::Find::name; my $n=substr($p,length($root)); $n =~ s{^/}{};
        need($n !~ /[\s\\]/,"Unsupported APEX path: $n"); $nodes{$n}=$p;
    }},$root);
    return \%nodes;
}
sub describe {
    my($p)=@_; my @s=lstat($p); need(@s,"Cannot stat APEX node: $p");
    open my $x,'-|','getfattr','-h','--absolute-names','-n','security.selinux','--only-values','--',$p or die "$!\n";
    local $/; my $label=<$x>//''; close $x or die "Missing APEX label: $p\n";
    $label =~ s/\0+$//; need($label =~ /^u:object_r:[^\s\0]+$/,"Invalid APEX label: $p");
    my $d={uid=>$s[4],gid=>$s[5],mode=>$s[2]&07777,label=>$label};
    if(S_ISREG($s[2])) { $d->{type}='file'; $d->{sha256}=sha($p) }
    elsif(S_ISLNK($s[2])) { $d->{type}='symlink'; $d->{target}=readlink($p) }
    elsif(S_ISDIR($s[2])) { $d->{type}='directory' }
    else { die "Unsupported APEX node: $p\n" }
    return $d;
}
my($kind,$temp)=@ARGV; my($source,$donor)=("$temp/source","$temp/arm32");
my $origins=inventory($source); my %original=map {$_=>describe($origins->{$_})} keys %$origins;
need(!exists($original{lib}) && !exists($original{'bin/linker'}),'Source already has ARM32 providers; review the graft');
my $libs=inventory("$donor/lib"); my %adds=map {('lib'.(length($_)?"/$_":''))=>$libs->{$_}} keys %$libs;
my $json=JSON::PP->new->canonical->pretty;
if($kind eq 'runtime') { $adds{"bin/$_"}="$donor/bin/$_" for qw(linker crash_dump32) }
else {
    need(-f "$donor/lib/libandroidicu.so",'Missing ARM32 ICU');
    my $icu=inventory("$donor/etc/icu");
    for my $n(keys %$icu) {
        my $name='etc/icu'.(length($n)?"/$n":'');
        if(exists $original{$name}) {
            need($json->encode(describe($icu->{$n})) eq $json->encode($original{$name}),"Conflicting ICU data/metadata: $name");
        } else { $adds{$name}=$icu->{$n} }
    }
}
my %added;
for my $n(keys %adds) {
    need(!exists($original{$n}),'Graft overwrites a One UI 9 provider');
    $added{$n}=describe($adds{$n});
    if($added{$n}{type} eq 'file') {
        open my $f,'<:raw',$adds{$n} or die "$!\n"; read($f,my $head,20);
        need(substr($head,0,4) ne "\x7fELF" || (substr($head,4,2) eq "\x01\x01" && substr($head,18,2) eq "\x28\x00"),"Not ARM32: $n");
    }
}
save("$temp/baseline.json",$json->encode({source=>\%original,added=>\%added}));
my %all=(%original,%added); my($fs,$contexts)=('','');
for my $n(sort keys %all) {
    my $d=$all{$n}; $fs.=sprintf("%s %d %d %o capabilities=0x0\n",$n,@$d{qw(uid gid mode)});
    # Do not escape '/' (libselabel extracts literal directory stems).
    my $escaped=$n; $escaped =~ s/([.\\+*?()\[\]{}^$|])/\\$1/g;
    $contexts.="/$escaped $d->{label}\n";
}
# build_fs_image.sh checks the literal lost+found before adding a default label.
$contexts.="# lost+found metadata retained above\n" if exists $all{'lost+found'};
save("$temp/fs_config",$fs); save("$temp/file_context",$contexts);
PERL
sudo chown "$(id -u):$(id -g)" "$TEMP/baseline.json" "$TEMP/fs_config" "$TEMP/file_context"

if [ -e "$CACHE" ]; then
    # A partial/old-format seal is an error, not permission to trust flags in a
    # receipt or quietly accept an archive from a different input cohort.
    cmp "$TEMP/inputs.sha256" "$CACHE/inputs.sha256"
    cmp "$TEMP/baseline.json" "$CACHE/baseline.json"
    (cd "$CACHE" && sha256sum -c SHA256SUMS)
    OUTPUT="$CACHE/$NAME"
else
    apktool d -j 4 -r -p "$TEMP/framework" -o "$TEMP/apex" "$SOURCE_APEX" > /dev/null
    sudo cp -a -T "$TEMP/source" "$TEMP/payload"
    sudo cp -a "$TEMP/arm32/lib" "$TEMP/payload/lib"
    if [ "$KIND" = runtime ]; then
        sudo cp -a "$TEMP/arm32/bin/linker" "$TEMP/arm32/bin/crash_dump32" "$TEMP/payload/bin/"
    else
        sudo cp -a --update=none "$TEMP/arm32/etc/icu/." "$TEMP/payload/etc/icu/"
    fi
    sudo chown -hR "$(id -u):$(id -g)" "$TEMP/payload"
    "$SRC_DIR/scripts/build_fs_image.sh" ext4 --no-avb --force -p system \
        -o "$TEMP/apex/unknown/apex_payload.img" "$TEMP/payload" \
        "$TEMP/file_context" "$TEMP/fs_config" > /dev/null
    # e2fsdroid inherits the APEX root's 1000:1000 for mke2fs's pre-created
    # lost+found, ignoring that one fs_config entry. Restore its reviewed 0:0
    # before AVB signing; the complete metadata comparison below checks this.
    debugfs -w -R 'set_inode_field /lost+found uid 0' "$TEMP/apex/unknown/apex_payload.img" > /dev/null 2>&1
    debugfs -w -R 'set_inode_field /lost+found gid 0' "$TEMP/apex/unknown/apex_payload.img" > /dev/null 2>&1
    SALT="$(sha256sum "$TEMP/apex/unknown/apex_manifest.pb" | cut -d ' ' -f 1)"
    avbtool add_hashtree_footer --do_not_generate_fec --algorithm SHA256_RSA4096 --hash_algorithm sha256 \
        --key "$SRC_DIR/security/avb/testkey_rsa4096.pem" --prop "apex.key:com.android.$KIND" --salt "$SALT" \
        --image "$TEMP/apex/unknown/apex_payload.img"
    avbtool extract_public_key --key "$SRC_DIR/security/avb/testkey_rsa4096.pem" \
        --output "$TEMP/apex/unknown/apex_pubkey"
    mkdir -p "$TEMP/apex/build/apk" "$TEMP/publish"
    cp -a "$TEMP/apex/original/META-INF" "$TEMP/apex/build/apk/META-INF"
    apktool b -j 4 -p "$TEMP/framework" "$TEMP/apex" > /dev/null
    OUTPUT="$TEMP/publish/$NAME"
    # Use the original launcher's JVM-option forwarding. Java 17+ accepts this
    # permission; newer hosts require it for Conscrypt's native library load.
    signapk -J-enable-native-access=ALL-UNNAMED -a 4096 --align-file-size "$SRC_DIR/security/${CERT}_platform.x509.pem" \
        "$SRC_DIR/security/${CERT}_platform.pk8" "$TEMP/apex/dist/$NAME" "$OUTPUT"
fi

# Verify the real existing signing chain, not a receipt's assertion of it.
LC_ALL=C jarsigner -J-Duser.language=en -J-Duser.country=US -verify "$OUTPUT" > "$TEMP/jarsigner.log"
grep -q '^jar verified\.$' "$TEMP/jarsigner.log"
unzip -p "$OUTPUT" META-INF/CERT.RSA | openssl pkcs7 -inform DER -print_certs -out "$TEMP/signer.pem"
[ "$(grep -c '^-----BEGIN CERTIFICATE-----$' "$TEMP/signer.pem")" = 1 ]
openssl x509 -in "$TEMP/signer.pem" -outform DER -out "$TEMP/signer.der"
openssl x509 -in "$SRC_DIR/security/${CERT}_platform.x509.pem" -outform DER -out "$TEMP/expected.der"
cmp "$TEMP/signer.der" "$TEMP/expected.der"
avbtool extract_public_key --key "$SRC_DIR/security/avb/testkey_rsa4096.pem" --output "$TEMP/expected.pubkey"
unzip -p "$OUTPUT" apex_pubkey > "$TEMP/output.pubkey"
cmp "$TEMP/output.pubkey" "$TEMP/expected.pubkey"
unzip -p "$OUTPUT" apex_payload.img > "$TEMP/output.img"
avbtool verify_image --image "$TEMP/output.img" --key "$SRC_DIR/security/avb/testkey_rsa4096.pem"
sudo mount -o ro "$TEMP/output.img" "$TEMP/output"
sudo perl - "$KIND" "$TEMP" "$OUTPUT" "$SOURCE_APEX" "$ARM32_APEX" <<'PERL'
use strict;
use warnings;
use Digest::SHA;
use File::Find;
use Fcntl ':mode';
use JSON::PP;
use MIME::Base64 qw(encode_base64);
sub need { die "$_[1]\n" unless $_[0] }
sub raw { open my $f,'<:raw',$_[0] or die "$!: $_[0]\n"; local $/; return <$f>//'' }
sub sha { open my $f,'<:raw',$_[0] or die "$!: $_[0]\n"; return Digest::SHA->new(256)->addfile($f)->hexdigest }
my($kind,$temp,$archive,$source,$donor)=@ARGV;
my $baseline=decode_json(raw("$temp/baseline.json")); my %expected=(%{$baseline->{source}},%{$baseline->{added}}); my %actual;
my $root="$temp/output";
find({no_chdir=>1,wanted=>sub {
    my $p=$File::Find::name; my $n=substr($p,length($root)); $n =~ s{^/}{}; $actual{$n}=$p;
}},$root);
need(join("\0",sort keys %actual) eq join("\0",sort keys %expected),'APEX node inventory changed');
for my $n(sort keys %actual) {
    my $p=$actual{$n}; my $d=$expected{$n}; my @s=lstat($p); need(@s,"Cannot stat APEX node: $n");
    open my $x,'-|','getfattr','-h','--absolute-names','-n','security.selinux','--only-values','--',$p or die "$!\n";
    my $label=do {local $/; <$x>//''}; close $x or die "Missing APEX label: $n\n"; $label =~ s/\0+$//;
    need($s[4]==$d->{uid} && $s[5]==$d->{gid} && ($s[2]&07777)==$d->{mode} && $label eq $d->{label},"APEX metadata changed: $n");
    my $valid=($d->{type} eq 'directory' && S_ISDIR($s[2])) ||
        ($d->{type} eq 'symlink' && S_ISLNK($s[2]) && readlink($p) eq $d->{target}) ||
        ($d->{type} eq 'file' && S_ISREG($s[2]) && sha($p) eq $d->{sha256});
    need($valid,"APEX provider changed: $n");
}
sub members {
    my($path)=@_; my(%hash,%text);
    # Read the central-directory inventory through the existing ZIP tool. APEX
    # signapk alignment padding is not an IO::Uncompress stream boundary.
    open my $list,'-|','unzip','-Z1',$path or die "$!\n";
    my @names=<$list>; close $list or die "Cannot inventory APEX: $path\n";
    chomp @names;
    for my $n(@names) {
        need($n =~ m{\A[A-Za-z0-9_./+\-]+\z},"Unsupported APEX archive path: $n");
        need(!exists $hash{$n},'Duplicate APEX archive entries');
        open my $entry,'-|','unzip','-p',$path,$n or die "$!\n";
        my $digest=Digest::SHA->new(256); my $body=''; my $count;
        while(($count=read($entry,my $buffer,65536))>0) { $digest->add($buffer); $body.=$buffer if $n eq 'META-INF/MANIFEST.MF' }
        need(defined($count),"Cannot read APEX member: $n"); close $entry or die "Cannot extract APEX member: $n\n";
        $hash{$n}=encode_base64($digest->digest,''); $text{$n}=$body if $n eq 'META-INF/MANIFEST.MF';
    }
    return(\%hash,\%text);
}
my($hash,$text)=members($archive); my($src)=members($source);
# jarsigner alone tolerates unsigned additions. Check every non-META-INF entry.
need(exists $text->{'META-INF/MANIFEST.MF'},'Missing signed APEX manifest');
my $manifest=$text->{'META-INF/MANIFEST.MF'}; $manifest =~ s/\r\n //g; my @blocks=split /\r\n\r\n/,$manifest; shift @blocks;
my %signed;
for my $block(@blocks) {
    my %fields=map {split /: /,$_,2} grep {/: /} split /\r\n/,$block;
    if(exists $fields{Name}) { need(!exists $signed{$fields{Name}},'Duplicate signed APEX manifest entry'); $signed{$fields{Name}}=\%fields }
}
for my $n(keys %$hash) {
    next if $n =~ m{/$|^META-INF/};
    need(exists($signed{$n}) && ($signed{$n}{'SHA-256-Digest'}//'') eq $hash->{$n},"Unsigned/changed APEX archive member: $n");
}
for my $n(qw(AndroidManifest.xml apex_manifest.pb)) {
    need(exists($hash->{$n}) && exists($src->{$n}) && $hash->{$n} eq $src->{$n},"Original APEX manifest changed: $n");
}
my $receipt={schema=>2,kind=>$kind,inputs_sha256=>sha("$temp/inputs.sha256"),
    source_apex_sha256=>sha($source),arm32_apex_sha256=>sha($donor),apex_sha256=>sha($archive),
    signer_certificate_sha256=>sha("$temp/signer.der"),payload_manifest_sha256=>sha("$temp/baseline.json"),
    original_files_verified=>scalar(grep {$_->{type} eq 'file'} values %{$baseline->{source}}),
    added_files=>{map {$_=>$baseline->{added}{$_}{sha256}} grep {$baseline->{added}{$_}{type} eq 'file'} keys %{$baseline->{added}}},
    scope=>'native ARM32 only; no ARM32 app ABI or ART',hardware_execution_verified=>JSON::PP::false};
open my $f,'>:raw',"$temp/receipt.json" or die "$!\n"; print $f JSON::PP->new->canonical->pretty->encode($receipt); close $f or die "$!\n";
PERL
sudo chown "$(id -u):$(id -g)" "$TEMP/receipt.json"
if [ -e "$CACHE" ]; then
    cmp "$TEMP/receipt.json" "$CACHE/receipt.json"
else
    cp "$TEMP/inputs.sha256" "$TEMP/baseline.json" "$TEMP/receipt.json" "$TEMP/publish/"
    (cd "$TEMP/publish" && sha256sum "$NAME" inputs.sha256 baseline.json receipt.json > SHA256SUMS)
    mv -T "$TEMP/publish" "$CACHE"
fi
cp "$CACHE/$NAME" "$WORK_DIR/system/system/apex/$NAME"
cp "$CACHE/receipt.json" "$WORK_DIR/.compat32-$KIND.json"
echo "Verified signed $KIND APEX: all original providers and native ARM32 additions sealed"
