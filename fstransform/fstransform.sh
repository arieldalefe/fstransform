#!/bin/dash

PROG=fstransform
PROG_VERSION=0.3.5
____='           '


BOOT_CMD_which=which

CMDS_bootstrap="which expr id"
CMDS="blockdev losetup mount umount mkdir rmdir rm mkfifo dd sync fsck mkfs fsmove fsremap"
# commands that may need different variants for source and target filesystems
CMDS_dual="fsck"
# commands not found in environment
CMDS_missing=

# start with a clean environment
ERR=0
DEVICE=
FSTYPE=
DEVICE_SIZE_IN_BYTES=
DEVICE_MOUNT_POINT=
DEVICE_FSTYPE=
LOOP_FILE=
LOOP_DEVICE=
LOOP_MOUNT_POINT=
ZERO_FILE=

OPTS_fsmove=
OPTS_fsremap=
OPTS_mkfs=
OPTS_fsck_source="-p -f"
OPTS_fsck_target="-p -f"
X_COPY_LOOP_FILE=
X_COPY_DEVICE=

USER_ANSWER=

for cmd in $CMDS_bootstrap $CMDS; do
  eval "CMD_$cmd="
done
for cmd in $CMDS_dual; do
  eval "CMD_${cmd}_source="
  eval "CMD_${cmd}_target="
done

FIFO_OUT="/tmp/fstransform.out.$$"
FIFO_ERR="/tmp/fstransform.err.$$"

exec 5>/dev/null

log_info_4_cmd() {
  echo "$@"
  echo "$@" 1>&5  
}
log_info() {
  echo "$PROG: $@"
  echo "$PROG: $@" 1>&5  
}
log_info_add() {
  echo "$____  $@"
  echo "$____  $@" 1>&5  
}

log_start() {
  echo -n "$PROG: $@"
  echo -n "$PROG: $@" 1>&5  
}
log_end() {
  echo "$@"
  echo "$@" 1>&5  
}

log_warn() {
  echo
  echo "$PROG: WARNING: $@"
  echo 1>&5
  echo "$PROG: WARNING: $@" 1>&5  
}
log_warn_add() {
  echo "$____  $@"
  echo "$____  $@" 1>&5  
}
log_warn_add_prompt() {
  echo -n "$____  $@"
  echo "$____  $@" 1>&5  
}

log_err() {
  echo
  echo "ERROR! $PROG: $@"
  echo 1>&5
  echo "ERROR! $PROG: $@" 1>&5  
}
log_err_add() {
  echo "       $@"
  echo "       $@" 1>&5  
}
log_err_add_prompt() {
  echo -n "       $@"
  echo "       $@" 1>&5  
}

append_to_log_file() {
  PROG_LOG_FILE="$HOME/.fstransform/log.$$"

  "$CMD_mkdir" -p "$HOME/.fstransform" >/dev/null 2>&1
  > "$PROG_LOG_FILE" >/dev/null 2>&1
  if test -w "$PROG_LOG_FILE"; then
    exec 5>"$PROG_LOG_FILE"
  fi
  log_info "saving output of this script into $PROG_LOG_FILE"
}

log_info "starting version $PROG_VERSION, checking environment"

