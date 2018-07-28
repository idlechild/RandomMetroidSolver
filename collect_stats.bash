#!/bin/bash

RANDO=./randomizer.py
SOLVER=./solver.py
GET_STATS=./get_stats.py

presets="noob flo manu speedrunner"
progs="slowest slow medium fast fastest random"
n=20
test_set=$1

nb_cpu=$(grep processor /proc/cpuinfo | wc -l)
#nb_cpu=1

[ -z "$test_set" ] && test_set="seeds"

[ -d "$test_set" ] && {
    echo "$test_set already exists" >&2
    exit 1
}

errlog=stats_errors_${test_set}.log

[ -f "$errlog" ] && {
    echo "$errlog already exists" >&2
    exit 1
}

mkdir -p $test_set/old_seeds
mv VARIA_Randomizer_*.json $test_set/old_seeds 2> /dev/null
rmdir $test_set/old_seeds 2> /dev/null
abort_msg=

function worker {
    p=$1
    speed=$2
    i=$3
    dest=$4
    extra=$5
    echo
    echo "**** $dest $i ****"
    echo $extra
    seed=$(head -c 500 /dev/urandom | tr -dc '0-9' | fold -w 7 | head -n 1 | sed 's/^0*//')
    errfile=/tmp/VARIA_stats_worker_${seed}_${speed}_${p}
    echo "errfile = $errfile"
    $RANDO --seed ${seed} -i $speed $extra --param diff_presets/$p.json
    [ $? -ne 0 ] && {
	echo "RANDO failed"  > $errfile
	echo "preset : $p" >> $errfile
	echo "seed : $seed" >> $errfile
	echo "speed : $speed" >> $errfile
	echo "extra options : $extra" >> $errfile
	return
    }
    rom=$(ls VARIA_Randomizer_*${seed}_${p}*.json)
    dot=$(ls VARIA_Randomizer_*${seed}_${p}*.dot 2> /dev/null)
    rom1st=${dest}/${rom/json/1st}
    solver_log=${dest}/${rom/json/log}
    ls $rom > /dev/null 2>&1 && {
	$SOLVER $rom --param diff_presets/$p.json  --difficultyTarget 5 --displayGeneratedPath -1 $rom1st > $solver_log
	[ $? -ne 0 ] && {
	    echo "SOLVER failed"  > $errfile
	    echo "rom : $rom" >> $errfile
	    echo "extra options : $extra" >> $errfile
	    return
	}
	mv $rom $dest
	[ ! -z "$dot" ] && {
	    mv $dot $dest
	}
    }
}

function get_difficulties() {
    echo "Seed;Difficulty"
    for slog in $*; do
	seed=$(basename $slog .log)
	diff=$(tail -2 $slog | head -1  | awk '{print $1}' | sed -e 's+[(,]*++g')
	echo "${seed};${diff}"
    done
}

function reset_workers() {
    workers=0
    rm /tmp/VARIA_stats_worker* 2> /dev/null
}

function wait_workers() {
    wait
    QUIT=1
    errfiles=$(ls -1 /tmp/VARIA_stats_worker* 2> /dev/null)
    for errfile in $errfiles; do
	echo
	echo "Worker ERROR $errfile :"
	cat $errfile | tee -a $errlog 
	echo
	grep -q 'SOLVER failed' $errfile
	if [ $? -eq 0 ]; then
	    QUIT=0
	fi
	rm -f $errfile
    done
    if [ ${QUIT} -eq 1 ]; then
	reset_workers
    else
	exit 1
    fi
}

function gen_seeds() {
    base_dir=$test_set/$1/$2/$3
    base_extra=$4
    progDiff=$3
    for p in $presets; do
	# if [ $p = 'noob' ]; then
	#     noob='--maxDifficulty harder'
	# fi
	mkdir -p $base_dir/$p
	for speed in $progs; do
	    extra="$base_extra --progressionDifficulty $progDiff $noob"
#	    extra="$base_extra --superQty 1 --powerBombQty 1 --missileQty 4.6"
	    if [[ $speed != "random" ]]; then
		extra="$extra --speedScrewRestriction"
	    fi
	    #	extra="--speedScrewRestriction --superFun Combat --superFun Movement"
	    if [[ $speed == slow* ]] || [[ $speed == "medium" ]]; then
		extra="$extra --spreadItems"
	    fi
	    if [[ $speed != "fastest" ]]; then
		extra="$extra --suitsRestriction"
	    fi
	    dest=$base_dir/$p/$speed
	    mkdir $dest
	    reset_workers
	    for i in $(seq 1 $n); do
		if [ ${workers} -ge ${nb_cpu} ]; then
		    wait_workers
		fi
		worker ${p} ${speed} ${i} ${dest} "$extra" &
		renice -n 10 -p $!
		let workers=${workers}+1
	    done
	    wait_workers
	    $GET_STATS $dest/*.1st
	    get_difficulties $dest/*.log > $dest/difficulties.csv
	    mv *stats.csv $dest
	done
    done
}

# do it again with random
DIFFS=("" "" "" "" "" "" "--maxDifficulty easy" "--maxDifficulty medium" "--maxDifficulty hard" "--maxDifficulty harder" "--maxDifficulty hardcore" "--maxDifficulty mania")

for A in "area" "standard"; do
    for B in "classic" "full"; do
	PARAMS=""
	if [ $A = "area" ]; then
	    PARAMS="${PARAMS} --area --dot"
	fi
	if [ $B = "full" ]; then
	    PARAMS="${PARAMS} --fullRandomization"
	fi

	# add randomized parameters
	#	PARAMS="${PARAMS} --randomRestrictions --superFun random --energyQty random --missileQty 0 --superQty 0 --powerBombQty 0 --minorQty 0"
	PARAMS="${PARAMS} --randomRestrictions --energyQty random --missileQty 0 --superQty 0 --powerBombQty 0 --minorQty 0"

	let S=$RANDOM%${#DIFFS[@]}
	DIFF=${DIFFS[$S]}
	PARAMS="${PARAMS} ${DIFF}"

	gen_seeds "$A" "$B" "random" "$PARAMS"
    done
done

for A in "standard" "area"; do
    for B in "classic" "full"; do
	for C in "easier" "harder" "normal"; do
	    PARAMS=""
	    if [ $A = "area" ]; then
		PARAMS="${PARAMS} --area --dot"
	    fi
	    if [ $B = "full" ]; then
		PARAMS="${PARAMS} --fullRandomization"
	    fi
	    gen_seeds "$A" "$B" "$C" "$PARAMS"
	done
    done
done

