set -e

trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT SIGHUP ERR

# windows cmd-like GOTO function 
function jumpto
{
    label=$1
    cmd=$(sed -n "/$label:/{:a;n;p;ba};" $0 | grep -v ':$')
    eval "$cmd"
    exit
}

function createOutputFile
{
  
  # Create video from output images.
  mkdir -p Out

  echo ""
  echo ""
  echo "Creating video from video sequence"
  echo ""
  stylename=$(basename "${style_image%.*}")
  $FFMPEG -i ./inProgress/${filename}/${filename}_[${num_iterations}]_$resolution/out-%04d_$num_passes.png -loglevel 'error' -framerate $framerate Out/${filename}-stylized-${stylename}_mp.$extension
  echo ""
}


# Save frames of the video as individual image files
function convertToSeq {
  echo ""
  echo "Converting video to frame sequence in background..."

  if [ "$FFMPEG" == "ffmpeg" ]; then
    framerate=$($FFMPEG ffmpeg -i filename 2>&1 | sed -n "s/.*, \(.*\) fp.*/\1/p")
  fi
  framerate=${framerate:-30}

  if [ $resolution == "original" ]; then
    $FFMPEG -i $filepath -loglevel 'error' inProgress/${filename}/frame_%04d.png &
  else
    $FFMPEG -i $filepath -vf scale=$resolution:-1 -loglevel 'error' inProgress/${filename}/frame_%04d.png &
  fi
}

