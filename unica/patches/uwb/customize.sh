APPEND_UWB_BOOTCLASSPATH()
{
    perl - "$@" <<'PERL'
use strict;
use warnings;
use JSON::PP;
use File::Path qw(make_path);
use File::Basename qw(dirname basename);
use File::Temp qw(tempfile tempdir);
sub need($$) { die "UN1CA: $_[1]\n" unless $_[0] }
sub raw { open my $f,'<:raw',$_[0] or die "$_[0]: $!\n"; local $/; return <$f>//'' }
sub same { JSON::PP->new->canonical->encode($_[0]) eq JSON::PP->new->canonical->encode($_[1]) }
sub put {
    my($path,$data)=@_; return if -f $path && raw($path) eq $data;
    make_path(dirname($path)); my($f,$name)=tempfile('.unica-native-XXXXXX',DIR=>dirname($path),UNLINK=>0);
    binmode $f; print $f $data or die "write $path: $!"; close $f or die "close $path: $!";
    chmod((-e $path ? (stat($path))[2]&0777 : 0644),$name) or die "chmod $name: $!";
    rename($name,$path) or die "rename $path: $!";
}
sub varint {my($data,$off)=@_; my $value=0; for(my $shift=0;$shift<70;$shift+=7) {need($off<length($data),"Truncated classpath protobuf"); my $byte=ord(substr($data,$off++,1));
    need($shift!=63 || $byte<=1,"Invalid classpath varint"); $value|=($byte&127)<<$shift; return($value,$off) if $byte<128} die "Invalid classpath varint\n"}
sub records {my($data)=@_; my($off,@out)=(0); while($off<length($data)) {my $start=$off; my($tag,$next)=varint($data,$off); need($tag==10,"Unexpected classpath root schema");
    my($size,$payload)=varint($data,$next); my $stop=$payload+$size; need($stop<=length($data) && $payload<$stop && ord(substr($data,$payload,1))==10,"Invalid classpath jar record");
    my($len,$name)=varint($data,$payload+1); my $end=$name+$len; need($end<$stop && ord(substr($data,$end,1))==16,"Unexpected classpath jar identity/type");
    my($kind)=varint($data,$end+1); push @out,[substr($data,$name,$len),$kind,substr($data,$start,$stop-$start)]; $off=$stop} return @out}
my($target,$stock)=@ARGV; my $original=raw($target); my $jar="/system/framework/com.samsung.android.uwb_extras.jar";
my @old=records($original); my @new=grep {$_->[0] eq $jar} records(raw($stock));
need(same([sort map {$_->[1]} @new],[1,3]),"Expected exactly boot and dex2oat UWB records"); need(!scalar(grep {$_->[0] eq $jar} @old),"Unexpected existing UWB classpath");
my $changed=$original.join("",map {$_->[2]} @new); records($changed); need(substr($changed,0,length($original)) eq $original,"Changed existing classpath records");
put($target,$changed); print "Preserved One UI 9 bootclasspath; added only stock UWB extension records\n";
PERL
}
SOURCE_FIRMWARE_PATH="$(cut -d "/" -f 1 -s <<< "$SOURCE_FIRMWARE")_$(cut -d "/" -f 2 -s <<< "$SOURCE_FIRMWARE")"
TARGET_FIRMWARE_PATH="$(cut -d "/" -f 1 -s <<< "$TARGET_FIRMWARE")_$(cut -d "/" -f 2 -s <<< "$TARGET_FIRMWARE")"

SOURCE_HAS_UWB="$(test -f "$FW_DIR/$SOURCE_FIRMWARE_PATH/vendor/etc/permissions/android.hardware.uwb.xml" && echo "true" || echo "false")"
TARGET_HAS_UWB="$(test -f "$FW_DIR/$TARGET_FIRMWARE_PATH/vendor/etc/permissions/android.hardware.uwb.xml" && echo "true" || echo "false")"

if ! $SOURCE_HAS_UWB; then
    if $TARGET_HAS_UWB; then
        SET_PROP "product" "ro.boot.uwbcountrycode" "ff"

        ADD_TO_WORK_DIR "b0qxxx" "product" \
            "overlay/UwbRROverlay.apk" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" \
            "system/app/UwbTest/UwbTest.apk" 0 0 644 "u:object_r:system_file:s0"
        if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
            # Do not replace the Android 17 bootclasspath with a complete
            # Android 16 snapshot merely to add the UWB extension jar.
            APPEND_UWB_BOOTCLASSPATH \
                "$WORK_DIR/system/system/etc/classpaths/bootclasspath.pb" \
                "$SRC_DIR/prebuilts/samsung/b0sxxx/system/etc/classpaths/bootclasspath.pb" || return 1
        else
            ADD_TO_WORK_DIR "$([[ "$TARGET_OS_SINGLE_SYSTEM_IMAGE" == "qssi" ]] && echo "b0qxxx" || echo "b0sxxx")" \
                "system" "system/etc/classpaths/bootclasspath.pb" 0 0 644 "u:object_r:system_file:s0"
        fi
        ADD_TO_WORK_DIR "b0qxxx" "system" \
            "system/etc/init/init.system.uwb.rc" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" \
            "system/etc/permissions/com.samsung.android.uwb_extras.xml" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" \
            "system/etc/permissions/org.carconnectivity.android.digitalkey.timesync.xml" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" \
            "system/etc/permissions/privapp-permissions-com.samsung.android.dcktimesync.xml" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" \
            "system/etc/permissions/privapp-permissions-com.sec.android.app.uwbtest.xml" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" \
            "system/etc/libuwb-cal.conf" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" \
            "system/etc/pp_model.tflite" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" \
            "system/framework/com.samsung.android.uwb_extras.jar" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" \
            "system/framework/semuwb-service.jar" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" \
            "system/lib/libtflite_uwb_jni.so" 0 0 644 "u:object_r:system_lib_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" \
            "system/lib64/libtflite_uwb_jni.so" 0 0 644 "u:object_r:system_lib_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system_ext" \
            "framework/org.carconnectivity.android.digitalkey.timesync.jar" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system_ext" \
            "priv-app/DckTimeSyncService/DckTimeSyncService.apk" 0 0 644 "u:object_r:system_file:s0"
    else
        LOG "\033[0;33m! Nothing to do\033[0m"
    fi
else
    if ! $TARGET_HAS_UWB; then
        ABORT "Missing patch for condition (SOURCE_HAS_UWB: [$SOURCE_HAS_UWB], TARGET_HAS_UWB: [$TARGET_HAS_UWB]). Aborting"
    fi
fi

unset SOURCE_FIRMWARE_PATH TARGET_FIRMWARE_PATH SOURCE_HAS_UWB TARGET_HAS_UWB