# parse command line arguments and set USER_CMD_* variables accordingly
parse_args() {
  log_info "parsing command line arguments"
  for arg in "$@"; do
    case "$arg" in
      --cmd-*=* )
        cmd="`$CMD_expr match \"$arg\" '--cmd-\(.*\)=.*'`"
        user_cmd="`$CMD_expr match \"$arg\" '--cmd-.*=\(.*\)'`"
        eval "USER_CMD_$cmd=\"$user_cmd\""
        ;;
      --loop-file=*)
        LOOP_FILE="`$CMD_expr match \"$arg\" '--loop-file=\(.*\)'`"
	log_info "loop file '$LOOP_FILE' specified on command line"
        ;;
      --loop-mount-point=*)
        LOOP_MOUNT_POINT="`$CMD_expr match \"$arg\" '--loop-mount-point=\(.*\)'`"
	log_info "loop file mount point '$LOOP_MOUNT_POINT' specified on command line"
        ;;
      --zero-file=*)
        ZERO_FILE="`$CMD_expr match \"$arg\" '--zero-file=\(.*\)'`"
	log_info "zero file '$ZERO_FILE' specified on command line"
        ;;
      --device-fstype=*)
        DEVICE_FSTYPE="`$CMD_expr match \"$arg\" '--device-fstype=\(.*\)'`"
	log_info "device initial filesystem type '$DEVICE_FSTYPE' specified on command line"
        ;;
      --opts-fsmove=*)
        OPTS_fsmove="`$CMD_expr match \"$arg\" '--opts-fsmove=\(.*\)'`"
	log_info "options '$OPTS_fsmove' for fsmove specified on command line"
	;;
      --opts-fsremap=*)
        OPTS_fsremap="`$CMD_expr match \"$arg\" '--opts-fsremap=\(.*\)'`"
	log_info "options '$OPTS_fsmove' for fsremap specified on command line"
	;;
      --opts-mkfs=*)
        OPTS_mkfs="`$CMD_expr match \"$arg\" '--opts-mkfs=\(.*\)'`"
	log_info "options '$OPTS_mkfs' for mkfs specified on command line"
	;;
      --opts-fsck-source=*)
        OPTS_fsck_source="`$CMD_expr match \"$arg\" '--opts-fsck-source=\(.*\)'`"
	log_info "options '$OPTS_fsck_source' for fsck(source filesystem) specified on command line"
	;;
      --opts-fsck-target=*)
        OPTS_fsck_target="`$CMD_expr match \"$arg\" '--opts-fsck-target=\(.*\)'`"
	log_info "options '$OPTS_FSCK_TARGET_FS' for fsck(target filesystem) specified on command line"
	;;
      --x-copy-device=*)
        X_COPY_DEVICE="`$CMD_expr match \"$arg\" '--x-copy-device=\(.*\)'`"
	log_info "(internal option) device will be copied to '$X_COPY_DEVICE' just before remapping"
        ;;
      --x-copy-loop-file=*)
        X_COPY_LOOP_FILE="`$CMD_expr match \"$arg\" '--x-copy-loop-file=\(.*\)'`"
	CMDS="$CMDS cmp"
	CMD_cmp=
	log_info "(internal option) loop file will be copied to '$X_COPY_LOOP_FILE'"
	log_info_add "command 'cmp' will be needed to verify it after transformation."
        ;;
      --*)
        log_info "ignoring unknown option '$arg'"
        ;;
      *)
        if test "$DEVICE" = ""; then
	  DEVICE="$arg"
	elif test "$FSTYPE" = ""; then
	  FSTYPE="$arg"
	else
          log_info "ignoring extra argument '$arg'"
	fi
	;;
    esac
  done
}

detect_cmd() {
  local my_cmd_which="$CMD_which"
  if test "$my_cmd_which" = ""; then
    my_cmd_which="$BOOT_CMD_which"
  fi

  local cmd="$1"
  local my_cmd=
  local user_cmd="`eval echo '$USER_CMD_'\"$cmd\"`"
  
  log_start "checking for $cmd...	"
  
  if test "$user_cmd" != ""; then
    my_cmd="`$my_cmd_which \"$user_cmd\"`" >/dev/null 2>&1
    if test "$my_cmd" != ""; then
      if test -x "$my_cmd"; then
        log_end "'$my_cmd' ('$user_cmd' was specified)"
        eval "CMD_$cmd=\"$my_cmd\""
        return 0
      fi
    fi
  fi

  my_cmd="`$my_cmd_which \"$cmd\"`" >/dev/null 2>&1
  if test "$my_cmd" != ""; then
    if test -x "$my_cmd"; then
      log_end "'$my_cmd'"
      eval "CMD_$cmd=\"$my_cmd\""
      return 0
   else
      log_end "found '$my_cmd', but is NOT executable by you!"
    fi
  else
    log_end "NOT FOUND!"
  fi
  CMDS_missing="$CMDS_missing '$cmd'"
  return 1
}

