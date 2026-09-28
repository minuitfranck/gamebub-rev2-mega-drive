#!/bin/sh
# Simulate md_gamebub_core with tb_core.sv in the Vivado simulator.
# Usage: run_core.sh <rom file> <workdir> [xsim plusargs, no '=' ...]
#   e.g. run_core.sh "Comix Zone (USA).md" /tmp/md-core +frames200 +dump_from100 +dump_every20
# Needs Vivado's bin directory on PATH (xvlog, xvhdl, xelab, xsim). REBUILD=1
# recompiles. MD_ELAB points at the Chisel output that holds MdVideoCapture.sv
# (default <repo>/build/md-elab; regenerate with build_core.py or mill).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
RTL="${MD_RTL:-$HERE/../rtl}"
ELAB="${MD_ELAB:-$HERE/../../../../../build/md-elab}"
ROM="$1"; WORK="$2"; shift 2
mkdir -p "$WORK"
python "$HERE/../tools/gen_fx68k_roms.py" > /dev/null
python "$HERE/make_hex.py" "$ROM" "$WORK"
cd "$WORK"
DEFS="-d MD_NO_CHEATS -d MD_NO_SVP -d MD_NO_PIER"
if [ ! -f xsim.dir/tb_core_snap/xsimk.exe ] || [ -n "$REBUILD" ]; then
  xvhdl --relax "$RTL/xilinx/bram.vhd" "$RTL/vdp_common.vhd" "$RTL/vdp.vhd" \
        "$RTL/T80/T80_Reg.vhd" "$RTL/T80/T80_ALU.vhd" "$RTL/T80/T80_MCode.vhd" \
        "$RTL/T80/T80.vhd" "$RTL/T80/T80s.vhd" > xvhdl.log
  xvlog --relax "$RTL"/jt12/*.v "$RTL"/jt12/mixer/*.v "$RTL"/jt12/adpcm/*.v \
        "$RTL"/jt89/*.v "$RTL"/fourway.v "$RTL"/audio_iir_filter.v "$RTL"/genesis_lpf.v > xvlog_v.log
  xvlog --relax -sv $DEFS -i "$RTL/generated" \
        "$RTL"/system.sv "$RTL"/gen_io.sv "$RTL"/multitap.sv "$RTL"/teamplayer.sv \
        "$RTL"/FX68K/*.sv "$RTL"/gamebub/*.sv "$ELAB/MdVideoCapture.sv" "$HERE/tb_core.sv" > xvlog_sv.log
  xelab --relax -debug off -O3 tb_core -s tb_core_snap > xelab.log
fi
ARGS=$(cat cart.args)
xsim tb_core_snap -R $(for a in $ARGS "$@"; do printf -- '--testplusarg %s ' "${a#+}"; done) > xsim.log 2>&1 || true
tail -5 xsim.log
