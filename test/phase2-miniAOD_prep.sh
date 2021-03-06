#!/usr/bin/env bash

cmsDriver.py phase2-miniAOD_input  --conditions auto:phase2_realistic_T15 -n 50 --era Phase2C9 --eventcontent RECOSIM --runUnscheduled  --filein das:/RelValTTbar_14TeV/CMSSW_11_0_0_pre13-110X_mcRun4_realistic_v2_2026D49noPU-v1/GEN-SIM-DIGI-RAW -s RAW2DIGI,L1Reco,RECO,RECOSIM --datatier GEN-SIM-RECO --geometry Extended2026D49 --fileout file:phase2-miniAOD_input.root
