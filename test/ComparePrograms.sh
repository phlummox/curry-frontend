cmpPrograms=../dist/build/cmpPrograms/cmpPrograms

(cd lib/.curry && ls *.fcy) | xargs -i -n 1 $cmpPrograms $1/.curry/'{}' "$1"2/.curry/'{}' | tee errors.txt
(cd lib/.curry && ls *.fint) | xargs -i -n 1 $cmpPrograms $1/.curry/'{}' "$1"2/.curry/'{}' | tee -a errors.txt

echo "============================="
echo "Errors: "
echo "============================="

cat errors.txt | grep "Not equal"

exit 0