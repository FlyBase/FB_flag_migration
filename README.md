# FB_flag_migration
Scripts to handle export of FlyBase triage flag and curation status data into the Alliance.


## Scripts


1. `populate_topic_data.pl`  

   Generates json for loading FlyBase triage flag information into the Topic Entity Tag tables in the Alliance ABC literature database.  
  Requires an access token (6th argument when run script) to query for correct topic_entity_tag_source_id

2. `populate_topic_curation_status.pl`  

   Generates json for loading *curation status* information for individual Alliance topics into the Workflow tables in the Alliance ABC literature database.  

3. `populate_workflow_status.pl`  

   Generates json for loading *workflow status* information for user, skim and thin curation into the Workflow tables in the Alliance ABC literature database.  

4. `ticket_scrum-3147-retrieve_deleted_topic.pl`  

   use to retrieve deleted flag from local files at Harvard.  

## Requirements

- Unless stated otherwise, each script requires a FB chado database with the `audit_chado` table (used for for timestamp information).  
- the scripts generally require an access token as an argument, as when used in test mode they attempt to POST json into the stage Alliance ABC literature database (so that the validity of the json can be tested).  

## Retired scripts

The retired folder contains scripts that are no longer used:  

- `ticket_scrum-3147-topic-entity-tag.pl` - this has been replaced by `populate_topic_data.pl`  