detect_cmd_dual() {
  local my_cmd_which="$CMD_which"
  if test "$my_cmd_which" = ""; then
    my_cmd_which="$BOOT_CMD_which"
  fi
  
  local cmd="$1"
  local source_or_target="$2"
  
  local user_cmd="`eval echo '$USER_CMD_'\"$cmd\"'_'\"$source_or_target\"`"
  local my_cmd=
  log_start "checking for ${cmd}($source_or_target filesystem)...	"

  if test "$user_cmd" != ""; then
    my_cmd="`$my_cmd_which \"$user_cmd\"`" >/dev/null 2>&1
    if test "$my_cmd" != ""; then
      if test -x "$my_cmd"; then
        log_end "'$my_cmd' ('$user_cmd' was specified)"
        eval "CMD_${cmd}_$source_or_target=\"$my_cmd\""
        return 0
      fi
    fi
  fi
  local nondual_cmd="`eval echo '$CMD_'\"$cmd\"`"
  log_end "'$nondual_cmd'"
  eval "CMD_${cmd}_$source_or_target=\"$nondual_cmd\""
  return 0
}

# apply fixes for special cases...
fix_for_special_cases() {
  if test "$DEVICE_FSTYPE" = "ntfs-3g"; then
    DEVICE_FSTYPE="ntfs"
  fi
  if test "$FSTYPE" = "ntfs-3g"; then
    FSTYPE="ntfs"
  fi
  local my_cmd_ntfsresize=
  if test "$FSTYPE" = "ntfs" -o "$DEVICE_FSTYPE" = "ntfs"; then
    log_info "applying special options for filesystem type '$FSTYPE'"
    # we need 'ntfsresize', check if it's available
    my_cmd_ntfsresize="`$CMD_which ntfsresize`"
    if test "$my_cmd_ntfsresize" = ""; then
      log_warn "command 'ntfsresize' not found, it is needed to check integrity of filesystem type 'ntfs'"
    fi
  fi
  
  if test "$DEVICE_FSTYPE" = "ntfs"; then
    if test "$my_cmd_ntfsresize" != "" -a "$USER_CMD_fsck_source" = ""; then
      USER_CMD_fsck_source="ntfsresize"
      OPTS_fsck_source="-n"
      detect_cmd_dual "fsck" "source"
    fi
  fi
  if test "$FSTYPE" = "ntfs"; then
    if test "$my_cmd_ntfsresize" != "" -a "$USER_CMD_fsck_target" = ""; then
      USER_CMD_fsck_target="ntfsresize"
      OPTS_fsck_target="-n"
      detect_cmd_dual "fsck" "target"
    fi
    # 'mkfs -t nfs' needs option '-f' (quick format) to maintain sparse files
    OPTS_mkfs="$OPTS_mkfs -f"
  fi
}

fail_missing_cmds() {
  log_err "environment check failed."
  log_err_add "Please install the commands$CMDS_missing before running fstransform.sh"
  log_err_add "If these commands are already installed, add them to your \$PATH"
  log_err_add "or tell their location with the option --cmd-COMMAND=/path/to/your/command"
  exit "$ERR"
}





# bootstrap command detection (command 'which') and argument parsing (command 'expr')
for cmd in $CMDS_bootstrap; do
  detect_cmd "$cmd" || ERR="$?"
done
if test "$ERR" != 0; then
  fail_missing_cmds
fi

check_uid_0() {
  UID="`$CMD_id -u`"
  if test "$UID" != 0; then
    log_err "this script must be executed as root (uid 0)"
    log_err_add "instead it is currently running as uid $UID"
    exit 1
  fi
}
check_uid_0


parse_args "$@"

for cmd in $CMDS; do
  detect_cmd "$cmd" || ERR="$?"
done

for cmd in $CMDS_dual; do
  detect_cmd_dual "$cmd" "source" || ERR="$?"
  detect_cmd_dual "$cmd" "target" || ERR="$?"
done

fix_for_special_cases

if test "$ERR" != 0; then
  fail_missing_cmds
fi

log_info "environment check passed."

check_command_line_args() {
  if test "$DEVICE" = ""; then
    if test "$FSTYPE" = ""; then
      log_err "missing command-line arguments DEVICE and FSTYPE"
    else
      log_err "missing command-line argument DEVICE"
    fi
    exit 1
  fi
  if test "$FSTYPE" = ""; then
    log_err "missing command-line argument FSTYPE"
    exit 1
  fi
}
check_command_line_args

append_to_log_file

read_user_answer() {
  read USER_ANSWER
}

