# Restore the original Settings embedding provider, retaining its real version.
# One UI 9 Settings uses the same 0.37 model/schema and asks for the "settings"
# adapter. The 4.0 provider is deliberately below the Gallery/other caller gates;
# it does not implement the newer QueryProcessor or advertise FUNCTION_INFO.
(
    [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ] || {
        ABORT "Settings semantic provider was reviewed for One UI 9 only"
        exit 1
    }
    SSCO_SOURCE="$FW_DIR/${SOURCE_FIRMWARE%%/*}_$(cut -d / -f 2 <<< "$SOURCE_FIRMWARE")/system/system/priv-app"
    SSCO_PREBUILT="$SRC_DIR/prebuilts/samsung/pa2qxxx/system/priv-app/SemanticSearchCore"
    SSCO_DEST="$WORK_DIR/system/system/priv-app/SemanticSearchCore/SemanticSearchCore.apk"
    # Normal module execution still has the signed donor APK and a deknox
    # decode. Also accept the reviewed final rebuilt APK for repeat validation.
    [ "$(sha256sum "$WORK_DIR/system/system/priv-app/SamsungSmartSuggestions/SamsungSmartSuggestions.apk" | cut -d ' ' -f 1)" = \
        "8611bacec5cf3e135b1ed587044f9ab029c48ef4d241c2bd7d65956faa6aaeff" ] || {
        ABORT "Unreviewed staged Smart Suggestions semantic provider client"
        exit 1
    }
    SSCO_SETTINGS_HASH="$(sha256sum "$WORK_DIR/system/system/priv-app/SecSettingsIntelligence/SecSettingsIntelligence.apk" | cut -d ' ' -f 1)"
    case "$SSCO_SETTINGS_HASH" in
        189ebf6d48159c57a1ad71aa16c4353c04ff3aaed2aae87f96be635b6b2bea18|b0faffe7433c83c8efe4f2fdda9c9fcc4e8a69be8c963b6b88c7b791fc5e15c9) ;;
        *) ABORT "Unreviewed staged Settings Intelligence semantic client"; exit 1 ;;
    esac
    SSCO_DECODE="$APKTOOL_DIR/system/priv-app/SecSettingsIntelligence/SecSettingsIntelligence.apk"
    if [ -d "$SSCO_DECODE" ]; then
        [ "$(sha256sum "$SSCO_DECODE/res/raw/semantic_schema.xml" | cut -d ' ' -f 1)" = \
            "8321bd0bac9bc43b0a95a4631a6b8b762589db567ef9adbeef2fc5485ae4d4d0" ] && \
        [ "$(sha256sum "$SSCO_DECODE/smali_classes2/com/samsung/android/settings/intelligence/search/sse/SSESearchManager.smali" | cut -d ' ' -f 1)" = \
            "8700470192177552d23c35c53d07558793eb367c97790290adf08be793909b69" ] || {
            ABORT "Unreviewed decoded Settings semantic schema or client implementation"
            exit 1
        }
    fi
    [ "$(sha256sum "$WORK_DIR/system/system/etc/permissions/privapp-permissions-com.android.settings.intelligence.xml" | cut -d ' ' -f 1)" = \
        "835380ed1e5ecaaa4a768c9d7b0b21c8abee018ce788bb4448613cb007944f1f" ] || {
        ABORT "Settings semantic provider access needs its reviewed privileged-permission grants"
        exit 1
    }
    [ "$(sha256sum "$SSCO_SOURCE/SamsungSmartSuggestions/SamsungSmartSuggestions.apk" | cut -d ' ' -f 1)" = \
        "8611bacec5cf3e135b1ed587044f9ab029c48ef4d241c2bd7d65956faa6aaeff" ] && \
    [ "$(sha256sum "$SSCO_SOURCE/SecSettingsIntelligence/SecSettingsIntelligence.apk" | cut -d ' ' -f 1)" = \
        "189ebf6d48159c57a1ad71aa16c4353c04ff3aaed2aae87f96be635b6b2bea18" ] || {
        ABORT "Unreviewed One UI 9 Settings semantic-search consumer cohort"
        exit 1
    }
    [ ! -e "$SSCO_PREBUILT/SemanticSearchCore.apk" ] && \
    [ "$(find "$SSCO_PREBUILT" -maxdepth 1 -name 'SemanticSearchCore.apk.[0-9][0-9]' | wc -l)" -eq 2 ] && \
    [ "$(sha256sum "$SSCO_PREBUILT/SemanticSearchCore.apk.00" | cut -d ' ' -f 1)" = \
        "2b0ca0355b7f28edfa6b1b2c1fc331942fa3fd33c6caf145b8b7e4ca318532f4" ] && \
    [ "$(sha256sum "$SSCO_PREBUILT/SemanticSearchCore.apk.01" | cut -d ' ' -f 1)" = \
        "9dcf8c8e1ba65757e2a2581f835c1ea60765fa2f32409d3b1608daedbadfc579" ] && \
    [ "$(cat "$SSCO_PREBUILT/SemanticSearchCore.apk.00" "$SSCO_PREBUILT/SemanticSearchCore.apk.01" | sha256sum | cut -d ' ' -f 1)" = \
        "e19ed0578454da0b050191c18932757b7a860623fe575cc8fe4fa1db330b23a6" ] || {
        ABORT "Unreviewed Settings semantic provider/model/tokenizer cohort"
        exit 1
    }
    if [ -e "$SSCO_DEST" ] && [ "$(sha256sum "$SSCO_DEST" | cut -d ' ' -f 1)" != \
        "e19ed0578454da0b050191c18932757b7a860623fe575cc8fe4fa1db330b23a6" ]; then
        ABORT "Refusing to replace an unreviewed existing SemanticSearchCore"
        exit 1
    fi
    LOG_STEP_IN "- Restoring Settings semantic search model 0.37"
    ADD_TO_WORK_DIR "pa2qxxx" "system" \
        "system/priv-app/SemanticSearchCore/SemanticSearchCore.apk" 0 0 644 "u:object_r:system_file:s0" || exit 1
    [ "$(sha256sum "$SSCO_DEST" | cut -d ' ' -f 1)" = \
        "e19ed0578454da0b050191c18932757b7a860623fe575cc8fe4fa1db330b23a6" ] || {
        ABORT "Settings semantic provider copy failed verification"
        exit 1
    }
    LOG_STEP_OUT
)
