LOG "- Installing the One UI 9.5 kernel"

mkdir -p "$TMP_DIR"
KERNEL_DIR="$(mktemp -d "$TMP_DIR/chiclet.XXXXXXXX")" || ABORT
EVAL "unpack_bootimg --boot_img \"$WORK_DIR/kernel/boot.img\" --out \"$KERNEL_DIR\" --format mkbootimg -0 > \"$KERNEL_DIR/args\"" || ABORT
EVAL "gzip -dc \"$MODPATH/Image.gz\" > \"$KERNEL_DIR/kernel\"" || ABORT
EVAL "xargs -0 -a \"$KERNEL_DIR/args\" mkbootimg --output \"$KERNEL_DIR/boot.img\"" || ABORT
EVAL "mv \"$KERNEL_DIR/boot.img\" \"$WORK_DIR/kernel/boot.img\"" || ABORT
EVAL "rm -rf \"$KERNEL_DIR\""

unset KERNEL_DIR