# inform if a command failed, and offer to fix manually
exec_cmd_status() {
  if test "$ERR" != 0; then
    log_err "command '$@' failed (exit status $ERR)"
    log_err_add "this is potentially a problem."
    log_err_add "you can either quit now by pressing ENTER or CTRL+C,"
    log_err_add
    log_err_add "or, if you know what went wrong, you can fix it yourself,"
    log_err_add "then manually run the command '$@'"
    log_err_add "(or something equivalent)"
    log_err_add_prompt "and finally resume this script by typing CONTINUE and pressing ENTER: "
    read_user_answer
    if test "$USER_ANSWER" != "CONTINUE"; then
      log_info 'exiting.'
      exit "$ERR"
    fi
    ERR=0
  fi
}


remove_fifo_out_err() {
  "$CMD_rm" -f "$FIFO_OUT" "$FIFO_ERR"
}

create_fifo_out_err() {
  remove_fifo_out_err
  "$CMD_mkfifo" -m 600 "$FIFO_OUT" "$FIFO_ERR"
  ERR="$?"
  exec_cmd_status "$CMD_mkfifo" -m 600 "$FIFO_OUT" "$FIFO_ERR"
}
create_fifo_out_err


trap remove_fifo_out_err 0

read_cmd_out_err() {
  local my_cmd_full="$1"
  local my_cmd="`$CMD_expr match \"$1\" '.*/\([^/]*\)'`"
  if test "$my_cmd" = ""; then
    my_cmd="$my_cmd_full"
  fi
  local my_fifo="$2"
  local my_prefix="$3"
  local my_out_1= my_out=
  while read my_out_1 my_out; do
    if test "$my_out_1" = "$my_cmd:"; then
      log_info_4_cmd "$my_prefix$my_cmd: $my_out"
    elif test "$my_out_1" = "$my_cmd_full:"; then
      log_info_4_cmd "$my_prefix$my_cmd: $my_out"
    else
      log_info_4_cmd "$my_prefix$my_cmd: $my_out_1 $my_out"
    fi
  done < "$my_fifo" &
}

read_cmd_out() {
  read_cmd_out_err "$1" "$FIFO_OUT" ""
}

read_cmd_err() {
  read_cmd_out_err "$1" "$FIFO_ERR" "warn: "
}

exec_cmd() {
  read_cmd_out "$1"
  "$@" >"$FIFO_OUT" 2>"$FIFO_OUT"
  ERR="$?"
  wait
  exec_cmd_status "$@"
}

capture_cmd() {
  local my_ret my_var="$1"
  shift
  read_cmd_out "$1"
  my_ret="`\"$@\" 2>\"$FIFO_OUT\"`"
  ERR="$?"
  wait
  if test "$ERR" != 0; then
    log_err "command '$@' failed (exit status $ERR)"
    exit "$ERR"
  elif test "$my_ret" = ""; then
    log_err "command '$@' failed (no output)"
    exit 1
  fi
  eval "$my_var=\"$my_ret\""
}




log_info "preparing to transform device '$DEVICE' to filesystem type '$FSTYPE'"


capture_cmd DEVICE_SIZE_IN_BYTES "$CMD_blockdev" --getsize64 "$DEVICE"
log_info "detected '$DEVICE' size: $DEVICE_SIZE_IN_BYTES bytes"

echo_device_mount_point_and_fstype() {
  local my_dev="$1"
  "$CMD_mount" | while read dev _on_ mount_point _type_ fstype opts; do
    if test "$dev" = "$my_dev"; then
      echo "$mount_point $fstype"
      break
    fi
  done
}

