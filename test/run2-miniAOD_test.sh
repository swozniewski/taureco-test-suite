#!/usr/bin/env bash

cmsDriver.py run2-miniAOD_$1  --conditions auto:run2_mc -n 50 --era Run2_2016 --eventcontent MINIAODSIM --runUnscheduled  -s PAT --datatier MINIAODSIM --pileup AVE_35_BX_25ns --filein  file:run2-miniAOD_input.root  --fileout file:run2-miniAOD_${1}.root
