# config hook path
git config core.hooksPath hooks
echo '##### CREATING SCRATCH ORG #####'
SCRATCH_ALIAS=$1
PROJECT_NAME=${PWD##*/}
SCRATCH_ALIAS="${SCRATCH_ALIAS:-$PROJECT_NAME-`git branch | grep \* | cut -d ' ' -f2`}" 
sf org create scratch --definition-file config/project-scratch-def.json --alias $SCRATCH_ALIAS --wait 15 --set-default
echo '##### PUSHING METADATA #####'
sf project deploy start --ignore-conflicts --target-org $SCRATCH_ALIAS
echo '##### DEPLOYING POST PUSH METADATA (ACTIVE LIGHTNING THEME) #####'
sf project deploy start --source-dir ./post-push-source --ignore-conflicts --target-org $SCRATCH_ALIAS
echo '##### ASSIGNING PERMISSIONS #####'
sf org assign permset --name Restaurants_Management --target-org $SCRATCH_ALIAS
echo '##### IMPORTING DUMMY DATA #####'
sf texei data import --inputdir ./data --target-org $SCRATCH_ALIAS
echo '##### CLEANING STANDARD LAYOUTS #####'
sf texei source layouts cleanorg --target-org $SCRATCH_ALIAS
echo '##### ACTIVATING AGENT #####'
sf agent activate --api-name Restaurant_Agent --target-org $SCRATCH_ALIAS
echo '##### CLEANING TRACKING #####'
sf project reset tracking --no-prompt --target-org $SCRATCH_ALIAS
echo '##### OPENING SCRATCH ORG #####'
sf org open --path /lightning/app/c__Restaurants_Management --target-org $SCRATCH_ALIAS