find_device_mount_point_and_fstype() {
  local my_dev="$DEVICE"
  local ret="`echo_device_mount_point_and_fstype \"$my_dev\"`"
  if test "$ret" = ""; then
    log_err "device '$my_dev' not found in the output of command $CMD_mount"
    log_err_add "maybe device '$my_dev' is not mounted?"
    exit 1
  fi
  local my_mount_point= my_fstype=
  for i in $ret; do
    if test "$my_mount_point" = ""; then
      my_mount_point="$i"
    else
      my_fstype="$i"
    fi
  done
  log_info "detected '$my_dev' mount point '$my_mount_point' with filesystem type '$my_fstype'"
  if test ! -e "$my_mount_point"; then
    log_err "mount point '$my_mount_point' does not exist."
    log_err_add "maybe device '$my_dev' is mounted on a path containing spaces?"
    log_err_add "fstransform.sh does not support mount points containing spaces in their path"
    exit 1
  fi
  if test ! -d "$my_mount_point"; then
    log_err "mount point '$my_mount_point' is not a directory"
    exit 1
  fi
  DEVICE_MOUNT_POINT="$my_mount_point"
  if test "$my_fstype" = fuseblk; then
    if test "$DEVICE_FSTYPE" != ""; then
      log_info "filesystem type '$my_fstype' is a placeholder name for FUSE... ignoring it (user specified type '$DEVICE_FSTYPE')"
    else
      log_info "filesystem type '$my_fstype' is a placeholder name for FUSE... ignoring it"
    fi
  elif test "$DEVICE_FSTYPE" != ""; then
    # let's compare user-specified filesystem type with what we found...
    # still we honour what the user said.
    if test "$DEVICE_FSTYPE" != "$my_fstype"; then
      log_warn "does not match user-specified device filesystem type '$DEVICE_FSTYPE'. using user-specified value."
    fi
  else
    DEVICE_FSTYPE="$my_fstype"
  fi
}
find_device_mount_point_and_fstype


create_loop_or_zero_file() {
  local my_kind="$1" my_var="$2" my_file="$3"
  local my_pattern="$DEVICE_MOUNT_POINT/.fstransform.$my_kind.*"
  local my_files="`echo $my_pattern`"
  if test "$my_files" != "$my_pattern"; then
    log_warn "possibly stale fstransform $my_kind files found inside device '$DEVICE',"
    log_warn_add "maybe they can be removed? list of files found:"
    log_warn_add
    log_warn_add "$my_files"
    log_warn_add
  fi
  if test "$my_file" = ""; then
    my_file="$DEVICE_MOUNT_POINT/.fstransform.$my_kind.$$"
    log_info "creating sparse $my_kind file '$my_file' inside device '$DEVICE'..."
    if test -e "$my_file"; then
      log_err "$my_kind file '$my_file' already exists! please remove it"
      exit 1
    fi
  else
    # check that user-specified file is actually inside DEVICE_MOUNT_POINT
    "$CMD_expr" match "$my_file" "$DEVICE_MOUNT_POINT/.*" >/dev/null 2>/dev/null || ERR="$?"
    if test "$ERR" != 0; then
      log_err "user-specified $my_kind file '$my_file' does not seem to be inside device mount point '$DEVICE_MOUNT_POINT'"
      log_err_add "please use a $my_kind file path that starts with '$DEVICE_MOUNT_POINT/'"
      exit "$ERR"
    fi
    "$CMD_expr" match "$my_file" '.*/\.\./.*' >/dev/null 2>/dev/null
    if test "$?" = 0; then
      log_err "user-specified $my_kind file '$my_var' contains '/../' in path"
      log_err_add "maybe somebody is trying to break fstransform?"
      log_err_add "I give up, sorry"
      exit "$ERR"
    fi
    log_info "overwriting $my_kind file '$my_file' inside device '$DEVICE'..."
  fi
  
  read_cmd_out "$PROG"
  > "$my_file" 2>"$FIFO_OUT"
  ERR="$?"
  wait
  if test "$ERR" != 0; then
    log_err "failed to create or truncate '$my_file' to zero bytes"
    log_err_add "maybe device '$DEVICE' is full or mounted read-only?"
    exit "$ERR"
  fi
  eval "$my_var=\"$my_file\""
}

create_loop_file() {
  create_loop_or_zero_file loop LOOP_FILE "$LOOP_FILE"
  exec_cmd "$CMD_dd" if=/dev/zero of="$LOOP_FILE" bs=1 count=1 seek="`\"$CMD_expr\" \"$DEVICE_SIZE_IN_BYTES\" - 1`" >/dev/null 2>/dev/null
}
create_loop_file


connect_loop_device() {
  capture_cmd LOOP_DEVICE "$CMD_losetup" -f
  exec_cmd "$CMD_losetup" "$LOOP_DEVICE" "$LOOP_FILE"
  log_info "connected loop device '$LOOP_DEVICE' to file '$LOOP_FILE'"
}
connect_loop_device

