LOG "- Using the local Perfetto sockets"

EVAL "sed -i '/^    start traced\$/i\\    setprop traced.relay_producer_port \"\"' \"$WORK_DIR/system/system/etc/init/perfetto.rc\""
