# Specify the path to the optical flow utility here.
# Also check line 63 and 66 whether the arguments are in the correct order.
flowCommandLine="bash run-deepflow.sh"

if [ -z "$flowCommandLine" ]; then
  echo "Please open makeOptFlow.sh and specify the command line for computing the optical flow."
  exit 1
fi

if [ ! -f ./consistencyChecker/consistencyChecker ]; then
  if [ ! -f ./consistencyChecker/Makefile ]; then
    echo "Consistency checker makefile not found."
    exit 1
  fi
  cd consistencyChecker/
  make
  cd ..
fi

filePattern=$1
folderName=$2
startFrame=${3:-1}
stepSize=${4:-1}
opt_res=${5:-1}

old_IFS=$IFS
IFS=',' read -r -a stepSize <<< "$stepSize"

wait_for_file() {
   local filename=$1
   while [ ! -f "$filename" ]; do
   sleep 1
   done
}



if [ "$#" -le 1 ]; then
   echo "Usage: ./makeOptFlow <filePattern> <outputFolder> [<startNumber> [<stepSize>]]"
   echo -e "\tfilePattern:\tFilename pattern of the frames of the videos."
   echo -e "\toutputFolder:\tOutput folder."
   echo -e "\tstartNumber:\tThe index of the first frame. Default: 1"
   echo -e "\tstepSize:\tThe step size to create long-term flow. May be an array, similar to -flow_relative_indices parameter: 1,15,40 .Default: 1. "
   echo -e "\topt_res:\tResolution for optical flow. Default: 1"
   exit 1
fi


loopWork=1

i=$[$startFrame]

mkdir -p "${folderName}"

while [ $loopWork = 1 ]; do
  for step in "${stepSize[@]}"; do
    j=$[ $i - $step ]
    file1=$(printf "$filePattern" "$i")
    file2=$(printf "$filePattern" "$j")

    echo $file1
    echo $file2

    if [ -a $file2 ] && [ -a $file1 ]; then
      if [ ! -f ${folderName}/forward_${j}_${i}.flo ]; then
        eval $flowCommandLine "$file2" "$file1" "${folderName}/forward_${j}_${i}.flo" ${opt_res} &
      fi
      if [ ! -f ${folderName}/backward_${i}_${j}.flo ]; then
        eval $flowCommandLine "$file1" "$file2" "${folderName}/backward_${i}_${j}.flo" ${opt_res}
      fi
      wait_for_file "${folderName}/forward_${j}_${i}.flo"
      ./consistencyChecker/consistencyChecker "${folderName}/backward_${i}_${j}.flo" "${folderName}/forward_${j}_${i}.flo" "${folderName}/reliable_${i}_${j}.pgm"
      ./consistencyChecker/consistencyChecker "${folderName}/forward_${j}_${i}.flo" "${folderName}/backward_${i}_${j}.flo" "${folderName}/reliable_${j}_${i}.pgm"

    fi

    if [ ! -f $file1 ]; then
      echo "not a file"
      loopWork=0
    fi

  done
  i=$[$i + 1]

done
