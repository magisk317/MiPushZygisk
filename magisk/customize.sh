CONFIG_DIR=/data/adb/mipush_zygisk
CONFIG_FILE=$CONFIG_DIR/app.conf
DEFAULT_CONFIG=$MODPATH/defaults/app.conf

mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

if [ ! -f "$CONFIG_FILE" ]; then
  if [ -f "$DEFAULT_CONFIG" ]; then
    cp "$DEFAULT_CONFIG" "$CONFIG_FILE"
  else
    cat > "$CONFIG_FILE" <<'EOF'
# MiPush Zygisk config
# Enable all processes of a package:
# com.example.app
#
# Enable only one process:
# com.example.app|com.example.app:push
EOF
  fi
  chmod 600 "$CONFIG_FILE"
fi

ui_print "MiPush Zygisk config: $CONFIG_FILE"
