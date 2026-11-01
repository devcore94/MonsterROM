SOURCE_FIRMWARE_PATH="$(cut -d "/" -f 1 -s <<< "$SOURCE_FIRMWARE")_$(cut -d "/" -f 2 -s <<< "$SOURCE_FIRMWARE")"
TARGET_FIRMWARE_PATH="$(cut -d "/" -f 1 -s <<< "$TARGET_FIRMWARE")_$(cut -d "/" -f 2 -s <<< "$TARGET_FIRMWARE")"

if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
    # Validate the imported descriptor/weight pairs before replacing any tree.
    # A directory can exist while its descriptor or referenced model is absent.
    for SAIV_MODEL in \
            system/system/saiv/image_understanding/db/slens_classifier/slens_classifier_cnn.sni \
            system/system/saiv/image_understanding/db/slens_detector/slens_detector_cnn.sni \
            vendor/etc/saiv/image_understanding/db/unified_detector/model.info \
            vendor/etc/saiv/image_understanding/db/unified_detector/01_2_Preview_UDDetector_v1.5.0.nnc \
            vendor/etc/saiv/image_understanding/db/unified_detector/01_1_Preview_UDClassifier_v1.2.0.nnc \
            vendor/etc/saiv/image_understanding/db/doc_rectifier/doc_rectifier_cnn.info \
            vendor/etc/saiv/image_understanding/db/doc_rectifier/06-1_DocumentScan_DocDewarping_v2.tflite \
            vendor/etc/saiv/image_understanding/db/aic_pet_detector/aic_pet_detector_cnn.info \
            vendor/etc/saiv/image_understanding/db/aic_pet_detector/01_5_Preview_PetDetector_v2.16.2.tflite \
            vendor/etc/saiv/image_understanding/db/slens_classifier/slens_classifier_cnn.tflite \
            vendor/etc/saiv/image_understanding/db/slens_detector/slens_detector_cnn.tflite \
            vendor/etc/saiv/image_understanding/db/hs_segmenter/12-23_PhotoEditor_SuggestErases_HumanSeg.info \
            vendor/etc/saiv/image_understanding/db/hs_segmenter/12-23_PhotoEditor_SuggestErases_v1.10.0_HumanSeg.tflite \
            vendor/etc/saiv/image_understanding/db/hs_segmenter/12-39_PhotoEditor_SuggestErases_BGPclassifier.info \
            vendor/etc/saiv/image_understanding/db/hs_segmenter/12-39_PhotoEditor_SuggestErases_v1.10.1_BGPclassifier.tflite; do
        [ -s "$FW_DIR/$SOURCE_FIRMWARE_PATH/$SAIV_MODEL" ] || {
            ABORT "One UI 9 vision descriptor/weight is missing: $SAIV_MODEL"
            return 1
        }
    done
    for SAIV_MODEL in hs_segmenter/hs_segmenter.info hs_segmenter/hs_segmenter.tflite \
            SS_segmenter/SS_segmenter_cnn.info SS_segmenter/SS_segmenter_cnn_light.caffemodel; do
        [ -s "$WORK_DIR/vendor/etc/saiv/image_understanding/db/$SAIV_MODEL" ] || {
            ABORT "Target vision compatibility model is missing: $SAIV_MODEL"
            return 1
        }
    done
    if [ "$TARGET_PLATFORM" = "exynos2100" ]; then
        # One UI 9 selects by ro.soc.model, not midasSR_devices. Its existing LSI
        # GPU/SNAPLITE profile has the genuine target LITE tensor names.
        # Names/nonempty files alone do not establish this reader/model ABI.
        if ! (
            cd "$FW_DIR/$SOURCE_FIRMWARE_PATH" || exit 1
            sha256sum --check --quiet "$MODPATH/midas.sha256"
        ); then
            ABORT "Unreviewed One UI 9 MIDAS reader/config cohort; requalify before selecting LITE"
            return 1
        fi
        for SAIV_MODEL in libmidas_core.camera.samsung.so libmidas_DNNInterface.camera.samsung.so; do
            cmp -s "$WORK_DIR/system/system/lib64/$SAIV_MODEL" \
                "$FW_DIR/$SOURCE_FIRMWARE_PATH/system/system/lib64/$SAIV_MODEL" || {
                ABORT "Staged MIDAS reader does not match the reviewed One UI 9 cohort: $SAIV_MODEL"
                return 1
            }
        done
        [ "$(GET_PROP "vendor" "ro.soc.model")" = "Exynos 2100" ] || {
            ABORT "Unsupported Exynos2100 MIDAS property selection"
            return 1
        }
        for SAIV_MODEL in 2 3 4; do
            [ -s "$FW_DIR/$TARGET_FIRMWARE_PATH/vendor/etc/midas/SRIBMidas_aiUPSCALER_${SAIV_MODEL}X_LITE_V100_INT8.tflite" ] || {
                ABORT "Target MIDAS ${SAIV_MODEL}X LITE model is missing"
                return 1
            }
        done
        if ! (
            cd "$FW_DIR/$TARGET_FIRMWARE_PATH/vendor/etc/midas" || exit 1
            sha256sum --check --quiet "$MODPATH/midas-lite.sha256"
        ); then
            ABORT "Target MIDAS LITE graphs do not match the reviewed tensor/weight cohort"
            return 1
        fi
        LC_ALL=C git apply --check --unsafe-paths \
            --directory="$FW_DIR/$SOURCE_FIRMWARE_PATH/vendor/etc/midas" \
            "$MODPATH/0001-Select-Exynos2100-MIDAS-LITE-profile.patch" || return 1
    fi
    unset SAIV_MODEL

    # Preserve the target's legacy native readers and their descriptors/weights.
    # Add One UI 9 cohorts at their real paths, without converting NCP models.
    DELETE_FROM_WORK_DIR "system" "system/saiv" || return 1
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/saiv" 0 0 755 "u:object_r:system_file:s0" || return 1
    DELETE_FROM_WORK_DIR "system" "system/saiv/face/cluster_pb" || return 1
    ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "system" "system/saiv/face/cluster_pb" 0 0 755 "u:object_r:system_file:s0" || return 1
    ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "system" "system/saiv/imageCropper" 0 0 755 "u:object_r:system_file:s0" || return 1
    ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "system" "system/saiv/image_understanding" 0 0 755 "u:object_r:system_file:s0" || return 1

    # Stride's One UI 9 detector/layout/ViT models and charsets are one cohort.
    # As in the original module, replace (do not merge) the target OCR tree.
    DELETE_FROM_WORK_DIR "system" "system/saiv/textrecognition" || return 1
    ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "system" "system/saiv/textrecognition" 0 0 755 "u:object_r:system_file:s0" || return 1

    # The new CPU SLENS descriptors also require the source CPU weights, not
    # the target's EDEN payloads with the same .tflite filenames.
    for SAIV_MODEL in unified_detector doc_rectifier aic_pet_detector slens_classifier slens_detector hs_segmenter; do
        ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "vendor" "etc/saiv/image_understanding/db/$SAIV_MODEL" \
            0 0 755 "u:object_r:vendor_configs_file:s0" || return 1
    done
    unset SAIV_MODEL
    ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "vendor" "etc/midas" 0 0 755 "u:object_r:vendor_configs_file:s0" || return 1
    if [ "$TARGET_PLATFORM" = "exynos2100" ]; then
        for SAIV_MODEL in 2 3 4; do
            ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "vendor" "etc/midas/SRIBMidas_aiUPSCALER_${SAIV_MODEL}X_LITE_V100_INT8.tflite" \
                0 0 644 "u:object_r:vendor_configs_file:s0" || return 1
        done
        unset SAIV_MODEL
        LOG "- Selecting the Exynos2100 MIDAS LITE profile"
        EVAL "LC_ALL=C git apply --verbose --unsafe-paths --directory=\"$WORK_DIR/vendor/etc/midas\" \"$MODPATH/0001-Select-Exynos2100-MIDAS-LITE-profile.patch\"" || return 1
        # Do not alias another model or force success for the unshipped 1X graph.
        LOGW "MIDAS LITE 2X/3X/4X paths restored; 1X/Pro/GenSR and device inference remain unqualified"
    fi

    # Retain the complete target SS/HS compatibility pairs. Their legacy paths
    # are still used by native consumers, independently of the app ABI.
    for SAIV_MODEL in hs_segmenter/hs_segmenter.info hs_segmenter/hs_segmenter.tflite \
            SS_segmenter/SS_segmenter_cnn.info SS_segmenter/SS_segmenter_cnn_light.caffemodel; do
        [ -s "$WORK_DIR/vendor/etc/saiv/image_understanding/db/$SAIV_MODEL" ] || {
            ABORT "Target vision compatibility model is missing: $SAIV_MODEL"
            return 1
        }
    done
    unset SAIV_MODEL
    LOGW "One UI 9 vision cohorts staged unchanged; NPU/EDEN hardware execution remains unvalidated"
    unset SOURCE_FIRMWARE_PATH TARGET_FIRMWARE_PATH
    return 0
