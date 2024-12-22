#!/bin/bash

cd src &&
../cycompile.py server.pyx -O1 &&
rm -f *.log server.cpp &&
mv server ../ -f &&
cd ../ &&
sudo ./server
