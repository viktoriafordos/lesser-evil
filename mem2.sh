PIDs=`ps -C beam.smp -o pid=`
pid=
for i in ${PIDs}; do
    pid=${i}
done

mkdir -p /measurements
logfile="/measurements/mem-${pid}-$(date +%s).csv"
printf "Logfile: %s\n" $logfile

start=$(date +%s)

while mem=$(ps -o rss=,vsz= -p "$pid"); do
    time=$(date +%s)

    printf "%d %s\n" $((time-start)) "$mem" >> "$logfile"

    sleep 1
done