disconnect_loop_device() {
  local my_iter=0
  # loop device sometimes needs a little time to become free...
  for my_iter in 1 2 3 4; do
    exec_cmd "$CMD_sync"
    if test "$my_iter" -le 3; then
      "$CMD_losetup" -d "$LOOP_DEVICE" && break
    else
      exec_cmd "$CMD_losetup" -d "$LOOP_DEVICE"
    fi
  done
  log_info "disconnected loop device '$LOOP_DEVICE' from file '$LOOP_FILE'"
}


format_loop_device() {
  log_info "formatting loop device '$LOOP_DEVICE' with filesystem type '$FSTYPE'..."
  exec_cmd "$CMD_mkfs" -t "$FSTYPE" -q $OPTS_mkfs "$LOOP_DEVICE"
}
format_loop_device


mount_loop_file() {
  if test "$LOOP_MOUNT_POINT" = ""; then
    LOOP_MOUNT_POINT="/tmp/fstransform.mount.$$"
    exec_cmd "$CMD_mkdir" "$LOOP_MOUNT_POINT"    
  else
    "$CMD_expr" match "$LOOP_MOUNT_POINT" "/.*" >/dev/null 2>/dev/null
    if test "$?" != 0; then
      log_warn "user-specified loop file mount point '$LOOP_MOUNT_POINT' should start with '/'"
      log_warn_add "i.e. it should be an absolute path."
      log_warn_add "fstransform cannot ensure that '$LOOP_MOUNT_POINT' is outside '$DEVICE_MOUNT_POINT'"
      log_warn_add "continue at your own risk"
      log_warn_add
      log_warn_add_prompt "press ENTER to continue, or CTRL+C to quit: "
      read_user_answer
    else
      "$CMD_expr" match "$LOOP_MOUNT_POINT" "$DEVICE_MOUNT_POINT/.*" >/dev/null 2>/dev/null
      if test "$?" = 0; then
        log_err "user-specified loop file mount point '$LOOP_MOUNT_POINT' seems to be inside '$DEVICE_MOUNT_POINT'"
	log_err_add "maybe somebody is trying to break fstransform and lose data?"
	log_err_add "I give up, sorry"
	exit 1
      fi
    fi
  fi
  log_info "mounting loop device '$LOOP_DEVICE' on '$LOOP_MOUNT_POINT' ..."
  exec_cmd "$CMD_mount" -t "$FSTYPE" "$LOOP_DEVICE" "$LOOP_MOUNT_POINT"
  log_info "loop device '$LOOP_DEVICE' mounted successfully."
}
mount_loop_file


move_device_contents_into_loop_file() {
  log_info "preliminary steps completed, now comes the delicate part:"
  log_info "fstransform will move '$DEVICE' contents into the loop file."
  
  log_warn "THIS IS IMPORTANT! if either the original device '$DEVICE'"
  log_warn_add "or the loop device '$LOOP_DEVICE' become FULL,"
  log_warn_add
  log_warn_add " YOU  WILL  LOSE  YOUR  DATA !"
  log_warn_add
  log_warn_add "please open another terminal, type"
  log_warn_add "'watch df $DEVICE $LOOP_DEVICE'"
  log_warn_add "and check that both the original device '$DEVICE'"
  log_warn_add "and the loop device '$LOOP_DEVICE' are NOT becoming full."
  log_warn_add
  log_warn_add "if one of them is almost full,"
  log_warn_add "you MUST stop fstransform.sh with CTRL+C or equivalent."
  log_warn_add
  log_warn_add "this is your chance to quit."
  log_warn_add_prompt "press ENTER to continue, or CTRL+C to quit: "
  read_user_answer
  
  log_info "moving '$DEVICE' contents into the loop file."
  log_info "this may take a long time, please be patient..."
  exec_cmd "$CMD_fsmove" $OPTS_fsmove -- "$DEVICE_MOUNT_POINT" "$LOOP_MOUNT_POINT" --exclude "$LOOP_FILE"
}
move_device_contents_into_loop_file

umount_and_fsck_loop_file() {
  log_info "unmounting and running '$CMD_fsck_target' (disk check) on loop file '$LOOP_FILE'"
  exec_cmd "$CMD_umount" "$LOOP_DEVICE"
  # ignore errors if removing "$LOOP_MOUNT_POINT" fails
  "$CMD_rmdir" "$LOOP_MOUNT_POINT" >/dev/null 2>/dev/null
  exec_cmd "$CMD_fsck_target" $OPTS_fsck_target "$LOOP_DEVICE"
  exec_cmd "$CMD_sync"

  if test "$X_COPY_LOOP_FILE" != ""; then
    log_info "(internal option) copying loop file '$LOOP_FILE' to '$X_COPY_LOOP_FILE'"
    exec_cmd "$CMD_dd" bs=64k if="$LOOP_DEVICE" of="$X_COPY_LOOP_FILE"
  fi
}
umount_and_fsck_loop_file