fi

DELETE_FROM_WORK_DIR "system" "system/saiv"
ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/saiv" 0 0 755 "u:object_r:system_file:s0"

# SEC_PRODUCT_FEATURE_VISION_CONFIG_FACE_RECOGNITION_SOLUTION
SOURCE_VISION_CONFIG_FACE_RECOGNITION_SOLUTION="$(GET_FLOATING_FEATURE_CONFIG "$FW_DIR/$SOURCE_FIRMWARE_PATH/system/system/etc/floating_feature.xml" "SEC_FLOATING_FEATURE_GALLERY_CONFIG_FACE_CLUSTER_VERSION")"
TARGET_VISION_CONFIG_FACE_RECOGNITION_SOLUTION="$(GET_FLOATING_FEATURE_CONFIG "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/etc/floating_feature.xml" "SEC_FLOATING_FEATURE_GALLERY_CONFIG_FACE_CLUSTER_VERSION")"
if [[ "$(GET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_GALLERY_CONFIG_FACE_CLUSTER_VERSION")" == "$SOURCE_VISION_CONFIG_FACE_RECOGNITION_SOLUTION" ]]; then
    if [[ "$TARGET_VISION_CONFIG_FACE_RECOGNITION_SOLUTION" != "$SOURCE_VISION_CONFIG_FACE_RECOGNITION_SOLUTION" ]] || \
            [ "$TARGET_PLATFORM_SDK_VERSION" -lt "$SOURCE_PLATFORM_SDK_VERSION" ]; then
        if [ -d "$WORK_DIR/system/system/saiv/face/cluster_pb" ]; then
            DELETE_FROM_WORK_DIR "system" "system/saiv/face/cluster_pb"
        fi
        ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "system" "system/saiv/face/cluster_pb" 0 0 755 "u:object_r:system_file:s0"
    fi
fi

# SEC_PRODUCT_FEATURE_SAIV_CONFIG_MIDAS
if [ ! -f "$WORK_DIR/vendor/etc/midas/moire_detection/moire_detection.tflite" ]; then
    ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "vendor" "etc/midas/moire_detection/moire_detection.tflite" 0 0 644 "u:object_r:vendor_configs_file:s0"
fi
if [ ! "$(find "$WORK_DIR/vendor/etc/midas" -maxdepth 1 -type f -name "SRIBMQA_aiFiQA*" 2> /dev/null)" ]; then
    ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "vendor" "etc/midas/SRIBMQA_aiFiQA_V100_FP32.tflite" 0 0 644 "u:object_r:vendor_configs_file:s0"
fi
if [ ! -f "$WORK_DIR/vendor/etc/midas/SRIBMQA_aiIQA_V100_FP32.tflite" ]; then
    ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "vendor" "etc/midas/SRIBMQA_aiIQA_V100_FP32.tflite" 0 0 644 "u:object_r:vendor_configs_file:s0"
fi
if [ "$(find "$WORK_DIR/vendor/etc/midas" -maxdepth 1 -type f -name "*UPSCALER_*_LITE*" 2> /dev/null)" ]; then
    # Ensure AI_UPSCALE LITE models are loaded if available
    if ! sed -n "/\"midasSR_devices\"/,/]/p" "$WORK_DIR/vendor/etc/midas/midas_config.json" | grep -q "\"$(GET_PROP "ro.product.device")\""; then
        LOG "- Patching /vendor/etc/midas/midas_config.json"
        EVAL "sed -i \"/\\\"midasSR_devices\\\"[^[]*\\[/a\\\\    \\\"$(GET_PROP "ro.product.device")\\\",\" \"$WORK_DIR/vendor/etc/midas/midas_config.json\""
    fi
fi

# SEC_PRODUCT_FEATURE_GALLERY_CONFIG_IMAGE_TAGGER_VERSION
SOURCE_GALLERY_CONFIG_IMAGE_TAGGER_VERSION="$(GET_FLOATING_FEATURE_CONFIG "$FW_DIR/$SOURCE_FIRMWARE_PATH/system/system/etc/floating_feature.xml" "SEC_FLOATING_FEATURE_GALLERY_CONFIG_IMAGE_TAGGER_VERSION")"
TARGET_GALLERY_CONFIG_IMAGE_TAGGER_VERSION="$(GET_FLOATING_FEATURE_CONFIG "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/etc/floating_feature.xml" "SEC_FLOATING_FEATURE_GALLERY_CONFIG_IMAGE_TAGGER_VERSION")"
if [[ "$(GET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_GALLERY_CONFIG_IMAGE_TAGGER_VERSION")" == "$SOURCE_GALLERY_CONFIG_IMAGE_TAGGER_VERSION" ]]; then
    if [[ "$TARGET_GALLERY_CONFIG_IMAGE_TAGGER_VERSION" != "$SOURCE_GALLERY_CONFIG_IMAGE_TAGGER_VERSION" ]] || \
            [ "$TARGET_PLATFORM_SDK_VERSION" -lt "$SOURCE_PLATFORM_SDK_VERSION" ]; then
        if [ -d "$WORK_DIR/system/system/saiv/image_understanding/db/aig" ]; then
            DELETE_FROM_WORK_DIR "system" "system/saiv/image_understanding/db/aig"
        fi
        ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "system" "system/saiv/image_understanding/db/aig" 0 0 755 "u:object_r:system_file:s0"
        if [ -d "$WORK_DIR/vendor/saiv/image_understanding/db/aig_classifier" ]; then
            DELETE_FROM_WORK_DIR "vendor" "saiv/image_understanding/db/aig_classifier"
        fi
        ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "vendor" "saiv/image_understanding/db/aig_classifier" 0 2000 755 "u:object_r:vendor_snap_file:s0"
        if [ -d "$WORK_DIR/vendor/saiv/image_understanding/db/aig_detector" ]; then
            DELETE_FROM_WORK_DIR "vendor" "saiv/image_understanding/db/aig_detector"
        fi
        if [ -d "$WORK_DIR/vendor/saiv/image_understanding/db/aig_document_classifier" ]; then
            DELETE_FROM_WORK_DIR "vendor" "saiv/image_understanding/db/aig_document_classifier"
        fi
        ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "vendor" "saiv/image_understanding/db/aig_document_classifier" 0 2000 755 "u:object_r:vendor_snap_file:s0"
        if [ -d "$WORK_DIR/vendor/saiv/image_understanding/db/aig_document_detector" ]; then
            DELETE_FROM_WORK_DIR "vendor" "saiv/image_understanding/db/aig_document_detector"
        fi
        ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "vendor" "saiv/image_understanding/db/aig_document_detector" 0 2000 755 "u:object_r:vendor_snap_file:s0"
        if [ -d "$WORK_DIR/vendor/saiv/image_understanding/db/srr_interaction" ]; then
            DELETE_FROM_WORK_DIR "vendor" "saiv/image_understanding/db/srr_interaction"
        fi
    fi
fi

# Photo Editor "oneUI-full-release"/"genAI-full-release" flavor models
if [ -f "$WORK_DIR/system/system/priv-app/PhotoEditor_Full/PhotoEditor_Full.apk" ] || \
        [ -f "$WORK_DIR/system/system/priv-app/PhotoEditor_AIFull/PhotoEditor_AIFull.apk" ]; then
    if [ ! -d "$WORK_DIR/vendor/etc/saiv/image_understanding/db/hs_segmenter" ] || \
            [ "$TARGET_PLATFORM_SDK_VERSION" -lt "$SOURCE_PLATFORM_SDK_VERSION" ]; then
        if [ -d "$WORK_DIR/vendor/etc/saiv/image_understanding/db/hs_segmenter" ]; then
            DELETE_FROM_WORK_DIR "vendor" "etc/saiv/image_understanding/db/hs_segmenter"
        fi
        ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "vendor" "etc/saiv/image_understanding/db/hs_segmenter/hs_segmenter.info" 0 0 644 "u:object_r:vendor_configs_file:s0"
        ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "vendor" "etc/saiv/image_understanding/db/hs_segmenter/hs_segmenter.tflite" 0 0 644 "u:object_r:vendor_configs_file:s0"
    fi
else
    if [ -d "$WORK_DIR/vendor/etc/saiv/image_understanding/db/hs_segmenter" ]; then
        DELETE_FROM_WORK_DIR "vendor" "etc/saiv/image_understanding/db/hs_segmenter"
    fi
fi

# SEC_PRODUCT_FEATURE_GALLERY_CONFIG_PET_CLUSTER_VERSION
SOURCE_GALLERY_CONFIG_PET_CLUSTER_VERSION="$(GET_FLOATING_FEATURE_CONFIG "$FW_DIR/$SOURCE_FIRMWARE_PATH/system/system/etc/floating_feature.xml" "SEC_FLOATING_FEATURE_GALLERY_CONFIG_PET_CLUSTER_VERSION")"
TARGET_GALLERY_CONFIG_PET_CLUSTER_VERSION="$(GET_FLOATING_FEATURE_CONFIG "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/etc/floating_feature.xml" "SEC_FLOATING_FEATURE_GALLERY_CONFIG_PET_CLUSTER_VERSION")"
if [[ "$(GET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_GALLERY_CONFIG_PET_CLUSTER_VERSION")" == "$SOURCE_GALLERY_CONFIG_PET_CLUSTER_VERSION" ]]; then
    if [[ "$SOURCE_GALLERY_CONFIG_PET_CLUSTER_VERSION" != "None" ]]; then
        if [[ "$TARGET_GALLERY_CONFIG_PET_CLUSTER_VERSION" != "$SOURCE_GALLERY_CONFIG_PET_CLUSTER_VERSION" ]] || \
                [ "$TARGET_PLATFORM_SDK_VERSION" -lt "$SOURCE_PLATFORM_SDK_VERSION" ]; then
            if [ -d "$WORK_DIR/vendor/saiv/image_understanding/db/pet_detector" ]; then
                DELETE_FROM_WORK_DIR "vendor" "saiv/image_understanding/db/pet_detector"
            fi
            ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "vendor" "saiv/image_understanding/db/pet_detector" 0 2000 755 "u:object_r:vendor_snap_file:s0"
            if [ -d "$WORK_DIR/vendor/saiv/image_understanding/db/pet_mypetsearch" ]; then
                DELETE_FROM_WORK_DIR "vendor" "saiv/image_understanding/db/pet_mypetsearch"
            fi
            ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "vendor" "saiv/image_understanding/db/pet_mypetsearch" 0 2000 755 "u:object_r:vendor_snap_file:s0"
        fi
    else
        if [ -d "$WORK_DIR/vendor/saiv/image_understanding/db/pet_detector" ]; then
            DELETE_FROM_WORK_DIR "vendor" "saiv/image_understanding/db/pet_detector"
        fi
        if [ -d "$WORK_DIR/vendor/saiv/image_understanding/db/pet_mypetsearch" ]; then
            DELETE_FROM_WORK_DIR "vendor" "saiv/image_understanding/db/pet_mypetsearch"
        fi
    fi
fi

# SEC_PRODUCT_FEATURE_VISION_CONFIG_BIXBYVISION_VERSION
if [ -f "$WORK_DIR/system/system/priv-app/BixbyVisionFramework3.5/BixbyVisionFramework3.5.apk" ]; then
    if [ ! -d "$WORK_DIR/vendor/etc/saiv/image_understanding/db/slens_classifier" ] || \
            [ "$TARGET_PLATFORM_SDK_VERSION" -lt "$SOURCE_PLATFORM_SDK_VERSION" ]; then
        if [ -d "$WORK_DIR/system/system/saiv/image_understanding/db/slens_classifier" ]; then
            DELETE_FROM_WORK_DIR "system" "system/saiv/image_understanding/db/slens_classifier"
        fi
        ADD_TO_WORK_DIR "pa2qxxx" "system" "system/saiv/image_understanding/db/slens_classifier/slens_classifier_cnn.sni" 0 0 644 "u:object_r:system_file:s0"
        if [ -d "$WORK_DIR/vendor/etc/saiv/image_understanding/db/slens_classifier" ]; then
            DELETE_FROM_WORK_DIR "vendor" "etc/saiv/image_understanding/db/slens_classifier"
        fi
        ADD_TO_WORK_DIR "pa2qxxx" "vendor" "etc/saiv/image_understanding/db/slens_classifier/slens_classifier_cnn.tflite" 0 0 644 "u:object_r:vendor_configs_file:s0"
        if [ -d "$WORK_DIR/vendor/saiv/image_understanding/db/slens_classifier" ]; then
            DELETE_FROM_WORK_DIR "vendor" "saiv/image_understanding/db/slens_classifier"
        fi
    fi
    if [ ! -d "$WORK_DIR/vendor/etc/saiv/image_understanding/db/slens_detector" ] || \
            [ "$TARGET_PLATFORM_SDK_VERSION" -lt "$SOURCE_PLATFORM_SDK_VERSION" ]; then
        if [ -d "$WORK_DIR/system/system/saiv/image_understanding/db/slens_detector" ]; then
            DELETE_FROM_WORK_DIR "system" "system/saiv/image_understanding/db/slens_detector"
        fi
        ADD_TO_WORK_DIR "pa2qxxx" "system" "system/saiv/image_understanding/db/slens_detector/slens_detector_cnn.sni" 0 0 644 "u:object_r:system_file:s0"
        if [ -d "$WORK_DIR/vendor/etc/saiv/image_understanding/db/slens_detector" ]; then
            DELETE_FROM_WORK_DIR "vendor" "etc/saiv/image_understanding/db/slens_detector"
        fi
        ADD_TO_WORK_DIR "pa2qxxx" "vendor" "etc/saiv/image_understanding/db/slens_detector/slens_detector_cnn.tflite" 0 0 644 "u:object_r:vendor_configs_file:s0"
        if [ -d "$WORK_DIR/vendor/saiv/image_understanding/db/slens_detector" ]; then
            DELETE_FROM_WORK_DIR "vendor" "saiv/image_understanding/db/slens_detector"
        fi
    fi
else
    if [ -d "$WORK_DIR/system/system/saiv/image_understanding/db/slens_classifier" ]; then
        DELETE_FROM_WORK_DIR "system" "system/saiv/image_understanding/db/slens_classifier"
    fi
    if [ -d "$WORK_DIR/system/system/saiv/image_understanding/db/slens_detector" ]; then
        DELETE_FROM_WORK_DIR "system" "system/saiv/image_understanding/db/slens_detector"
    fi
    if [ -d "$WORK_DIR/vendor/etc/saiv/image_understanding/db/slens_classifier" ]; then
        DELETE_FROM_WORK_DIR "vendor" "etc/saiv/image_understanding/db/slens_classifier"
    fi
    if [ -d "$WORK_DIR/vendor/etc/saiv/image_understanding/db/slens_detector" ]; then
        DELETE_FROM_WORK_DIR "vendor" "etc/saiv/image_understanding/db/slens_detector"
    fi
    if [ -d "$WORK_DIR/vendor/saiv/image_understanding/db/slens_classifier" ]; then
        DELETE_FROM_WORK_DIR "vendor" "saiv/image_understanding/db/slens_classifier"
    fi
    if [ -d "$WORK_DIR/vendor/saiv/image_understanding/db/slens_detector" ]; then
        DELETE_FROM_WORK_DIR "vendor" "saiv/image_understanding/db/slens_detector"
    fi
fi

# SEC_PRODUCT_FEATURE_CAMERA_CONFIG_DOCUMENT_DEWARP_VERSION
SOURCE_CAMERA_CONFIG_DOCUMENT_DEWARP_VERSION="$(GET_FLOATING_FEATURE_CONFIG "$FW_DIR/$SOURCE_FIRMWARE_PATH/system/system/etc/floating_feature.xml" "SEC_FLOATING_FEATURE_CAMERA_DOCUMENTSCAN_SOLUTIONS")"
TARGET_CAMERA_CONFIG_DOCUMENT_DEWARP_VERSION="$(GET_FLOATING_FEATURE_CONFIG "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/etc/floating_feature.xml" "SEC_FLOATING_FEATURE_CAMERA_DOCUMENTSCAN_SOLUTIONS")"
if [[ "$(GET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_CAMERA_DOCUMENTSCAN_SOLUTIONS")" == "$SOURCE_CAMERA_CONFIG_DOCUMENT_DEWARP_VERSION" ]]; then
    if [[ "$SOURCE_CAMERA_CONFIG_DOCUMENT_DEWARP_VERSION" == *"AI_DEWARPING"* ]]; then
        if [[ "$TARGET_CAMERA_CONFIG_DOCUMENT_DEWARP_VERSION" != *"AI_DEWARPING"* ]] || \
                [ "$TARGET_PLATFORM_SDK_VERSION" -lt "$SOURCE_PLATFORM_SDK_VERSION" ]; then
            ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" \
                "system" "system/saiv/image_understanding/db/smartscan_rectifier/deep_dewarp_cnn.sni" 0 0 644 "u:object_r:system_file:s0"
            ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" \
                "vendor" "saiv/image_understanding/db/smartscan_rectifier/deep_dewarp_cnn.onnx" 0 0 644 "u:object_r:vendor_snap_file:s0"
        fi
    else
        if [ -d "$WORK_DIR/system/system/saiv/image_understanding/db/smartscan_rectifier" ]; then
            DELETE_FROM_WORK_DIR "system" "system/saiv/image_understanding/db/smartscan_rectifier"
        fi
        if [ -d "$WORK_DIR/vendor/saiv/image_understanding/db/smartscan_rectifier" ]; then
            DELETE_FROM_WORK_DIR "vendor" "saiv/image_understanding/db/smartscan_rectifier"
        fi
    fi
fi

# SEC_PRODUCT_FEATURE_VISION_CONFIG_SMART_CROPPING_SOLUTION
if [ ! -d "$WORK_DIR/system/system/saiv/smartcropping_2.0" ] || \
        [ "$TARGET_PLATFORM_SDK_VERSION" -lt "$SOURCE_PLATFORM_SDK_VERSION" ]; then
    if [ -d "$WORK_DIR/system/system/saiv/smartcropping_2.0" ]; then
        DELETE_FROM_WORK_DIR "system" "system/saiv/smartcropping_2.0"
    fi
    ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "system" "system/saiv/smartcropping_2.0/db/smartcrop_saliency_deploy.prototxt" 0 0 644 "u:object_r:system_file:s0"
    ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "system" "system/saiv/smartcropping_2.0/db/smartcrop_saliency_train" 0 0 644 "u:object_r:system_file:s0"
fi
if [ ! -d "$WORK_DIR/vendor/saiv/image_understanding/db/sce_detector" ] || \
        [ "$TARGET_PLATFORM_SDK_VERSION" -lt "$SOURCE_PLATFORM_SDK_VERSION" ]; then
    if [ -d "$WORK_DIR/vendor/saiv/image_understanding/db/sce_detector" ]; then
        DELETE_FROM_WORK_DIR "vendor" "saiv/image_understanding/db/sce_detector"
    fi
    ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "vendor" "saiv/image_understanding/db/sce_detector/sce_detector_cnn.tflite" 0 0 644 "u:object_r:vendor_snap_file:s0"
fi

# SEC_PRODUCT_FEATURE_CAMERA_CONFIG_STRIDE_OCR_VERSION
if [ -d "$WORK_DIR/system/system/saiv/textrecognition" ]; then
    DELETE_FROM_WORK_DIR "system" "system/saiv/textrecognition"
fi
ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "system" "system/saiv/textrecognition" 0 0 755 "u:object_r:system_file:s0"

# SEC_PRODUCT_FEATURE_CAMERA_CONFIG_VENDOR_LIB_INFO:=*smart_scan.samsung.v2*
if [ -f "$WORK_DIR/system/system/lib64/libSmartScan.camera.samsung.so" ]; then
    if [ ! -d "$WORK_DIR/vendor/etc/saiv/image_understanding/db/SS_segmenter" ] || \
            [ "$TARGET_PLATFORM_SDK_VERSION" -lt "$SOURCE_PLATFORM_SDK_VERSION" ]; then
        if [ -d "$WORK_DIR/vendor/etc/saiv/image_understanding/db/SS_segmenter" ]; then
            DELETE_FROM_WORK_DIR "vendor" "etc/saiv/image_understanding/db/SS_segmenter"
        fi
        ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "vendor" "etc/saiv/image_understanding/db/SS_segmenter" 0 2000 755 "u:object_r:vendor_configs_file:s0"
    fi
fi

unset SOURCE_FIRMWARE_PATH TARGET_FIRMWARE_PATH \
    SOURCE_VISION_CONFIG_FACE_RECOGNITION_SOLUTION TARGET_VISION_CONFIG_FACE_RECOGNITION_SOLUTION \
    SOURCE_GALLERY_CONFIG_IMAGE_TAGGER_VERSION TARGET_GALLERY_CONFIG_IMAGE_TAGGER_VERSION \
    SOURCE_GALLERY_CONFIG_PET_CLUSTER_VERSION TARGET_GALLERY_CONFIG_PET_CLUSTER_VERSION \
    SOURCE_CAMERA_CONFIG_DOCUMENT_DEWARP_VERSION TARGET_CAMERA_CONFIG_DOCUMENT_DEWARP_VERSION
