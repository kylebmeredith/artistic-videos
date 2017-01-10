set -e
function termination {
  echo ""
  echo "  Processing terminated!"
  echo ""
  trap - SIGTERM && kill -- -$$
}
trap termination SIGINT SIGTERM SIGHUP ERR


# Get a carriage return into `cr`
cr=`echo $'\n.'`
cr=${cr%.}



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

if [ "$#" -le 1 ]; then
   echo "Usage: ./stylizeVideo <path_to_video> <path_to_style_image>"
   exit 1
fi

# Parse arguments
filename=$(basename "$1")
extension="${filename##*.}"
filename="${filename%.*}"
filename=${filename//[%]/x}
style_image=$2

# Create output folder
mkdir -p $filename


echo ""
read -p "Which backend do you want to use? \
For Nvidia GPU, use cudnn if available, otherwise nn on CPU. \
For non-Nvidia GPU, use clnn. Note: You have to have the given backend installed in order to use it. [cudnn] $cr > " backend
backend=${backend:-cudnn}

if [ "$backend" == "cudnn" ] || [ "$backend" = "clnn" ]; then
  gpu="0"
  echo ""
  read -p "Please enter a resolution width at which the video should be processed, or leave blank to use the original resolution $cr > " resolution
elif [ "$backend" = "nn" ]; then
  gpu="-1"
  echo ""
read -p "Please enter a resolution width at which the video should be processed, or leave blank to use the original resolution $cr > " resolution
else
  echo "Unknown backend."
  exit 1
fi

# Save frames of the video as individual image files

echo ""
echo "Converting video to frame sequence..."

if [ "$FFMPEG" == "ffmpeg" ]; then
framerate=$($FFMPEG ffmpeg -i filename 2>&1 | sed -n "s/.*, \(.*\) fp.*/\1/p")
fi
framerate=${framerate:-30}

if [ -z $resolution ]; then
  $FFMPEG -i $1 -loglevel 'warning' ${filename}/frame_%04d.png
  resolution=default
else
  $FFMPEG -i $1 -vf scale=$resolution:-1 -loglevel 'warning' ${filename}/frame_%04d.png
fi


echo ""
read -p "How much do you want to weight the style reconstruction term? \
[1000] $cr > " style_weight
style_weight=${style_weight:-1000}

temporal_weight=1e3 #1e3 default


echo ""
read -p "How much iterations do you want? \
[2000,1000] $cr > " iters
iters=${iters:-2000,1000}

echo ""
read -p "What style size do you want? \
[1.0] $cr > " s_scale
s_scale=${s_scale:-1}

echo ""
read -p "What pooling do you want? avg - 0, max - 1 \
[1] $cr > " pooling
pooling=${pooling:-1}


if [ "$pooling" == "1" ]; then
  pooling=max
  weight_tv=0.001
else
  pooling=avg
  weight_tv=0
fi

echo ""
read -p "What init do you want? random - 0, image - 1 \
[1] $cr > " init_w
init_w=${init_w:-1}


if [ "$init_w" == "1" ]; then
  init_w=image
else
  init_w=random
fi


echo ""
read -p "Compute optical flow? 1 - yes, 0 - no \
[1] $cr > " need_flow
need_flow=${need_flow:-1}


if [ "$need_flow" == "1" ]; then
  echo ""
  read -p "Which resolution downscaling do you want for optical flow? Value is in 2^n \
  [1] $cr > " opt_res
  opt_res=${opt_res:-1}
  echo ""
  echo "Computing optical flow in low-priority in background..."
  nice bash makeOptFlow.sh ./${filename}/frame_%04d.png ./${filename}/flow_$resolution $opt_res &
fi


mkdir -p ./${filename}/${filename}_[${iters}]

echo ""
echo ""
echo "Performing style transfer in foreground"
echo ""
echo ""

# Perform style transfer


th artistic_video.lua \
-content_pattern ${filename}/frame_%04d.png \
-flow_pattern ${filename}/flow_${resolution}/backward_[%d]_{%d}.flo \
-flowWeight_pattern ${filename}/flow_${resolution}/reliable_[%d]_{%d}.pgm \
-style_weight $style_weight \
-output_folder ./${filename}/${filename}_[${iters}]/ \
-style_image $style_image \
-backend $backend \
-gpu $gpu \
-num_iterations $iters \
-style_scale $s_scale \
-cudnn_autotune \
-number_format %04d \
-tv_weight $weight_tv \
-init $init_w,prevWarped \
-temporal_weight 10 \
-original_colors 0 \
-timer 600 \
-pooling $pooling 

# Create video from output images.
mkdir -p Out
echo ""
echo ""
echo "Creating video from video sequence"
$FFMPEG -i ./${filename}/${filename}_[${iters}]/out-%04d.png -loglevel 'warning' -framerate $framerate Out/${filename}-stylized.$extension
echo ""
echo ""

