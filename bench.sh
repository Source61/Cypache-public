#!/bin/bash

wrk -t8 -c120 -d1s http://$@