disconnect_loop_device

create_zero_file() {
  create_loop_or_zero_file zero ZERO_FILE "$ZERO_FILE"
  log_info "filling '$ZERO_FILE' with zeroes until device '$DEVICE' is full"
  log_info_add "needed by '$CMD_fsremap' to locate unused space."
  log_info_add "this may take a while, please be patient..."
  
  # trying to fill a device until it fails with "no space left on device" is not very nice
  # and can probably cause filesystem corruption if device happens to be a loop-mounted file
  # which contains non-synced data.
  # to be safe, we 'sync' BEFORE and AFTER filling the device
  exec_cmd "$CMD_sync"

  # next command will fail with "no space left on device".
  # this is normal and expected.
  "$CMD_dd" if=/dev/zero of="$ZERO_FILE" bs=64k >/dev/null 2>/dev/null
  
  exec_cmd "$CMD_sync"
  log_info "file full of zeroes created successfully"
}
create_zero_file

remount_device_ro_and_fsck() {
  #log_info "remounting device '$DEVICE' read-only"
  #exec_cmd "$CMD_mount" "$DEVICE" -o remount,ro
  #exec_cmd "$CMD_sync"

  # cannot safely perform disk check on a mounted device... it must be unmounted first!
  log_info "unmounting device '$DEVICE' before disk check"
  exec_cmd "$CMD_umount" "$DEVICE"
  log_info "running '$CMD_fsck_source' (disk check) on device '$DEVICE'"
  exec_cmd "$CMD_fsck_source" $OPTS_fsck_source "$DEVICE"
  exec_cmd "$CMD_sync"
  
  if test "$X_COPY_DEVICE" != ""; then
    log_info "(internal option) copying device '$DEVICE' to '$X_COPY_DEVICE'"
    exec_cmd "$CMD_dd" bs=64k if="$DEVICE" of="$X_COPY_DEVICE"
  fi
  
  log_info "mounting again device '$DEVICE' read-only"
  if test "$DEVICE_FSTYPE" != ""; then
    exec_cmd "$CMD_mount" -t "$DEVICE_FSTYPE" "$DEVICE" "$DEVICE_MOUNT_POINT" -o ro
  else
    exec_cmd "$CMD_mount" "$DEVICE" "$DEVICE_MOUNT_POINT" -o ro
  fi
}
remount_device_ro_and_fsck


remap_device_and_sync() {
  log_info "launching '$CMD_fsremap' in simulated mode"
  exec_cmd "$CMD_fsremap" -n -q $OPTS_fsremap -- "$DEVICE" "$LOOP_FILE" "$ZERO_FILE"
  
  log_info "launching '$CMD_fsremap' in REAL mode to perform in-place remapping."
  exec_cmd "$CMD_fsremap" -q $OPTS_fsremap -- "$DEVICE" "$LOOP_FILE" "$ZERO_FILE"
  exec_cmd "$CMD_sync"
  

  if test "$X_COPY_LOOP_FILE" != ""; then
    log_info "(internal option) comparing transformed device '$DEVICE' with previously saved loop file '$X_COPY_LOOP_FILE'"
    exec_cmd "$CMD_cmp" "$X_COPY_LOOP_FILE" "$DEVICE"
  fi
}
remap_device_and_sync

fsck_device() {
  log_info "running again '$CMD_fsck_target' (disk check) on device '$DEVICE'"
  exec_cmd "$CMD_fsck_target" $OPTS_fsck_target "$DEVICE"
}
fsck_device

mount_device() {
  log_info "mounting transformed device '$DEVICE'"
  exec_cmd "$CMD_mount" -t "$FSTYPE" "$DEVICE" "$DEVICE_MOUNT_POINT"
}
mount_device

log_info "completed successfully. your new '$FSTYPE' filesystem is mounted at '$DEVICE_MOUNT_POINT'"