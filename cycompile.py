#!/usr/bin/env python3
import os, sys

def run(cmd):
	print("Running '%s'" % cmd)
	ret = os.system(cmd)
	if ret:
		print("Command %s failed with return code %d." % (cmd, ret))
		exit(ret)

fp = sys.argv.pop(1)
fn, ext = fp.rsplit(".", 1)

run("cython --cplus --embed -3 -v %s" % fp)
run("g++ -std=c++23 %s%s.cpp -o %s $(python3-config --includes --ldflags --embed)" % ((" ".join(sys.argv[1:]) + " ") if len(sys.argv) > 1 else "", fn, fn))
#run("sudo ./%s" % fn)
