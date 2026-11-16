set -e
W=$HOME/basedos-work
rm -rf $W/harvest-test
python3 /mnt/e/projects/spruceOS-gkd350hultra/basedos/tools/harvest.py $W/stock-root /mnt/e/projects/spruceOS-gkd350hultra/basedos/manifest/harvest.list $W/harvest-test/root
grep -c "needed by" $W/harvest-test/harvest-report.txt
grep "needed by" $W/harvest-test/harvest-report.txt | awk -F'\t' '{print $1}' | head -60 | tr '\n' ' '