# Parse arguments
function parseArguments
{
  filepath=$1
  filename=$(basename "$1")
  extension="${filename##*.}"
  filename="${filename%.*}"
  filename=${filename//[%]/x}
  style_image=$2
}

function makeDirs
{
  mkdir -p inProgress
  mkdir -p ./inProgress/$filename
  if [ ! "$1" == "0" ]; then mkdir -p ./inProgress/${filename}/${filename}_[${num_iterations}]_$resolution; fi;
}

# Parsing last state
function parseLastState
{
  laststate=./inProgress/$(basename "${1%.*}")_$(basename "${2%.*}")_multipass_laststate.txt
}

# Default values
function defaultValues
{
backend=cudnn
gpu=0
style_weight=1000
resolution=original
num_iterations=66
style_scale=1.0
pooling=1
init=1
need_flow=1
opt_res=1
flow_relative_indices=1
temporal_weight=1e3
continue_with_pass=1
weight_tv=0.0005
num_passes=15
original_colors=0
timer=1200
seed=1
}

# Get a carriage return into `cr`
function setCr
{
cr=`echo $'\n.'`
cr=${cr%.}
}
setCr

# change bash relative path to script location
SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
cd $SCRIPTPATH


# Find out whether ffmpeg or avconv is installed on the system
FFMPEG=ffmpeg
command -v $FFMPEG >/dev/null 2>&1 || {
  FFMPEG=avconv
  command -v $FFMPEG >/dev/null 2>&1 || {
    echo >&2 "This script requires either ffmpeg or avconv installed.  Aborting."; exit 1;
  }
}


# Parsing input parameters file

# txt is 3 argument
if [[ ! -z "$3" ]]; then
  defaultValues
  source $3
  parseArguments $1 $2
  makeDirs
  convertToSeq $1
  sleep 2
  sleep `echo $flow_relative_indices  | head -n1 | cut -d "," -f1`
  jumpto startComputing
fi

# txt is 2 argument
if [[ "`echo "$2" | cut -d'.' -f2`" == "txt" ]]; then
  defaultValues
  parseArguments $1
  source $2
  if [[ -z "$style_image" ]]; then echo "No \"style_image\" parameter in $(basename "${2%}") file. Aborting.";  exit 1; fi;
  makeDirs
  convertToSeq $2
  sleep 2
  sleep `echo $flow_relative_indices  | head -n1 | cut -d "," -f1`
  parseLastState $filepath $style_image
  jumpto startComputing
fi

# txt is 1 argument
if [[ "`echo "$1" | cut -d'.' -f2`" == "txt" ]]; then
  defaultValues
  source $1
  if [[ -z "$style_image" ]]; then echo "No \"style_image\" parameter in $(basename "${1%}") file. Aborting.";  exit 1; fi;
  if [[ -z "$filepath" ]]; then echo "No \"filepath\" parameter in $(basename "${1%}") file. Aborting.";  exit 1; fi;
  makeDirs
  convertToSeq $1
  sleep 2
  sleep `echo $flow_relative_indices  | head -n1 | cut -d "," -f1`
  parseLastState $filepath $style_image
  jumpto startComputing
fi

if [ "$#" -le 1 ]; then
   echo "Usage:"
   echo "./stylizeVideo.sh <path_to_video> <path_to_style_image>"
   echo "./stylizeVideo.sh <path_to_video> <path_to_style_image> <path_to_parameters>.txt"
   echo "./stylizeVideo.sh <path_to_video> <path_to_parameters>.txt"
   echo "./stylizeVideo.sh <path_to_parameters>.txt"
   exit 1
fi


# Default values
defaultValues

# Parsing last state
parseLastState $1 $2



if [ -a "$laststate" ]; then
  source <(grep -E 'filepath|style_image' "$laststate" | tr " " "\n")
fi

if [ "$filepath" == "$1" ] && [ "$style_image" = "$2" ]; then
  echo ""
  echo ""
  read -p "Do you want to load previously entered parametres for \"$(basename "${1%.*}")\" and \"$(basename "${2%.*}")\"?  0 - no, 1 - yes, 2 - yes, jump to processing now. [0] $cr > " previousload
previousload=${previousload:-0}
  if [ "$previousload" == "2" ]; then
    source $laststate
    makeDirs
    jumpto startComputing
  fi
  if [ "$previousload" == "1" ]; then
    source $laststate
  fi
fi  


parseArguments $1 $2

# Create output folder
makeDirs 0


echo ""
read -p "Which backend do you want to use? \
For Nvidia GPU, use cudnn if available, otherwise nn on CPU. \
For non-Nvidia GPU, use clnn. Note: You have to have the given backend installed in order to use it. [$backend] $cr > " readtmp
if [[ ! -z "$readtmp" ]]; then backend=$readtmp; unset readtmp; fi;

if [ "$backend" == "cudnn" ] || [ "$backend" = "clnn" ]; then
  echo ""
  read -p "Please enter a resolution width at which the video should be processed, or leave blank to use [$resolution] resolution $cr > " readtmp
if [[ ! -z "$readtmp" ]]; then resolution=$readtmp; unset readtmp; fi;
elif [ "$backend" = "nn" ]; then
  gpu="-1"
  echo ""
  read -p "Please enter a resolution width at which the video should be processed, or leave blank to use [$resolution] resolution $cr > " readtmp
if [[ ! -z "$readtmp" ]]; then resolution=$readtmp; unset readtmp; fi;
else
  echo "Unknown backend."
  exit 1
fi


# Save frames of the video as individual image files
convertToSeq $1

echo ""
  read -p "On which gpu do you want to compute? -1 for CPU. \
[$gpu] $cr > "  readtmp 
if [[ ! -z "$readtmp" ]]; then gpu=$readtmp; unset readtmp; fi;

echo ""
read -p "How much do you want to weight the style reconstruction term? \
[$style_weight] $cr > " readtmp
if [[ ! -z "$readtmp" ]]; then style_weight=$readtmp; unset readtmp; fi;


echo ""
read -p "How much iterations do you want? \
[$num_iterations] $cr > " readtmp
if [[ ! -z "$readtmp" ]]; then num_iterations=$readtmp; unset readtmp; fi;

echo ""
read -p "How much passes do you want? \
[$num_passes] $cr > " readtmp
if [[ ! -z "$readtmp" ]]; then num_passes=$readtmp; unset readtmp; fi;

echo ""
read -p "What style size do you want? \
[$style_scale] $cr > " readtmp 
if [[ ! -z "$readtmp" ]]; then style_scale=$readtmp; unset readtmp; fi;

echo ""
read -p "What pooling do you want? avg - 0, max - 1 \
[$pooling] $cr > " readtmp 
if [[ ! -z "$readtmp" ]]; then pooling=$readtmp; unset readtmp; fi;


if [ "$pooling" == "1" ]; then
  pooling=max
  weight_tv=0.0005
fi
if [ "$pooling" == "0" ]; then
  pooling=avg
  weight_tv=0
fi

echo ""
read -p "What init do you want? random - 0, image - 1, prevWarped - 2 \
[$init] $cr > " readtmp 
if [[ ! -z "$readtmp" ]]; then init=$readtmp; unset readtmp; fi;


if [ "$init" == "1" ]; then
  init=image
fi
if [ "$init" == "0" ]; then
  init=random
fi
if [ "$init" == "2" ]; then
  init=prevWarped
fi


echo ""
read -p "Compute optical flow? 1 - yes, 0 - no \
[$need_flow] $cr > " readtmp 
if [[ ! -z "$readtmp" ]]; then need_flow=$readtmp; unset readtmp; fi;

makeDirs

if [ "$need_flow" == "1" ]; then
  echo ""
  read -p "Which resolution downscaling do you want for optical flow? Value is in 2^n \
[$opt_res] $cr > " readtmp 
  if [[ ! -z "$readtmp" ]]; then opt_res=$readtmp; unset readtmp; fi;
fi

jumpto startComputingNormal
startComputing:
startComputingNormal:

# save current parameters
unset cr
unset cmd
unset label
unset readtmp

compgen -v | while read var; do echo "$var"="\"${!var}\"" ; done | sed '/^[A-Z[:punct:]]/d' > $laststate

setCr

# copy current parameters
yes | cp -rf $laststate ./inProgress/${filename}/${filename}_[${num_iterations}]_$resolution/run_parameters.txt

# find last file in out directory
dir=inProgress/${filename}/${filename}_[${num_iterations}]_${resolution}
unset -v latest
for file in "$dir"/*.png; do
  [[ $file -nt $latest ]] && latest=$file
done
lastfoundindex=`echo $latest | grep -o '[0-9:]*' | tail -1 | sed 's/^0*//'`
lastfoundindex=${lastfoundindex:-0}

lastfoundindex2=`echo $latest | grep -o '[0-9:]*' | tail -2 | sed 's/^0*//' | head -1`
lastfoundindex2=${lastfoundindex2:-0}


# find last file number of input sequence
dir=inProgress/${filename}
unset -v latest
for file in "$dir"/*.png; do
  if [[ `echo $file | grep -o '[0-9:]*' | tail -1 | sed 's/^0*//'` -gt `echo $latest | grep -o '[0-9:]*' | tail -1 | sed 's/^0*//'` ]]; then latest=$file; fi;
done
lastfoundinputindex=`echo $latest | grep -o '[0-9:]*' | tail -1 | sed 's/^0*//'`
lastfoundinputindex=${lastfoundinputindex:-0}


# if last processing is found
if [ "$lastfoundindex" -gt 1 ]; then
  if [[ "$lastfoundindex" == "$num_passes"  &&  "$lastfoundinputindex" == "$lastfoundindex2" ]]; then 
    echo ""
    echo Found, that previous multi-pass calculations already finished.
    read -p "Do you want to start process with the begining? 1 - yes, 0 - no \
[1] $cr > " readtmp 
    if [[ -z "$readtmp" ]]; then readtmp=1; fi;
    if [ "$readtmp" == 1 ]; then
      continue_with_pass=1
    else 
      exit 1
    fi
    unset readtmp
  else   
    echo ""
    echo Found, that previous multi-pass calculations stopped at pass $lastfoundindex
    read -p "Do you want to continue from last found state? 1 - yes, 0 - no \
[$continue_with_pass] $cr > " readtmp 
    if [[ ! -z "$readtmp" ]]; then continue_with_pass=$readtmp; unset readtmp; fi;
    if [ "$continue_with_pass" == 0 ]; then
      continue_with_pass=1
    else 
      continue_with_pass=$lastfoundindex
    fi
  fi
else
  continue_with_pass=1
fi  


if [ "$need_flow" == "1" ]; then
  echo ""
  echo "Computing optical flow in low-priority in background..."
  echo 
  bash makeOptFlow.sh ./inProgress/${filename}/frame_%04d.png ./inProgress/${filename}/flow_$resolution 1 $flow_relative_indices $opt_res &
fi

echo ""
echo ""
echo "Performing style transfer in foreground"
echo ""
echo ""

# Perform style transfer

performStarted=1

th artistic_video_multiPass.lua \
-content_pattern inProgress/${filename}/frame_%04d.png \
-backwardFlow_pattern inProgress/${filename}/flow_${resolution}/backward_[%d]_{%d}.flo \
-backwardFlow_weight_pattern inProgress/${filename}/flow_${resolution}/reliable_[%d]_{%d}.pgm \
-forwardFlow_pattern inProgress/${filename}/flow_${resolution}/forward_[%d]_{%d}.flo \
-forwardFlow_weight_pattern inProgress/${filename}/flow_${resolution}/reliable_[%d]_{%d}.pgm \
-style_weight $style_weight \
-output_folder ./inProgress/${filename}/${filename}_[${num_iterations}]_$resolution/ \
-style_image $style_image \
-backend $backend \
-gpu $gpu \
-num_iterations $num_iterations \
-style_scale $style_scale \
-cudnn_autotune \
-number_format %04d \
-tv_weight $weight_tv \
-init $init \
-temporal_weight $temporal_weight \
-original_colors $original_colors \
-timer $timer \
-seed $seed \
-continue_with_pass $continue_with_pass \
-num_passes $num_passes \
-pooling $pooling
  
createOutputFile
#rm -f $laststate
