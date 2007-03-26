#!/bin/sh

[ -f "Makefile_support" ] && rm -f Makefile_support

GHCVS=`ghc -V`
GHCV=`expr "$GHCVS" : ".*version \([0-9]\.[0-9]\).*"`

if [ "$GHCV" != "6.6" ]; then
  echo "# Just for ghc < 6.6" > Makefile_support 
  echo "HC_OPTS	+= -syslib lang" >> Makefile_support
fi
